#!/usr/bin/env python3
"""Publish the event commit's unsigned WDA master using create-only R2 writes."""

import hashlib
import json
import logging
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path


BUCKET = "wda-masters"
IPA_NAME = "WebDriverAgentRunner-Runner.ipa"
APP_NAME = "WebDriverAgentRunner-Runner.app"
BUNDLE_ID = "app.kilo.automation.simple"
MAX_IPA_BYTES = 268435456
MAX_ENTRIES = 10000
MAX_UNPACKED_BYTES = 1073741824
MAX_NAME_BYTES = 1024
CHUNK_BYTES = 1024 * 1024
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
COMMIT_PATTERN = re.compile(r"[0-9a-f]{40}")
MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}
SECRET_ENV = {"R2_WDA_MASTERS_TOKEN_JSON", "GITHUB_TOKEN", "GH_TOKEN"}


class PublicationError(Exception):
    def __init__(self, stage, code):
        self.stage = stage
        self.code = code
        super().__init__(code)


@contextmanager
def phase(stage, code):
    try:
        yield
    except PublicationError:
        raise
    except Exception:
        raise PublicationError(stage, code) from None


def require(condition, stage, code):
    if not condition:
        raise PublicationError(stage, code)


def mask(value):
    if isinstance(value, str) and value:
        escaped = value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::add-mask::{escaped}", flush=True)


def tool_environment():
    return {key: value for key, value in os.environ.items() if key not in SECRET_ENV}


@dataclass(frozen=True)
class Configuration:
    account_id: str
    access_key: str = field(repr=False)
    secret_key: str = field(repr=False)
    github_token: str = field(repr=False)
    runner_temp: Path
    summary: Path


def configuration():
    # Mask parsed strings before validating other fields or emitting diagnostics.
    with phase("configuration", "configuration_invalid"):
        token = json.loads(os.environ.get("R2_WDA_MASTERS_TOKEN_JSON", ""))
        if isinstance(token, dict):
            mask(token.get("access_key_id"))
            mask(token.get("secret_access_key"))
        github_token = os.environ.get("GITHUB_TOKEN", "")
        mask(github_token)
        require(isinstance(token, dict), "configuration", "configuration_invalid")
        access_key = token.get("access_key_id")
        secret_key = token.get("secret_access_key")
        for value in (access_key, secret_key, github_token):
            require(isinstance(value, str) and bool(value.strip()),
                    "configuration", "configuration_invalid")
        account_id = os.environ.get("R2_ACCOUNT_ID", "")
        require(re.fullmatch(r"[0-9a-fA-F]{32}", account_id) is not None,
                "configuration", "configuration_invalid")
        temp_value = os.environ.get("RUNNER_TEMP", "")
        summary_value = os.environ.get("GITHUB_STEP_SUMMARY", "")
        require(bool(temp_value) and bool(summary_value),
                "configuration", "configuration_invalid")
        runner_temp, summary = Path(temp_value), Path(summary_value)
        require(runner_temp.is_absolute() and runner_temp.is_dir()
                and summary.is_absolute(), "configuration", "configuration_invalid")
        # Check local record availability before building or writing remotely.
        with summary.open("a", encoding="utf-8"):
            pass
        return Configuration(account_id.lower(), access_key, secret_key,
                             github_token, runner_temp, summary)


def run_tool(arguments, root):
    result = subprocess.run(arguments, cwd=root, env=tool_environment(),
                            check=True, capture_output=True)
    return result.stdout.decode("utf-8", errors="strict").strip()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the job token to a redirect target.
        return None


class Source:
    def __init__(self, root, config):
        self.token = config.github_token
        self.opener = urllib.request.build_opener(NoRedirect())
        with phase("admission", "invalid_context"):
            self.tag = os.environ.get("GITHUB_REF_NAME", "")
            self.repository = os.environ.get("GITHUB_REPOSITORY", "")
            event_sha = os.environ.get("GITHUB_SHA", "").lower()
            event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
            version = json.loads((root / "package.json").read_text())["version"]
            require(os.environ.get("GITHUB_EVENT_NAME") == "push"
                    and os.environ.get("GITHUB_REF_TYPE") == "tag"
                    and isinstance(event, dict) and event.get("deleted") is False
                    and event.get("ref") == f"refs/tags/{self.tag}"
                    and re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z._-]{0,63}", self.tag)
                    and isinstance(version, str) and bool(version)
                    and re.fullmatch(r"titan-" + re.escape(version) + r"-[1-9][0-9]*", self.tag)
                    and re.fullmatch(r"[0-9A-Za-z_.-]+/[0-9A-Za-z_.-]+", self.repository)
                    and COMMIT_PATTERN.fullmatch(event_sha), "admission", "invalid_context")
            self.commit = run_tool(["git", "--no-pager", "rev-parse", "--verify",
                                    f"{event_sha}^{{commit}}"], root)
            head = run_tool(["git", "--no-pager", "rev-parse", "--verify", "HEAD^{commit}"], root)
            require(COMMIT_PATTERN.fullmatch(self.commit) and self.commit == head,
                    "admission", "invalid_context")

    def get(self, path, missing_ref=False):
        with phase("source", "source_unavailable"):
            request = urllib.request.Request(
                f"https://api.github.com/repos/{self.repository}/git/{path}",
                headers={"Authorization": f"Bearer {self.token}",
                         "Accept": "application/vnd.github+json",
                         "X-GitHub-Api-Version": "2022-11-28",
                         "User-Agent": "wda-master-publisher"}, method="GET")
            try:
                with self.opener.open(request, timeout=30) as response:
                    require(response.status == 200, "source", "source_unavailable")
                    data = response.read(CHUNK_BYTES + 1)
                    require(len(data) <= CHUNK_BYTES, "source", "source_unavailable")
                    result = json.loads(data)
                    require(isinstance(result, dict), "source", "source_unavailable")
                    return result
            except urllib.error.HTTPError as error:
                with error:
                    if missing_ref and error.code == 404:
                        raise PublicationError("source", "master_conflict") from None
                raise PublicationError("source", "source_unavailable") from None

    def check(self):
        with phase("source", "source_unavailable"):
            ref = self.get("ref/tags/" + urllib.parse.quote(self.tag, safe=""), missing_ref=True)
            require(ref.get("ref") == f"refs/tags/{self.tag}", "source", "source_unavailable")
            obj = ref.get("object")
            seen = set()
            # A bounded tag-object chain handles lightweight and annotated tags.
            for _ in range(32):
                require(isinstance(obj, dict), "source", "source_unavailable")
                sha, kind = obj.get("sha"), obj.get("type")
                require(isinstance(sha, str) and COMMIT_PATTERN.fullmatch(sha)
                        and sha not in seen, "source", "source_unavailable")
                seen.add(sha)
                if kind == "commit":
                    require(sha == self.commit, "source", "master_conflict")
                    return
                require(kind == "tag", "source", "source_unavailable")
                obj = self.get("tags/" + sha).get("object")
            raise PublicationError("source", "source_unavailable")


def normalize_plists(app):
    plugin = app / "PlugIns/WebDriverAgentRunner.xctest"
    for bundle in (app, plugin):
        info_path = bundle / "Info.plist"
        with info_path.open("rb") as source:
            info = plistlib.load(source)
        require(isinstance(info, dict), "artifact", "artifact_invalid")
        info["CFBundleIdentifier"] = BUNDLE_ID
        environment = info.setdefault("LSEnvironment", {})
        require(isinstance(environment, dict), "artifact", "artifact_invalid")
        environment["WDA_PRODUCT_BUNDLE_IDENTIFIER"] = BUNDLE_ID
        if bundle == app:
            info["CFBundleDisplayName"] = "TrafficTitans"
            info["CFBundleName"] = "TrafficTitans"
        executable = info.get("CFBundleExecutable")
        require(isinstance(executable, str) and executable not in ("", ".", "..")
                and "/" not in executable and "\\" not in executable,
                "artifact", "artifact_invalid")
        binary = bundle / executable
        require(binary.is_file() and bool(binary.stat().st_mode & 0o111),
                "artifact", "artifact_invalid")
        require(run_tool(["xcrun", "lipo", "-archs", str(binary)], app).split() == ["arm64"],
                "artifact", "artifact_invalid")
        with info_path.open("wb") as destination:
            plistlib.dump(info, destination, fmt=plistlib.FMT_XML)
    framework = plugin / "Frameworks/WebDriverAgentLib.framework/WebDriverAgentLib"
    require(framework.is_file(), "artifact", "artifact_invalid")
    require(run_tool(["xcrun", "lipo", "-archs", str(framework)], app).split() == ["arm64"],
            "artifact", "artifact_invalid")


def excluded(name):
    return (name in {"_CodeSignature", "__MACOSX", ".DS_Store"}
            or name.startswith("._") or name.endswith((".dSYM", ".mobileprovision", ".provisionprofile")))


def strip_signatures(app):
    otool = run_tool(["xcrun", "--find", "otool"], app)
    for path in sorted(app.rglob("*")):
        require(not path.is_symlink(), "artifact", "artifact_invalid")
        if not path.is_file():
            continue
        with path.open("rb") as binary:
            magic = binary.read(4)
        if magic not in MACHO_MAGICS:
            continue
        load_commands = run_tool([otool, "-arch", "all", "-l", str(path)], app)
        require("Load command " in load_commands, "artifact", "artifact_invalid")
        if re.search(r"^\s*cmd LC_CODE_SIGNATURE\s*$", load_commands, re.MULTILINE):
            run_tool(["codesign", "--remove-signature", str(path)], app)
            load_commands = run_tool([otool, "-arch", "all", "-l", str(path)], app)
        require("Load command " in load_commands
                and not re.search(r"^\s*cmd LC_CODE_SIGNATURE\s*$", load_commands, re.MULTILINE),
                "artifact", "artifact_invalid")


def safe_entry(name):
    logical = name.removesuffix("/")
    parts = logical.split("/")
    require(bool(logical) and len(name.encode("utf-8")) <= MAX_NAME_BYTES
            and "\\" not in name and ":" not in name
            and all(part not in ("", ".", "..") and not excluded(part) for part in parts)
            and not any(ord(char) < 32 or 127 <= ord(char) <= 159 for char in name)
            and (logical == "Payload" or logical == f"Payload/{APP_NAME}"
                 or logical.startswith(f"Payload/{APP_NAME}/")), "artifact", "artifact_invalid")
    return logical


def package(stage, ipa):
    paths = [stage / "Payload", *sorted((stage / "Payload").rglob("*"))]
    require(1 <= len(paths) <= MAX_ENTRIES, "artifact", "artifact_invalid")
    names = set()
    unpacked_bytes = 0
    with zipfile.ZipFile(ipa, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=False) as archive:
        for path in paths:
            mode = path.lstat().st_mode
            require(stat.S_ISREG(mode) or stat.S_ISDIR(mode), "artifact", "artifact_invalid")
            name = path.relative_to(stage).as_posix() + ("/" if path.is_dir() else "")
            logical = safe_entry(name)
            require(logical not in names, "artifact", "artifact_invalid")
            names.add(logical)
            if path.is_file():
                unpacked_bytes += path.stat().st_size
            require(unpacked_bytes <= MAX_UNPACKED_BYTES, "artifact", "artifact_invalid")
            archive.write(path, name)
    require(1 <= ipa.stat().st_size <= MAX_IPA_BYTES, "artifact", "artifact_invalid")
    with zipfile.ZipFile(ipa) as archive:
        entries = archive.infolist()
        require(len(entries) == len(names)
                and sum(entry.file_size for entry in entries) == unpacked_bytes
                and all(entry.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                        for entry in entries), "artifact", "artifact_invalid")
    hasher = hashlib.sha256()
    with ipa.open("rb") as source:
        while chunk := source.read(CHUNK_BYTES):
            hasher.update(chunk)
    return hasher.hexdigest()


def build_candidate(root, workspace):
    derived = workspace / "DerivedData"
    with phase("build", "build_failed"):
        with (workspace / "build.log").open("wb") as log:
            subprocess.run([
                "xcodebuild", "build-for-testing", "-project", "WebDriverAgent.xcodeproj",
                "-scheme", "WebDriverAgentRunner", "-configuration", "Debug",
                "-destination", "generic/platform=iOS", "-sdk", "iphoneos",
                "-derivedDataPath", str(derived), "ARCHS=arm64", "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "CODE_SIGN_ENTITLEMENTS=",
                "DEVELOPMENT_TEAM=", f"PRODUCT_BUNDLE_IDENTIFIER={BUNDLE_ID}",
                "INFOPLIST_OUTPUT_FORMAT=XML",
            ], cwd=root, env=tool_environment(), check=True, stdout=log, stderr=subprocess.STDOUT)
    with phase("artifact", "artifact_invalid"):
        stage = workspace / "stage"
        app = stage / "Payload" / APP_NAME
        shutil.copytree(derived / "Build/Products/Debug-iphoneos" / APP_NAME, app,
                        symlinks=False,
                        ignore=lambda directory, names: [name for name in names if excluded(name)])
        for framework in (app / "Frameworks").glob("XC*.framework"):
            require(framework.is_dir(), "artifact", "artifact_invalid")
            shutil.rmtree(framework)
        normalize_plists(app)
        strip_signatures(app)
        # Signature removal can touch bundle resources; none may enter the ZIP.
        for directory, dirs, files in os.walk(app, topdown=True):
            for name in list(dirs):
                if excluded(name):
                    shutil.rmtree(Path(directory) / name)
                    dirs.remove(name)
            for name in files:
                if excluded(name):
                    (Path(directory) / name).unlink()
        ipa = workspace / IPA_NAME
        digest = package(stage, ipa)
        return ipa, digest


class MasterPublisher:
    def __init__(self, config, source):
        with phase("configuration", "configuration_invalid"):
            import boto3
            from botocore.config import Config

            self.client = boto3.client(
                "s3", endpoint_url=f"https://{config.account_id}.r2.cloudflarestorage.com",
                aws_access_key_id=config.access_key, aws_secret_access_key=config.secret_key,
                region_name="auto", verify=True,
                config=Config(signature_version="s3v4", s3={"addressing_style": "path"},
                              connect_timeout=10, read_timeout=120,
                              retries={"mode": "standard", "total_max_attempts": 3},
                              request_checksum_calculation="when_required",
                              response_checksum_validation="when_required"))
        self.source = source
        self.ipa_key = f"{source.tag}/{IPA_NAME}"
        self.sidecar_key = self.ipa_key + ".sha256"

    @contextmanager
    def object(self, key):
        from botocore.exceptions import ClientError

        with phase("storage", "storage_unavailable"):
            try:
                response = self.client.get_object(Bucket=BUCKET, Key=key)
            except ClientError as error:
                if error.response.get("Error", {}).get("Code") == "NoSuchKey":
                    yield None
                    return
                raise
            body = response.get("Body")
            require(body is not None, "storage", "storage_unavailable")
            try:
                yield response
            finally:
                body.close()

    def read_master(self):
        with self.object(self.ipa_key) as response:
            if response is None:
                return None
            length = response.get("ContentLength")
            require(type(length) is int and 1 <= length <= MAX_IPA_BYTES,
                    "master", "master_conflict")
            metadata = response.get("Metadata")
            require(isinstance(metadata, dict)
                    and metadata.get("source-commit") == self.source.commit
                    and metadata.get("titan-tag") == self.source.tag
                    and isinstance(metadata.get("sha256"), str)
                    and SHA256_PATTERN.fullmatch(metadata["sha256"]), "master", "master_conflict")
            hasher, received = hashlib.sha256(), 0
            while chunk := response["Body"].read(CHUNK_BYTES):
                require(isinstance(chunk, bytes) and len(chunk) <= CHUNK_BYTES,
                        "storage", "storage_unavailable")
                received += len(chunk)
                require(received <= MAX_IPA_BYTES, "master", "master_conflict")
                hasher.update(chunk)
            require(received == length, "storage", "storage_unavailable")
            digest = hasher.hexdigest()
            require(metadata["sha256"] == digest, "master", "master_conflict")
            return digest

    def observe_sidecar(self):
        with self.object(self.sidecar_key) as response:
            if response is None:
                return None
            data = response["Body"].read(66)
            return data, response.get("ContentLength")

    def sidecar_hash(self, observation):
        if observation is None:
            return None
        data, length = observation
        require(isinstance(data, bytes) and re.fullmatch(rb"[0-9a-f]{64}\n", data)
                and type(length) is int and length == 65, "sidecar", "master_conflict")
        return data[:64].decode("ascii")

    def read_sidecar(self):
        return self.sidecar_hash(self.observe_sidecar())

    def create(self, *, sidecar, body, digest):
        parameters = {
            "Bucket": BUCKET, "Key": self.sidecar_key if sidecar else self.ipa_key,
            "Body": body, "IfNoneMatch": "*",
            "ContentType": "text/plain" if sidecar else "application/octet-stream",
        }
        if not sidecar:
            parameters["Metadata"] = {"source-commit": self.source.commit,
                                      "titan-tag": self.source.tag, "sha256": digest}
        self.source.check()
        try:
            self.client.put_object(**parameters)
            return True
        except Exception:
            # Even a lost acknowledgment or 409/412 is resolved only by the next GET.
            return False

    def publish(self, root, workspace):
        self.source.check()
        digest = self.read_master()
        if digest is None:
            observation = self.observe_sidecar()
            if observation is not None:
                # Interleaved reads can observe a sidecar after an earlier absent IPA.
                digest = self.read_master()
                require(digest is not None, "master", "master_conflict")
                require(self.sidecar_hash(observation) == digest, "sidecar", "master_conflict")
            else:
                ipa, candidate_hash = build_candidate(root, workspace)
                with phase("storage", "storage_unavailable"):
                    with ipa.open("rb") as body:
                        acknowledged = self.create(sidecar=False, body=body, digest=candidate_hash)
                digest = self.read_master()
                require(digest is not None, "ipa_readback", "storage_unavailable")
                require(digest == candidate_hash, "ipa_readback", "master_conflict")
                if not acknowledged:
                    print("stage=ipa_readback reconciled=canonical", flush=True)
        sidecar = self.read_sidecar()
        if sidecar is None:
            acknowledged = self.create(sidecar=True, body=(digest + "\n").encode("ascii"), digest=digest)
            sidecar = self.read_sidecar()
            require(sidecar is not None, "sidecar_readback", "storage_unavailable")
            require(sidecar == digest, "sidecar_readback", "master_conflict")
            if not acknowledged:
                print("stage=sidecar_readback reconciled=canonical", flush=True)
        require(sidecar == digest, "sidecar", "master_conflict")
        final_hash = self.read_master()
        final_sidecar = self.read_sidecar()
        require(final_hash is not None and final_sidecar is not None,
                "pair_readback", "storage_unavailable")
        require(final_hash == digest == final_sidecar, "pair_readback", "master_conflict")
        self.source.check()
        return final_hash


def record(config, source, digest):
    text = (
        "Unsigned WDA master for backend re-signing (CP-WDA-ONBOARDING-20261116).\n\n"
        f"Tag: {source.tag}\n"
        f"Source commit: {source.commit}\n"
        f"SHA-256: {digest}\n"
        f"IPA: r2://{BUCKET}/{source.tag}/{IPA_NAME}\n"
        f"SHA-256 sidecar: r2://{BUCKET}/{source.tag}/{IPA_NAME}.sha256\n\n"
        "This master is unsigned. Backend hash verification and a successful lab install/launch "
        "are required before customer rollout.\n"
    )
    with phase("record", "record_unavailable"):
        with config.summary.open("a", encoding="utf-8", newline="\n") as summary:
            summary.write(text)
        print(text, end="", flush=True)


def main():
    logging.disable(logging.CRITICAL)
    config = configuration()
    root = Path(__file__).resolve().parents[2]
    source = Source(root, config)
    publisher = MasterPublisher(config, source)
    with phase("workspace", "configuration_invalid"):
        with tempfile.TemporaryDirectory(prefix="wda-master-", dir=config.runner_temp) as temporary:
            digest = publisher.publish(root, Path(temporary))
            record(config, source, digest)


if __name__ == "__main__":
    try:
        main()
    except PublicationError as error:
        print(f"stage={error.stage} code={error.code}", file=sys.stderr, flush=True)
        sys.exit(1)
    except Exception:
        print("stage=publisher code=configuration_invalid", file=sys.stderr, flush=True)
        sys.exit(1)
