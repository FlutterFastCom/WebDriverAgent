# Publish permanent unsigned WDA masters from Titan tags

Status: DONE
Risk-Class: security
Risk-Class-Justification: This introduces a bucket-scoped write credential and publishes executable input to the backend signing pipeline. Conditional object creation, source identity, unsigned packaging and a truthful publication record are security boundaries.
Version-Impact: minor
Unit-Size: small
Created: 2026-11-18
Feature-Folder: /Users/dmitrydyachenko/orca/workspaces/titan-ai-mediator/testing-strategy/missions/2026-11-14-automated-iphone-self-onboarding-user-requests-p/features/wda-fork-master-build
Checkpoint: CP-WDA-ONBOARDING-20261116
Execution mode: single unit, single builder turn
Native-Validation: UNAVAILABLE under the WDA-only exception authorized in relay/answers.round1.json, native_gate_policy choice A, 2026-11-18. No predecessor or design blocker remains.
Test-Mandate: SUSPENDED. Create, edit, adapt and run no tests, fixtures, coverage or red proofs. Acceptance is observable behavior verified by the real-stack TESTBED.

## Goal

A manually pushed Titan tag produces a permanent unsigned iOS-device IPA in R2, its SHA-256 sidecar, and an Actions job-summary record identifying those exact bytes. Deliver AC-01 through AC-09 together, with interrupted publication resumable without rebuilding an existing master or replacing its bytes. The binding consumer outcome is the verified R2 pair; the human-facing record does not require a GitHub Release.

## Non-Goals

No WDA endpoint or application-source changes, backend/agent changes, Apple API calls, signing, profile/certificate inputs, GitHub Release API calls, remote Git tag/ref writes, default-branch changes, extra GitHub credential, upstream release migration, deletion, expiry, new bucket, or object-versioning mechanism. Automatic GitHub Releases are deferred under relay/answers.json precheck_gaps; the human-facing publication record is P4's Actions summary. Do not push a tag, upload an object or provision a secret during implementation; the TESTBED/operator exercises the resulting workflow. Existing tests require no change or deletion.

## Files To Modify

The production automation scope is exactly the following three files, including the two additions.

| File | Action | Contract |
| --- | --- | --- |
| `.github/workflows/wda-master.yml` | Create | Titan-tag-only workflow; explicit toolchain, permissions, concurrency, dependency installation and publisher invocation. |
| `Scripts/ci/publish-master.py` | Create | One concrete unsigned-master publication flow: context admission, existing-master reconciliation, build/package, create-only R2 writes and job-summary recording. |
| `Scripts/embed-runner-icon.sh` | Modify | Prevent entry to the existing signature-inspection/re-signing block when `CODE_SIGNING_ALLOWED=NO`; retain icon embedding and the behavior of signed builds. |

## Companion files

| File | Contract |
| --- | --- |
| `README.md` | Add the operator-facing Titan master instructions: credential/variable schema, canonical tag recipe, permanent keys, unsigned artifact, retries/conflicts, Actions publication-record location, deferred GitHub Releases, and backend lab rollout boundary. No default-branch landing or extra GitHub credential is a prerequisite. |
| `package.json` | Release companion, explicitly authorized in planned_files. Increase the version only if the repository's actual staged-runtime guard requires it and the worktree version does not already satisfy that guard; otherwise leave byte-identical. Do not use `npm version`, which runs the unrelated Info.plist/staging hook. No dependency or script change here. |

Only the architect edits `tasks/`. Report any discovered census deltas, with path, token and added/removed disposition, under Issues/findings in build-report.md. Do not amend this spec or its census.

## Architect Intake

Intent-Surfaces: wda-master-publication
GROUNDED-IN: README.md, Scripts/ci/build-real.sh, WebDriverAgent.xcodeproj/xcshareddata/xcschemes/WebDriverAgentRunner.xcscheme
LOUD FINDING: NO-OWNING-INTENT-DOC — this fork contains no docs/business/intent-surface-index.md. Product authority is the supplied intake.md RELAY BRIEF and the already-shipped backend CP-WDA-ONBOARDING-20261116 contract, cited in design.md. Do not manufacture a Rust intent registry in this Objective-C fork.

```architect-intake-v1 json
{
  "intent_surfaces": ["wda-master-publication"],
  "grounded_in": [
    "README.md",
    "Scripts/ci/build-real.sh",
    "WebDriverAgent.xcodeproj/xcshareddata/xcschemes/WebDriverAgentRunner.xcscheme"
  ],
  "invariants": [
    {
      "id": "permanent-tag-pathed-wda-masters",
      "universal": "Every master-object write issued by the new publisher targets one of the two fixed wda-masters keys for its admitted Titan tag, uses atomic create-only PutObject, and never replaces or deletes an existing object. Every successful publication record describes the streamed, verified remote IPA hash and the matching sidecar; the publisher never calls the GitHub Release API or writes a Git ref.",
      "census_needle": "wda-masters",
      "search_roots": [".github/", "Scripts/", "README.md", "package.json"],
      "planned_files": [
        ".github/workflows/wda-master.yml",
        "Scripts/ci/publish-master.py",
        "Scripts/embed-runner-icon.sh",
        "README.md",
        "package.json"
      ],
      "sites": [
        {"path": ".github/workflows/wda-master.yml", "classification": "migrated", "reason": "New workflow identifies its wda-masters publication purpose and invokes the sole master writer."},
        {"path": "Scripts/ci/publish-master.py", "classification": "migrated", "reason": "New fixed-bucket writer and reconciliation reader; owns both object keys and the verified Actions publication record."},
        {"path": "README.md", "classification": "migrated", "reason": "Publishes the same permanent bucket/key contract and token provisioning instructions."}
      ]
    },
    {
      "id": "unsigned-build-does-not-resign-icons",
      "universal": "When CODE_SIGNING_ALLOWED is NO, the icon hook retains its icon and plist work but enters none of its signature-discovery or re-signing branch. The master publisher invokes this unsigned build setting and never signs the packaged application.",
      "census_needle": "CODE_SIGNING_ALLOWED",
      "search_roots": [".github/", "Scripts/", "README.md", "package.json"],
      "planned_files": [
        ".github/workflows/wda-master.yml",
        "Scripts/ci/publish-master.py",
        "Scripts/embed-runner-icon.sh",
        "README.md",
        "package.json"
      ],
      "sites": [
        {"path": "Scripts/ci/publish-master.py", "classification": "migrated", "reason": "New build caller fixes signing to NO and validates the staged unsigned application."},
        {"path": "Scripts/embed-runner-icon.sh", "classification": "migrated", "reason": "Adds the unsigned-mode guard around the existing signing branch."}
      ]
    }
  ]
}
```

## Scope & Decomposition

One observable slice and one builder turn. The workflow, publisher and invoked icon hook together establish the unsigned artifact and permanent publication contract; a separate storage or packaging unit would have no complete consumer outcome. Three automation source files plus documentation and a conditional version companion fit this turn. There is no repeated migration or codemod. Audit, alternatives, reuse evidence and cross-repo census live once in feature-folder design.md.

## Architecture Locks

### P1 — Admission, toolchain and secret boundary

Add an independent workflow named `Publish unsigned WDA master to wda-masters`. Its only event is `push.tags: ['titan-*']`; no branch, dispatch, release or schedule trigger. Deleted-tag events do not run its job. It never creates a remote Git tag. Use concurrency group `wda-master-${{ github.ref }}` and `cancel-in-progress: false`; conditional storage writes remain the correctness boundary.

Run one job on `macos-15`, timeout 45 minutes. Reuse this repo's `actions/checkout@v7` and `maxim-lobanov/setup-xcode@v1` selection of Xcode `16.4`. Checkout the event SHA, with `persist-credentials: false`, never a default-branch checkout. Select Python `3.12` with `actions/setup-python@v6`; install `boto3==1.44.5` in a job-local virtual environment. This is a CI dependency, not an npm dependency. Do not install the npm/Ruby development stack or run repository tests. Fix workflow/job GitHub permissions to `contents: read`, with every other configurable permission unset/none; never grant contents or workflows write.

Invoke the publisher as `python Scripts/ci/publish-master.py` from the repository root. Its only operator-provided secret is `R2_WDA_MASTERS_TOKEN_JSON`, a JSON object with nonempty string fields `access_key_id` and `secret_access_key`: the S3 credentials generated for ONE R2 Object Read+Write token restricted to the `wda-masters` bucket. `R2_ACCOUNT_ID` is a non-secret repository variable, exactly 32 hex characters; derive `https://<account-id>.r2.cloudflarestorage.com`, region `auto`, fixed bucket `wda-masters`. This is the existing default-jurisdiction bucket contract. No R2_ADMIN key, account administration permission, public bucket URL, Apple secret or extra personal GitHub token. Export the R2 secret and an explicit `GITHUB_TOKEN` environment variable only on the publisher run step. The automatic read-only GitHub token is job-scoped: actions can access `github.token`, and checkout receives it even with `persist-credentials: false`. Explicit env export and credential non-persistence are not action-step isolation. The publisher uses this token only for GitHub GET requests that verify source refs/tags. Missing/malformed configuration, including a missing `GITHUB_STEP_SUMMARY` path, fails before a build or remote write.

The first tag push waits for operator provisioning of `R2_WDA_MASTERS_TOKEN_JSON` and the `R2_ACCOUNT_ID` variable. Provisioning is outside this design and implementation scope; it does not block PLAN_DONE or implementation readiness.

Read `GITHUB_EVENT_NAME`, `GITHUB_REF_TYPE`, `GITHUB_REF_NAME`, `GITHUB_SHA` and `GITHUB_REPOSITORY` from environment as data, without shell interpolation. Require a non-deletion tag push, `ref_type=tag`, tag full-match `^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$` and exact full-match convention `titan-<checked-out package.json version>-<n>`, where the ASCII suffix matches `[1-9][0-9]*`. Escape the package version when constructing that match. Zero, a sign, leading zeroes (including `01`), non-ASCII digits and a missing suffix are `invalid_context`. Resolve the checked-out/event object to its commit and require equality. Handle both annotated and lightweight tags.

At entry, immediately before EACH application-level conditional PutObject call (IPA or sidecar), and after P3's final pair readback, GET the GitHub ref and, for an annotated tag, resolve its tag objects to the source commit. SDK retries inside that call retain its create-only condition and event metadata; they do not repeat the source check. Use authenticated REST GETs with TLS verification, API version `2022-11-28`, per-call timeout 30 seconds, no credential-bearing redirect follow and no application retry loop. If a check observes a missing ref or a different commit, fail `master_conflict` before the next operation; a failed/unreadable lookup is `source_unavailable`. Retain any already committed R2 objects. These checks observe snapshots, not a lock against another maintainer moving/deleting a ref. A move/deletion after a check can race with the next conditional R2 write or the final record. The bytes and metadata stay bound to the original event commit; unobserved later ref changes do not invalidate that immutable artifact or retroactively fail a successful run. The publisher NEVER creates, recreates, moves or deletes a Git tag/ref, including after an observed or unobserved deletion. It makes no GitHub Release API call, so there is no release POST that can recreate a tag. Publish changed code under a new canonical tag.

Mask both parsed S3 credential strings before any diagnostic. Never print the JSON, credentials, auth headers, signed requests, raw exception bodies or environment dumps. Do not enable SDK debug logging, shell tracing or command strings containing secrets. Pass a subprocess environment with the R2 secret and GitHub token removed to build/tool invocations. Use argument arrays and checked subprocess results. Temporary work is private to a new directory beneath `RUNNER_TEMP`, removed on normal exit; cancellation relies on runner disposal and never triggers remote cleanup.

### P2 — Unsigned package compatible with the shipped backend

Only when P3 determines there is no existing IPA, execute `xcodebuild build-for-testing` for project `WebDriverAgent.xcodeproj`, scheme `WebDriverAgentRunner`, configuration `Debug`, destination `generic/platform=iOS`, SDK `iphoneos`, architecture `arm64`, using a fresh derived-data directory beneath that private workspace. This action COMPILES the existing Runner; it never executes XCTest. Fix `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, `CODE_SIGN_IDENTITY=`, `CODE_SIGN_ENTITLEMENTS=`, `DEVELOPMENT_TEAM=`, `PRODUCT_BUNDLE_IDENTIFIER=app.kilo.automation.simple`, `INFOPLIST_OUTPUT_FORMAT=XML`. No provisioning updates, signing commands or profile loading. Preserve the existing scheme icon post-action; the hook's signing branch must additionally require `CODE_SIGNING_ALLOWED` not equal to `NO` (unset retains existing signed-build behavior).

Stage `Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app` under `Payload/`. Keep all compiled Titan WDA code and the nested `PlugIns/WebDriverAgentRunner.xctest/Frameworks/WebDriverAgentLib.framework`. Normalize the generated outer app's `CFBundleIdentifier` to exactly `app.kilo.automation.simple`; Xcode's generated `.xctrunner` suffix is not the backend's accepted legacy bundle identifier. Set the nested test bundle's identifier to the same base. Set the outer `CFBundleDisplayName` and `CFBundleName` to `TrafficTitans`. In both outer and nested test Info.plists, retain/extend `LSEnvironment` with `WDA_PRODUCT_BUNDLE_IDENTIFIER=app.kilo.automation.simple`. Preserve other plist and compiled icon content. Serialize these final plists as XML after all modifications.

Remove direct children matching `Frameworks/XC*.framework` from the OUTER app, preserving the plugin's WebDriverAgentLib and other nonmatching dependencies. Remove every `*.dSYM` directory from the staged app. Remove `_CodeSignature` directories and embedded provisioning profiles from the stage. For any remaining Mach-O that carries a signature, `codesign --remove-signature` is permitted solely as signature removal, without signing identity; never `--sign`, including ad-hoc signing. Inspect every Mach-O/all architectures using the selected Xcode's `otool`; require no remaining `LC_CODE_SIGNATURE`, and fail on inspection errors. No certificate, entitlement blob or profile is added. The unsigned icon hook guard above also prevents a transient re-sign during the build itself.

Package with Python stdlib `zipfile`, Stored/Deflated entries, a single root `Payload/WebDriverAgentRunner-Runner.app/`, and executable permissions retained. Resolve build-time symlinks into regular staged files/directories while copying; do not put symlinks in the archive (the backend rejects them). Do not include build logs, `.xctestrun`, DerivedData, resource-fork metadata, signatures, profiles or dSYMs. Bound the archive to 1..268435456 bytes, at most 10000 entries, at most 1073741824 uncompressed bytes, and entry names at most 1024 UTF-8 bytes. Require safe relative slash-delimited names and no duplicate logical names. These mirror the backend's actual artifact/archive readers. Fail `artifact_invalid` before any PUT if the stage or archive violates the contract. Hash the FINAL ZIP bytes by streaming; never repackage after hashing. The final basename is `WebDriverAgentRunner-Runner.ipa`.

### P3 — Create-once, resumable R2 publication

Use the boto3 S3 client with explicit credentials, SigV4, path-style addressing, region `auto`, and `request_checksum_calculation='when_required'` / `response_checksum_validation='when_required'` to avoid optional unsupported S3 checksum behavior. Use ordinary single-request PutObject, not the multipart transfer helpers. Configure connect timeout 10 seconds, read timeout 120 seconds, standard retries with `total_max_attempts=3`. IPA reads and hash calculation use chunks no larger than 1 MiB, with the P2 byte bound applied to both ContentLength and bytes actually received. Sidecar reads stop after 66 bytes and only accept exactly 64 lowercase hex characters followed by one LF (65 bytes total). Close response bodies on all exits.

The ONLY object keys are `<tag>/WebDriverAgentRunner-Runner.ipa` and `<tag>/WebDriverAgentRunner-Runner.ipa.sha256`, without a `masters/` prefix. Every PUT has `IfNoneMatch='*'`; no unconditional PUT, overwrite, copy-replace, DELETE, bucket configuration call or retention operation exists. New IPA metadata records `source-commit` (resolved full commit), `titan-tag` and `sha256` (lowercase streamed final hash); use ContentType `application/octet-stream`. The sidecar body is the ASCII hash plus LF and ContentType `text/plain`.

At entry, GET the canonical IPA. Only an explicit object `NoSuchKey` is absence; authorization, NoSuchBucket, malformed responses and transport failures are failures. If it exists, stream/hash it and require all three metadata fields to match the admitted source identity and real hash. Reuse those exact canonical bytes/hash without building; a missing, malformed or inconsistent identity is `master_conflict`. This path does not download/repackage an existing IPA for another upload. Then read/reconcile the sidecar. A matching sidecar is retained. An absent sidecar is created from that verified canonical hash using the same create-only rule. An existing unequal/malformed sidecar is `master_conflict` and is never repaired by replacement.

If the IPA is absent, inspect the sidecar before building. If a sidecar appeared, re-read the IPA once to reconcile a competing publication; an absent IPA after that observation is `master_conflict`. If both are absent, build P2's candidate. Attempt the IPA create, then GET/hash the canonical result and compare its hash AND source identity to the candidate before creating the sidecar. For an uncertain PUT response, 409 or 412, reconcile using the same GET comparison: matching canonical bytes are success; differing bytes/identity are `master_conflict`; still absent or unreadable is `storage_unavailable` with no success record. Never substitute a competing different build even when it came from the same source commit.

After the IPA is verified, create/reconcile the sidecar with the same conditional-write/uncertain-response rule. Re-read both canonical objects and verify their agreement, then perform P1's final ref check before P4. ETags or user metadata alone never prove the SHA-256. Do not delete or roll back a completed object if a later operation fails. A rerun enters through the existing-IPA rule, so Xcode/ZIP nondeterminism cannot prevent recovery of a missing sidecar or summary. Never remove an old tag's two objects, including when its Git ref is later deleted or moved. Permanence is a publisher behavior and an operator requirement that the existing bucket has no expiry rule; do not claim R2 Object Lock or a token incapable of deletion.

### P4 — Human-facing publication record, last

After P3 verifies both remote objects and P1's final ref snapshot still identifies the event commit, append the following deterministic Markdown record to the publisher step's `GITHUB_STEP_SUMMARY`, substituting the verified canonical tag/commit/hash. This is the human-facing release-note record for the MVP, under the narrowing authorized in relay/answers.json. It creates no GitHub Release and needs no workflow revision on the default branch, merge to master, write-capable GitHub token or extra credential:

```text
Unsigned WDA master for backend re-signing (CP-WDA-ONBOARDING-20261116).

Tag: <tag>
Source commit: <source-commit>
SHA-256: <sha256>
IPA: r2://wda-masters/<tag>/WebDriverAgentRunner-Runner.ipa
SHA-256 sidecar: r2://wda-masters/<tag>/WebDriverAgentRunner-Runner.ipa.sha256

This master is unsigned. Backend hash verification and a successful lab install/launch are required before customer rollout.
```

Write the same public record to the job log, after the pair verification; no release URL is invented. The summary and log describe the event commit and the bytes retained in R2, not perpetual ownership of a mutable Git ref. They have GitHub run retention, not the masters' permanence guarantee. Script success attests the local summary append and log emission; GitHub uploads summaries after the step finishes. A runner-side summary-upload warning does not undo R2 publication or add a publisher retry path; the emitted log is the other human record. Do not read, create, modify or delete GitHub releases/assets, and do not upload a separate note artifact or third R2 object. An existing manually authored release does not participate in this flow.

If the local summary append fails, exit nonzero with `record_unavailable`; retain the verified R2 pair. Cancellation can leave a verified pair without the record. A later workflow rerun performs P1/P3 again, reuses the canonical IPA and regenerates the record without building or remote mutation when both objects already match. No background completion or unbounded retries. Exit 0 only after the pair is verified and the summary/log record is written. All failures use a sanitized stage plus one of `invalid_context`, `configuration_invalid`, `source_unavailable`, `build_failed`, `artifact_invalid`, `master_conflict`, `storage_unavailable`, `record_unavailable`. SDK/HTTP details must not become public diagnostics.

## Case table

Each row is a family; P1–P4 determine all members without per-input expansion.

| family | state × event | outcome | writer / reader sites |
| --- | --- | --- | --- |
| C1 Admission, configuration and observed source | Any state × trigger/context/config/ref check | P1's exact grammar rejects unsupported events/tags, including leading-zero suffixes; its source checks fail on observed ref changes/unavailable reads before the next operation, retaining committed objects. Later unobserved ref changes follow P1's snapshot rule. Upstream tags/branches do not dispatch this workflow. | New workflow trigger/job/env/contents-read permission; checkout token reader; publisher validator; package.json version reader; all publisher ref/tag GET sites at entry, before each PUT and after final readback; README recipe. |
| C2 Artifact production | No canonical IPA × build/package | P2 produces the exact compatible unsigned archive or fails before PUT. Unsigned hook mode cannot invoke signature discovery or signing; existing signed mode retains its behavior. | Publisher build/staging/ZIP/hash/limit writers and readers; embed-runner-icon.sh; existing scheme post-action and Runner plist; backend MAX_IPA_BYTES, unpack_ipa and prepare_master readers named in design.md. |
| C3 Existing canonical IPA | Existing IPA × entry/retry | P3 verifies actual hash and source metadata, reuses it without build, then reconciles remaining publications; conflict/unreadable state fails without replacement. | Publisher entry GET/stream/metadata verifier; canonical IPA PutObject is its only writer; backend hash_master/read_master remain read-only. |
| C4 Object creation and races | Missing object or uncertain create × new candidate/competing writer | P3 conditional create plus canonical readback accepts only matching content/source, otherwise conflict/unavailable. Apply to both keys. Sidecar-only observation re-reads IPA once before refusal. | Every publisher PutObject and its recovery GET; sidecar hash reader; workflow concurrency is scheduling only. |
| C5 Partial publication / cancellation | Any prefix of IPA → sidecar → summary/log × interruption/rerun | Retain committed R2 objects. Re-enter C1/C3/C4/P4; no success claim for an incomplete run, no rebuild of an existing IPA, no remote cleanup. | Publisher top-level sequence, finally/local cleanup, all HTTP/SDK/record exception paths, GitHub Actions cancellation. |
| C6 Publication record | Verified pair and final source snapshot × summary/log write | P4 records the verified event identity and hash, or fails record_unavailable while retaining the pair. Default-branch workflow differences and any existing GitHub release are irrelevant; no release/ref write occurs even if the ref changes after the check. | Publisher summary/log writer; GITHUB_STEP_SUMMARY path reader; Actions run/operator readers. |
| C7 Retention and consumers | New tag or later Git-ref change × previously published tags | Old objects remain untouched, even after a ref deletion; backend continues reading its pinned tag and computing the hash independently of the sidecar. | Publisher fixed-key writer/no DELETE; README operational permanence; existing BE master store, pipeline and CP contract. |

## Proof: State Table

C3–C6 above are the publication state table. Reachable durable R2 prefixes are empty, IPA only, and IPA+sidecar; the last may exist with or without its run summary/log record. A sidecar-only observation can occur from interleaved reads and follows C4; a standalone sidecar is never deliberately written. The record has run retention. No Git-ref/R2/summary atomic transaction is promised.

## Proof: Linearization

Each object acquires its bytes at the atomic create-only PutObject commit described in P3. A read-before-write check or Actions concurrency is not a storage fence. P1's Git-ref reads are observational checkpoints, not atomic publication authorization; P4 records the original event identity after the final checkpoint. A lost object-write acknowledgment is reconciled by reading authoritative R2 state; the flow does not claim exactly-once network delivery or create Git refs through a release call.

## Proof: Interruption Matrix

Apply C5 to every boundary before/after IPA PUT, IPA readback, sidecar PUT, final readback/ref check and summary/log write. Local files may be lost; committed objects remain authoritative. P1/P3/P4 determine observed source changes, ambiguous object completion and a failed/missing run record after successful R2 publication, without a ref-writing API.

## Proof: Supersession

P3's canonical tag/source metadata and atomic create-only writes prevent tag reuse or source movement from replacing a canonical IPA. C4 requires the local candidate comparison even if another run used the same commit. P1 explicitly bounds source-ref observations instead of promising a transaction across mutable refs and R2. Existing published masters are retained; this task changes no backend pin or customer assignment. No default-branch predecessor or new credential is needed.

## Proof: Red Tests

The test mandate is suspended by the operator; no tests, fixtures, coverage or red proofs are designed or required. The real-stack TESTBED observes the product acceptance below. This section exists solely for the selected security metadata class.

## Acceptance Criteria

- AC-01: Only a manually pushed valid `titan-<package.json version>-<n>` tag, with ASCII suffix `[1-9][0-9]*` and total tag length at most 64, publishes a master from its event's tagged commit. Branch pushes, upstream `vX.Y.Z` tags, leading-zero suffixes and invalid Titan contexts cannot publish one. Source checks reject observed moved/deleted refs; later unobserved changes never cause the publisher to create or alter a Git ref.
- AC-02: The IPA contains the existing arm64 iOS Runner under Payload with exact outer/plugin bundle identity `app.kilo.automation.simple`, XML Info.plists, `TrafficTitans` display/name and the matching LSEnvironment value, retaining compiled Titan code and the nested WDA framework.
- AC-03: The archive contains no embedded provisioning profile, signature/load command, outer XC*.framework or dSYM, and fits the shipped backend's archive limits. Unsigned icon processing never signs; ordinary signed icon processing retains its previous behavior.
- AC-04: The fixed bucket contains `<tag>/WebDriverAgentRunner-Runner.ipa` and `.ipa.sha256`; the latter is the lowercase SHA-256 of the real IPA bytes plus exactly one newline.
- AC-05: Competing or repeated publication cannot replace a published object with different bytes or a different tag/source identity, including a differently rebuilt candidate from the same commit. Conflicts fail visibly and preserve the existing objects.
- AC-06: Rerunning after interruption between IPA, sidecar and run record completes the missing sidecar/record from the verified canonical master without rebuilding or changing it; an ambiguous failure never produces a false success. An observed source conflict preserves already committed objects.
- AC-07: After the R2 pair agrees and the final ref snapshot identifies the event commit, the Actions summary/log records that verified tag/source/hash and both keys. Record failure preserves R2 objects for retry. This works from the tagged branch without landing the workflow on the default branch or an extra GitHub credential; no GitHub Release or tag/ref is created, edited or deleted by this flow.
- AC-08: Missing/invalid configuration and unavailable storage/source services fail with sanitized stage/code, without credential disclosure or Apple material; no artifact is published before its unsigned/archive validation. The automatic GitHub job token grants contents read only; action access and checkout non-persistence do not imply step isolation.
- AC-09: Publishing a new tag leaves every previous master and its hash readable; the existing upstream packaging/npm workflows retain their triggers and outputs. The README gives the actual one-token setup, tag convention and retry/lab-rollout instructions.

## Verification Commands

Native authoring checks are explicitly **UNAVAILABLE**, not passed. The conductor authorized the WDA-only exception in feature-folder `relay/answers.round1.json`, question `native_gate_policy`, choice A, on 2026-11-18. This fork never had these Rust-repository validators; do not import or author gate/registry infrastructure to supply them. Independent conductor review and build obligations are unchanged.

| Required native command, run in this WDA checkout | Actual exit | Observation |
| --- | --- | --- |
| `bun scripts/gates/check-task-metadata.ts --file tasks/2026-11-18-202100-wda-unsigned-master-publication.md` | 1 | `error: Module not found "scripts/gates/check-task-metadata.ts"` |
| `bash scripts/lint-task-spec.sh tasks/2026-11-18-202100-wda-unsigned-master-publication.md` | 127 | `bash: scripts/lint-task-spec.sh: No such file or directory` |

Architect static artifact checks retain the parsed intake JSON, the identical native/feature acceptance lists, the one-unit AC-01–AC-09 mapping, exact planned-file manifest and release companion, metadata/proof section presence, artifact whitespace checks, and `git diff --check`. Results are recorded in `relay/validation.json`; they do not substitute a fabricated successful native-validator result.

Builder static verification only, with no test execution:

```bash
git diff --check
python3 -c 'import ast,pathlib; ast.parse(pathlib.Path("Scripts/ci/publish-master.py").read_text())'
bash -n Scripts/embed-runner-icon.sh
ruby -rpsych -e 'Psych.safe_load(File.read(ARGV.fetch(0)), aliases: true)' .github/workflows/wda-master.yml
```

The TESTBED owns actual tag pushes, workflow runs, R2 inspection and backend/lab acceptance. Neither architect nor builder may claim these happened from static checks. Do not run the publisher locally as a syntax check: it is the real build/publication entry point. Honor any applicable repository compile-only checks; do not run npm/cargo/XCTest suites.

## Adversarial Review

FOR-CONDUCTOR-ADVERSARIAL-RECHECK: This is a single contract under the supplied small-unit rule. The full independent review must examine C1–C7, the icon-hook writer, every conditional PUT and ambiguous-response reader, the Xcode-generated bundle identifier, XML output, and the actual cross-repo consumers identified in design.md. Record concrete contradictions, undetermined reachable outcomes or missing writers rather than expanding examples already determined by P1–P4. No independent review result is claimed by this spec.

The final precheck amendment resolves G1–G4 by rule: P1 accurately scopes a read-only job token and exact suffix grammar; P4 uses a run summary/log rather than a GitHub Release; P1 bounds ref checks to observations and prohibits every ref-writing API. Full dispositions and supporting API evidence are recorded once in design.md. The R2 create-only/byte-identity contract is unchanged; no operator decision or default-branch predecessor remains.

The WDA-only validator exception is resolved as recorded above. No gate installation or unrelated repository changes are authorized. This native spec is ready for the unchanged conductor review/build lifecycle; operator secret provisioning gates the first tag push only.
