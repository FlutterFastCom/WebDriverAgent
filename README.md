# WebDriverAgent

[![NPM version](http://img.shields.io/npm/v/appium-webdriveragent.svg)](https://npmjs.org/package/appium-webdriveragent)
[![Downloads](http://img.shields.io/npm/dm/appium-webdriveragent.svg)](https://npmjs.org/package/appium-webdriveragent)

[![Release](https://github.com/appium/WebDriverAgent/actions/workflows/publish.js.yml/badge.svg)](https://github.com/appium/WebDriverAgent/actions/workflows/publish.js.yml)

[![GitHub license](https://img.shields.io/badge/license-BSD-lightgrey.svg)](LICENSE)

WebDriverAgent is a [WebDriver server](https://w3c.github.io/webdriver/webdriver-spec.html) implementation for iOS that can be used to remote control iOS devices. It allows you to launch & kill applications, tap & scroll views or confirm view presence on a screen. This makes it a perfect tool for application end-to-end testing or general purpose device automation. It works by linking `XCTest.framework` and calling Apple's API to execute commands directly on a device. WebDriverAgent is developed for end-to-end testing and is successfully adopted by [Appium](http://appium.io) via [XCUITest driver](https://github.com/appium/appium-xcuitest-driver).

## Features
* Both iOS and tvOS platforms are supported with devices & simulators
* Implements most of [WebDriver Spec](https://w3c.github.io/webdriver/webdriver-spec.html)
* Implements part of [Mobile JSON Wire Protocol Spec](https://github.com/SeleniumHQ/mobile-spec/blob/master/spec-draft.md)
* USB support for devices is implemented via [appium-ios-device](https://github.com/appium/appium-ios-device) library and has zero dependencies on third-party tools.
* Easy development cycle as it can be launched & debugged directly via Xcode
* Use [Mac2Driver](https://github.com/appium/appium-mac2-driver) to automate macOS apps

## Getting Started On This Repository

You need to have Node.js installed for this project.

After it is finished you can simply open `WebDriverAgent.xcodeproj` and start `WebDriverAgentRunner` test
and start sending [requests](https://github.com/facebook/WebDriverAgent/wiki/Queries).

More about how to start WebDriverAgent [here](https://github.com/facebook/WebDriverAgent/wiki/Starting-WebDriverAgent).

## Multiple displays

See [Multiple displays](docs/multiple-displays.md) for display selection, capture,
and active-app detection.

See [Hinge angle](docs/hinge-angle.md) for reading angles, sending simulated hinge
events, runtime requirements, and physical-device testing feedback.

## Known Issues

If you are having some issues please checkout [wiki](https://github.com/facebook/WebDriverAgent/wiki/Common-Issues) first.

## For Contributors

If you want to help us out, you are more than welcome to. However please make sure you have followed the guidelines in [CONTRIBUTING](CONTRIBUTING.md).

## Creating Bundles

`npm run bundle`

Then, you find `WebDriverAgentRunner-Runner-sim-<version>.zip` for iOS and `WebDriverAgentRunner-Runner-tv_sim-<version>.zip` for tvOS files in the current directory.

## Publishing Titan unsigned masters

The independent `Publish unsigned WDA master to wda-masters` Actions workflow
builds the tagged Titan commit with Xcode 16.4 on macOS 15. It compiles the arm64
iOS Runner without executing XCTest, fixes `CODE_SIGNING_ALLOWED=NO`, and packages
an unsigned IPA for backend re-signing. The Payload app and nested WDA bundle use
`app.kilo.automation.simple`; the app is named `TrafficTitans`. Existing npm and
iOS/tvOS/simulator packaging workflows keep their triggers and outputs.

Before the first tag push, configure these repository Actions settings:

| Setting | Value |
| --- | --- |
| Secret `R2_WDA_MASTERS_TOKEN_JSON` | `{"access_key_id":"<S3 access key ID>","secret_access_key":"<S3 secret access key>"}`; both fields must be nonempty strings from **one** R2 Object Read+Write token restricted to the existing `wda-masters` bucket. |
| Variable `R2_ACCOUNT_ID` | The account's 32-character hexadecimal ID. The publisher derives `https://<account-id>.r2.cloudflarestorage.com`, region `auto`, for the default-jurisdiction bucket. |

No R2 administration key, Apple certificate/profile, public bucket URL or extra
GitHub credential is needed. The automatic job token grants only `contents: read`;
it is used for authenticated GitHub ref/tag GETs. Actions, including checkout, can
access that job token. `persist-credentials: false` prevents checkout credential
persistence; it does not isolate actions from the job token. Explicit R2 and
GitHub token environment exports occur only on the publisher step, and its build
subprocesses receive neither token.

Manually push **one tag at a time**, from the commit containing the workflow and
publisher. Landing the workflow on the default branch or merging to `master` is
not required. The version must equal that commit's `package.json` version, and
the suffix must match ASCII `[1-9][0-9]*` (no leading zeroes). The whole tag must
be at most 64 characters and contain only ASCII letters, digits, dots, underscores
and hyphens. For example, from the intended commit:

```bash
version=$(node -p 'JSON.parse(require("node:fs").readFileSync("package.json", "utf8")).version')
tag="titan-${version}-1"
git tag "$tag"
git push origin "refs/tags/$tag"
```

Choose a fresh positive suffix for each new master. Annotated tags also work.
Only `titan-*` tag pushes dispatch this workflow; branch pushes, upstream `vX.Y.Z`
tags and tag deletions do not publish masters. Invalid Titan contexts fail
admission. Never move/reuse a published tag to publish changed code.

Each successful run verifies these two permanent, private objects:

```text
r2://wda-masters/<tag>/WebDriverAgentRunner-Runner.ipa
r2://wda-masters/<tag>/WebDriverAgentRunner-Runner.ipa.sha256
```

The sidecar contains the real IPA's lowercase SHA-256 plus exactly one newline.
Every upload is an atomic create-only PUT. Existing IPA bytes and their tag/source
metadata must agree; different bytes, even a different build of the same commit,
produce `master_conflict` without replacement. The publisher never deletes objects
or changes bucket retention. The operator must keep the bucket free of expiry
rules and retain old masters, including after tag deletion or movement. This is
not R2 Object Lock, and Object Read+Write credentials can permit deletion.

Rerun the failed Actions run after a cancellation or transient service failure.
An existing verified canonical IPA is reused without rebuilding or re-uploading;
a missing sidecar is created from its streamed hash. A complete pair needs only
verification and a regenerated run record. Malformed/conflicting objects are
retained and cause failure; publish corrected code under a new canonical tag.
Observed moved/deleted refs fail before the next publication operation, retaining
committed objects. Ref checks are snapshots: a change after a check can race with
the next operation, whose bytes and metadata still identify the original event
commit. The publisher never creates, recreates, moves or deletes remote refs.

After verifying both R2 objects and the final source snapshot, the publisher
appends the verified tag, source commit, SHA-256 and both keys to the Actions job
summary and writes the same record to the publisher step's log. These records
have GitHub run retention; the R2 masters have the operational permanence above.
A failed local summary append reports `record_unavailable` and retains the pair
for a rerun. A later runner-side summary-upload warning does not retract the pair
or cause a publisher retry; the job-log copy is the other human record. Automatic
GitHub Releases are deferred: this workflow never reads or changes releases or
release assets, and existing manually authored releases do not participate.

Failures report a sanitized stage and code: `invalid_context`,
`configuration_invalid`, `source_unavailable`, `build_failed`, `artifact_invalid`,
`master_conflict`, `storage_unavailable` or `record_unavailable`. Source/storage
failures and incomplete publications never produce a successful publication
record. This producer does not pin or assign a backend master: under
`CP-WDA-ONBOARDING-20261116`, the backend independently hashes the IPA (it does not
use the sidecar as proof), and a successful lab re-sign/install/launch is required
before customer rollout. Publishing an unsigned archive is not lab acceptance.

## License

[`WebDriverAgent` is BSD-licensed](LICENSE).

Have fun!
