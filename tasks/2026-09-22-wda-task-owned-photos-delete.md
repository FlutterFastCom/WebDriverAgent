# WDA owner proposal — bounded task-owned PhotoKit deletion

Status: **PROPOSED — UNAPPROVED / BLOCKED**  
Owner: WDA native fork (`/Users/dmitrydyachenko/Desktop/electron-farm/wda/WebDriverAgent`)  
Task branch observed: `tt/wda-photos-phase-1` (left unchanged)  
Planning runtime: Codex `gpt-5.6-luna` / xhigh  
Date: 2026-09-22

This is a planning-only native proposal. No WDA source, agent source, backend
source, build, test, device, account, database, branch, commit, or release was
changed or run. The mission remains DRAFT; this proposal and every consumer
spec remain BLOCKED pending owner agreement, operator approval, implementation,
review, and released-device qualification.

## Decision

Add one dedicated, typed PhotoKit route:

```text
POST /wda/photos/delete
capability tokens: photos.delete + photos.delete.status
GET /wda/photos/delete/status (read-only retained receipt)
```

It accepts a bounded ordered list of explicit PhotoKit `PHAsset.localIdentifier`
values and deletes only the corresponding fetched assets. The route is a new
producer. It must never call or delegate to `/wda/photos/clear`, whose current
implementation fetches every `PHAsset` and calls `PHAssetChangeRequest.deleteAssets`
on that entire result.

The operation is idempotent per identifier: a previously deleted, missing, or
otherwise not returned identifier is reported as `already_absent` in the
native observation; it does not cause another change request. The native
route cannot decide whether an absent identifier is owned by a task. The agent
and backend must enforce that contract before the route is reachable.

This is the smallest useful PhotoKit seam because the existing WDA fork already
has the exact identifier-producing import path, the explicit-ID fetch API is the
PhotoKit operation needed for bounded deletion, and no whole-library snapshot,
export, or generic WDA proxy is required.

## Source evidence and boundaries

The designated WDA fork has no narrower `AGENTS.md`, task directory, or native
design directory. The applicable instructions are the parent
`/Users/dmitrydyachenko/Desktop/electron-farm/AGENTS.md` and its canonical
`CLAUDE.md`; the WDA `README.md` describes the repository but adds no narrower
task rule. The source is currently clean on the designated branch.

Current WDA facts:

| Fact | Source | Boundary |
| --- | --- | --- |
| Closed custom Photos route set is import, importBatch, clear, list | `WebDriverAgentLib/Commands/FBPhotosBridge.m:26-33` | There is no delete-by-ID route today |
| Broad clear requires a marker, then fetches all assets and deletes them | `WebDriverAgentLib/Commands/FBPhotosBridge.m:50-60`; `FBPhotosCommands.swift:55-80` | Reusing it violates task ownership and unrelated-media preservation |
| List exposes `PHAsset.localIdentifier` as `assetIdentifier` | `FBPhotosCommands.swift:82-100`; `FBPhotoTypes.swift:72-86` | Listing is observation, not task ownership |
| Import returns `placeholderForCreatedAsset.localIdentifier` | `FBPhotosCommands.swift:137-165` | This is the required actual PhotoKit ID source |
| Full authorization helper already exists | `FBPhotosCommands.swift:217-221`; `FBPhotosPermissionHelper.swift:14-49` | Delete must use full `.readWrite` authorization; limited access is insufficient for this producer |
| WDA token list has no delete token | `WebDriverAgentLib/Commands/FBCustomEndpointTokens.m:15-22` | The route must be separately allowlisted |

The current WDA server sets its shared route queue to
`dispatch_get_main_queue()` (`WebDriverAgentLib/Routing/FBWebServer.m:80`).
`FBPhotosBridge.responseFromCommand` is deliberately synchronous and currently
fails closed when a command does not complete synchronously
(`WebDriverAgentLib/Commands/FBPhotosBridge.m:75-95`). These are source facts,
not assumptions about a future implementation. Its adjacent comment says the
Photos commands avoid permission prompts; that comment cannot be used as a
behavioral guarantee because Apple’s current documentation explicitly says
each change call may show the edit-confirmation alert and
`performChangesAndWait` may block indefinitely.

The planned delete route must therefore be registered as a **standalone** route
(`.withoutSession.standalone`) and run its blocking PhotoKit wait off the main
route queue. It must not call `performChangesAndWait` from the ordinary route
handler or use the synchronous bridge helper to hide an asynchronous operation.
The minimal producer keeps the request open until the background
`performChangesAndWait` call returns, then performs the explicit post-readback
and returns the version-1 response. The standalone route keeps the main queue
available for the alert endpoints while the Photos confirmation is displayed.
This is a future implementation requirement; no source change has been made.

Current consumer facts:

| Fact | Source | Required correction/contract |
| --- | --- | --- |
| Agent exposes `import_photo` only | `titan-devices-agent-rust/main/src/app/ports.rs:39-64` | Add a separate typed delete port/consumer; do not route through generic proxy |
| Agent posts only `/wda/photos/import` | `src/infra/wda_client.rs:332-349`; `wda_client_post_request.rs:4-24` | Add a fixed `/wda/photos/delete` client target with its own request/result parser |
| Import parser accepts any nonempty string | `src/infra/wda_photo_import.rs:75-137` | A nonempty string is transport data, not independent PhotoKit provenance |
| Agent result has only `MediaImported` for the current media path | `src/protocol/device_command_result_body.rs:21-26` | Add a typed deletion result owned by the agent contract |
| Media opcodes currently stop at SelectFolder/Rescan/Transfer | `src/protocol/opcodes.rs:25-27,81-86,128-135,174-180` | A delete operation needs a distinct bounded command family/opcode |
| Backend manifest enforces nonempty and unique IDs plus attempt/post/media fields | `titan-cloud-backend-rust/src/application/tools/media/manifest.rs:13-32,118-149` | It is provenance metadata, not proof that a value originated in PhotoKit |
| Media import forwards the raw agent string | `src/application/host_media/issue.rs:161-181` | Only a successful released agent import receipt may seed task-owned deletion |

Apple’s primary documentation confirms the relevant behavior:

- `PHAsset.fetchAssets(withLocalIdentifiers:options:)` retrieves assets by
  explicit local-device-specific identifiers; the route must use this API and
  never `fetchAssets(with: nil)`. See [Apple’s Fetching Assets documentation](https://developer.apple.com/documentation/photokit/fetching-assets).
- `PHAssetChangeRequest.deleteAssets(_:)` requests deletion of the supplied
  assets inside a PhotoKit change block, and `performChangesAndWait` runs that
  block synchronously. See [PHAssetChangeRequest](https://developer.apple.com/documentation/photos/phassetchangerequest)
  and [deleteAssets](https://developer.apple.com/documentation/photos/phassetchangerequest/deleteassets%28_%3A%29).
- Apple also states that every `performChanges` and
  `performChangesAndWait` call shows an alert asking the user for permission to
  edit the Photos library. Full `.readWrite` authorization therefore does not
  suppress this per-change edit confirmation. Apple says not to call
  `performChangesAndWait` on the main thread because Photos may prompt and the
  method may block indefinitely. See [Requesting Changes to the Photo
  Library](https://developer.apple.com/documentation/photokit/requesting-changes-to-the-photo-library?changes=_7)
  and [`performChangesAndWait`](https://developer.apple.com/documentation/photos/phphotolibrary/performchangesandwait%28_%3A%29).
- `PHAuthorizationStatus` distinguishes authorized, limited, denied,
  restricted, and not-determined states. The route must inspect
  `authorizationStatus(for: .readWrite)` and must not request authorization
  while a destructive command is in flight. This status check is separate from
  the edit-confirmation alert described above. See [Apple’s Photos
  authorization guidance](https://developer.apple.com/documentation/PhotoKit/delivering-an-enhanced-privacy-experience-in-your-photos-app?changes=_1&language=objc).
- Deleted Photos items are placed in Recently Deleted and can normally be
  recovered or permanently removed during the 30-day window; this route must
  not empty that collection or claim permanent erasure. With iCloud Photos,
  deletion propagates to devices using the same Apple Account and sync timing
  varies. See [Apple’s iPhone deletion guidance](https://support.apple.com/guide/iphone/delete-or-hide-photos-and-videos-iphb4defbde9/27/ios/27)
  and [iCloud Photos](https://support.apple.com/en-gb/108782).

## Native request schema

The bridge parser must reject unknown fields and all malformed values before
authorization, fetching, or a change block. The request is:

```json
{
  "version": 1,
  "requestId": "<source command UUID>",
  "expectedEpoch": "<epoch pinned before POST>",
  "assetIdentifiers": ["<exact PhotoKit localIdentifier>"],
  "confirmDelete": true,
  "deadlineBudgetMs": 15000
}
```

The exact bounds are part of the proposed contract:

| Field | Bound and rule |
| --- | --- |
| `version` | Exactly integer `1` |
| `requestId`, `expectedEpoch` | Canonical UUIDs; pinned source/producer identity under the mandatory recovery appendix |
| `assetIdentifiers` | Array of 1 through 20 strings, preserving caller order |
| Identifier bytes | 1 through 512 UTF-8 bytes per string; valid UTF-8, no NUL/control characters, no surrounding whitespace; no normalization or trimming |
| Duplicates | Any duplicate is a whole-request `invalid_duplicate` rejection before PhotoKit; no partial delete |
| Aggregate body | JSON request serialized bytes at most 16 KiB; response at most 64 KiB |
| `confirmDelete` | Exactly boolean `true`; missing/false is `missing_confirm_marker` |
| `deadlineBudgetMs` | Positive integer milliseconds from WDA route receipt, bounded to 1 through 30,000; the agent derives it from the outer command deadline and subtracts transport margin; WDA checks its own monotonic elapsed time immediately before irreversible submission |

Twenty IDs is deliberately a single bounded operation. A caller with more than
20 task assets must be rejected as `too_many_identifiers` and admitted by a
separately designed/chunked product operation; WDA must not silently loop or
turn this route into a batch workflow. The 512-byte identifier cap is a wire
guard, not a claim about PhotoKit’s internal identifier format.

The deadline is a relative WDA budget rather than a device-wall-clock
timestamp. The agent owns the outer command deadline and sends the remaining
budget after reserving transport/scheduler margin; WDA starts a monotonic clock
when it receives the request. This avoids making irreversible admission depend
on an unqualified host/device clock offset. The agent still treats an HTTP
timeout or cancellation after submission as an unknown physical effect.

The route has no `runId`, account id, content hash, media row, or ownership
field. Those values are backend provenance and do not make WDA capable of
deciding task ownership. An `assetIdentifier` received from `/list`, an
arbitrary test fixture, or a manually supplied nonempty string is not thereby
task-owned.

Exact future source/test membership is closed in the Files And Phases section below. There is no “or equivalent” file allowance.

## Native response schema

Every accepted request returns an explicit bounded result. HTTP 400 is used for
request-shape errors; permission, PhotoKit, deadline, and postcondition facts
are typed in the result. The response shape is:

```json
{
  "version": 1,
  "requestId": "<source command UUID>",
  "producerEpoch": "<same pinned UUID>",
  "bodySha256": "<exact POST bytes SHA-256>",
  "scope": "explicit_identifiers_only",
  "auth": "authorized",
  "outcome": "deleted",
  "submission": "submitted",
  "preReadback": [
    {"assetIdentifier": "<same exact string>", "state": "present"}
  ],
  "postReadback": [
    {"assetIdentifier": "<same exact string>", "state": "absent"}
  ],
  "items": [
    {"assetIdentifier": "<same exact string>", "outcome": "deleted"}
  ],
  "counts": {
    "requested": 1,
    "deleted": 1,
    "alreadyAbsent": 0,
    "stillPresent": 0,
    "unknown": 0
  },
  "editConfirmation": "unknown",
  "changeError": null,
  "retention": "recently_deleted",
  "cloudPropagation": "unobserved",
  "irreversibleSubmission": "completed"
}
```

The only per-item outcomes are `deleted`, `already_absent`, `still_present`,
and `unknown`. `preReadback` and `postReadback` preserve request order and each
contain exactly one entry for every requested ID. Readback state is `present`,
`absent`, or `unavailable`.

The top-level `outcome` values are:

| Outcome | Meaning |
| --- | --- |
| `deleted` | At least one ID was present, a change block was submitted without a reported error, and every requested ID is absent in post-readback |
| `already_absent` | All requested IDs were absent before submission; no change block was submitted |
| `partial` | A change was submitted and post-readback has a mix of absent/present or an error alongside per-ID uncertainty |
| `photos_error` | PhotoKit returned a change error and no requested present ID is proven absent by post-readback |
| `postcondition_unknown` | A change was submitted but post-readback was unavailable or the request was interrupted before the response |
| `permission_denied` | Full read/write authorization was not `authorized`; no PhotoKit fetch or mutation was attempted |
| `user_declined` | The Photos edit-confirmation alert was declined or dismissed before a successful change; explicit post-readback is still required |
| `deadline_expired` | The deadline failed immediately before submission; no change block was entered |
| `invalid_request` | Only used in an HTTP 400 error envelope for malformed request data |

The native result does not call an absent identifier `owned` or `not_owned`.
With full authorization, `absent` means PhotoKit did not return that explicit
identifier at that readback. The agent maps it to `already_absent` only after
its consumer admission has proved the ID is a task-issued ID. Backend policy
must treat an ID absent before import/receipt binding as an ownership failure,
not as permission to delete anything else.

`changeError` contains only a bounded stable error category and numeric domain
code, for example `{"category":"photos_change_failed","domain":"PHPhotosErrorDomain","code":3300}`;
it must not include arbitrary localized text or identifiers. The route reports
`retention: recently_deleted` for a submitted deletion and never reports
`permanently_erased`. `cloudPropagation: unobserved` is deliberately explicit.
`editConfirmation` is `unknown` in the native result unless the native
executor can prove a confirmation callback outcome; the WDA producer must not
pretend that full Photos authorization accepted the edit alert. The agent’s
maintenance lane records the UI observation separately as
`accepted`, `declined`, `not_observed`, or `unknown`.

## Execution and irreversibility rules

1. Parse the strict request and enforce all caps, confirmation, canonical ID
   strings, and duplicate rejection before any Photos API call.
2. Read `PHPhotoLibrary.authorizationStatus(for: .readWrite)`. Only
   `.authorized` is admitted. `.limited`, `.denied`, `.restricted`, and
   `.notDetermined` return `permission_denied` with no authorization request and
   no fetch. The caller must establish the approved full Photos permission in
   its own guarded flow. This authorization check does **not** suppress the
   separate per-change edit-confirmation alert documented by Apple.
3. Fetch only the supplied IDs with
   `PHAsset.fetchAssets(withLocalIdentifiers:options:)`. Build the explicit
   pre-readback and never enumerate the library. If all are absent, return
   `already_absent` with an explicit post-readback and no mutation.
4. Recheck full authorization and the WDA monotonic `deadlineBudgetMs`
   immediately before submission. If either check fails, return
   `permission_denied` or `deadline_expired` and do not enter the change block.
   The future bridge route must be `.standalone`, so this blocking operation
   runs off WDA’s main route queue; `performChangesAndWait` must never run on
   the main thread.
5. Set `irreversibleSubmission` to `started` at the boundary immediately before
   the standalone route calls `performChangesAndWait`. Inside that one change
   block, call `PHAssetChangeRequest.deleteAssets` only with the fetched assets
   whose IDs were present in the pre-readback. No `clear`, collection delete,
   album traversal, or broad fetch is reachable.
6. A Photos edit-confirmation alert may appear even after full `.readWrite`
   authorization. WDA does not auto-accept or auto-dismiss it. While the
   standalone request remains in flight, the agent’s separate per-device
   maintenance lane may inspect the expected Photos confirmation through the
   existing alert routes and accept it exactly once only when the backend has
   already authorized this run-issued cleanup. It must leave an unexpected
   alert untouched. The route’s `confirmDelete` marker is caller intent and is
   not evidence that iOS accepted the edit.
7. If the expected confirmation is declined or dismissed, report
   `user_declined` (or `photos_error` if the platform error cannot be classified)
   and still perform the explicit post-readback. If the alert remains pending,
   `performChangesAndWait` may block indefinitely. The agent must not retry or
   submit another Photos operation while it is pending.
8. Once the change call is entered, cancellation cannot undo it. A deadline,
   WDA HTTP timeout, process interruption, or caller cancellation after this
   boundary closes only the client-side wait; it does not cancel PhotoKit and
   remains `postcondition_unknown` unless a matching terminal producer result
   resolves it. The mandatory receipt-recovery appendix separates finite backend
   logical settlement from persistent Photos safety quarantine; ownership never
   waits indefinitely for the callback. No retry/import/delete/WDA restart is
   admitted while that safety guard is unresolved. There is no fake rollback.
9. After the change block returns, fetch the same explicit IDs again and emit
   post-readback. A change error does not suppress readback. Mixed final states
   produce `partial`; inaccessible readback produces `postcondition_unknown`.
10. A duplicate request ID returns its retained original result without another
   change block; a separately authorized new request for an already absent ID
   returns `already_absent`. The agent never replays an uncertain POST. The
   bounded process-local receipt store is defined by the recovery appendix;
   WDA has no durable operation journal and does not decide task ownership.

PhotoKit may observe a concurrent external change between the two reads. The
result therefore means “present before and absent after this submitted request”
and is not cryptographic causal proof against another Photos writer. The agent
consumer must serialize task-media deletion with its own Photos import/delete
operations, and released qualification must run with no unrelated writer.

## Agent and backend release seam

This WDA proposal is not a complete feature. The agent and backend must agree
on this exact division before any WDA builder work is approved.

### Agent owner contract

The agent adds a dedicated typed WDA client/port and a dedicated media cleanup
command family. It does not expose `/wda/photos/delete` through generic
`proxy`, `get_source`, or arbitrary caller JSON. The fixed client sends only:

```json
{
  "version": 1,
  "requestId": "<source command UUID>",
  "expectedEpoch": "<epoch pinned before POST>",
  "assetIdentifiers": ["<IDs admitted by the backend>"],
  "confirmDelete": true,
  "deadlineBudgetMs": 15000
}
```

It validates count, byte caps, duplicate IDs, inherited device/session,
deadline, response cap, and response version. The result must retain the
per-ID pre/post facts and `postcondition_unknown`; a transport timeout after
the irreversible boundary is never mapped to `failed` or `no_effect`.

The per-device actor must reserve a separate Photos-maintenance lane before
dispatch. The delete HTTP request remains in flight on WDA’s standalone route
while that lane watches the expected system edit-confirmation alert through
the existing alert endpoints. The lane accepts the expected Photos
confirmation once only after the backend’s run-issued provenance and user
authorization checks have passed; it never treats full `.readWrite` status or
`confirmDelete` as iOS confirmation, and it never accepts an unexpected alert.
The agent wraps the result with `editConfirmation: accepted | declined |
not_observed | unknown`. If the user declines, the agent returns the typed
`user_declined` result and does not retry.

The lane is part of the operation’s quiescence contract. The local agent HTTP
handoff and WDA internal PhotoKit submission are separate boundaries. Stop
before proven local handoff prevents a request; after handoff it cannot prevent
WDA from submitting already delivered work within its original budget. The
mandatory recovery appendix defines responsive read-only receipts, a finite
90-second consumer window, logical closure and separate Photos quarantine. A
matching completed receipt can resolve ordinary lost HTTP replies; lost epoch
or missing receipt is explicitly not observable. A whole-library list is never
a substitute.

The agent may carry an opaque backend provenance digest alongside its own
command envelope for correlation, but WDA receives only the explicit IDs. The
agent must not claim that a successful WDA response proves ownership. Its
released consumer must document whether it keeps successful-import receipts
for the active run/device and how restart/unknown delivery blocks further
mutation. A generic WDA endpoint addition alone cannot satisfy U5.

### Canonical agent boundary (owned by the device-agent task)

The agent result is closed by the canonical device-agent task, not by this WDA
proposal: `/Users/dmitrydyachenko/orca/workspaces/titan-devices-agent-rust/main/tasks/2026-09-22-000300-task-owned-media-delete-producer.md`,
§“Agent result contract”. That task owns `TaskMediaDeleteRequest` admission
and the exact closed `TaskMediaDeleteResult` shape. This WDA proposal does not
redefine that wire or reproduce its field list; the linked agent task is the
sole authority for its `outcome`, confirmation, delivery, per-ID readbacks,
retention, and provenance fields.

This replaces the earlier provisional `wdaResult`/`delivery`/`workerCleanup`
envelope. The agent owns command/session/device/generation and import-receipt
admission, the Photos-maintenance confirmation lane, per-device serialization,
the `backup-v1` worker guard, and Stop/timeout mapping. In particular, a
post-submission callback or transport loss maps to
`delivery=submitted_uncertain` and/or `outcome=postcondition_unknown`; it never
replays the request.

WDA owns only the native producer facts defined above: strict explicit-ID
request parsing, full-authorization gating, explicit PhotoKit fetch/delete,
off-main `performChangesAndWait`, native callback/effect outcome, and ordered
pre/post readback. WDA does not emit `TaskMediaDeleteResult`, decide task
ownership, or report agent delivery, host worker cleanup, or the `backup-v1`
physical quarantine. Those are separate agent/host facts. `mediaRowId`,
`ordinal`, `importReceiptId`, and `provenanceDigest` remain correlation and
admission data; WDA receives only ordered asset IDs and the native bounded
request identity/confirmation/deadline fields.

### Backend owner contract

Before dispatch, backend admission must prove for every requested ID:

- the exact inherited device is the same device that produced the import;
- the ID came from a successful released-agent `MediaImported` response whose
  producer is the WDA PhotoKit import path, not a test helper or caller string;
- the ID is bound to this run’s successful media manifest item, content/media
  row, ordinal, and import receipt; all IDs are unique and within the native
  bound;
- no prior cleanup result has settled the ID as deleted/unknown, and a
  `postcondition_unknown` or lost response blocks automatic destructive replay;
- the operation is admitted only when the user’s approved Photos/full Photos
  permission fact is current for the same device/session. WDA’s `.authorized`
  check is a final safety gate, not the backend’s permission-policy producer.
- the agent maintenance lane is available to handle the per-change Photos edit
  confirmation while WDA’s standalone request is pending. Full Photos
  authorization does not satisfy this separate iOS confirmation requirement.

The backend must reject unknown, duplicated, cross-device, unimported, or
caller-supplied IDs before dispatch. It must preserve attempt/run/media/import
provenance and map native `already_absent`, `partial`, `photos_error`, and
`user_declined`, and `postcondition_unknown` separately. It must preserve the
agent’s `editConfirmation` observation and treat `not_observed`/`unknown` as
qualification facts, not proof that iOS accepted the change. It must never
infer a successful cleanup
from a WDA HTTP 200, an Ack, a changed count, a returned identifier, or model
prose.

No server-side media deletion, account deletion, browser cleanup, Recently
Deleted purge, iCloud operation, or permanent secure erase is implied by this
producer. Unrelated Photos assets remain outside the explicit ID set by
construction. A strategy that produces phone-side media but cannot satisfy
this backend provenance plus released agent consumer contract remains
unsupported/blocked.

## Planned tests (not run)

WDA unit tests should add a strict request/response parser suite next to
`WebDriverAgentTests/UnitTests/FBPhotoListRequestTests.swift`:

- accept one and 20 valid IDs; reject zero, 21, overlong IDs, control/NUL,
  surrounding whitespace, invalid version, missing/false confirmation,
  expired/non-integer deadline, unknown fields, oversized body, and duplicates;
- map `.authorized`, `.limited`, `.denied`, `.restricted`, and `.notDetermined`
  to the permission contract and assert no fetch/change call for every
  non-authorized state;
- assert the executor calls only `fetchAssets(withLocalIdentifiers:)`, never
  `fetchAssets(with: nil)` or a library export, and preserves request order;
- prove all-absent idempotent retry skips `performChangesAndWait`, while a
  present set submits exactly one change block with only the fetched assets;
- cover expired-before-submit, cancellation/timeout-before-submit, and
  cancellation/timeout-after-submit as distinct facts; the latter cannot
  invoke rollback or claim no effect;
- cover PhotoKit success, change error, mixed post-readback, still-present, and
  unavailable-readback outcomes with exact count and response-cap assertions;
- assert the bridge has `/wda/photos/delete`, the capability token is
  `photos.delete`, and `/wda/photos/clear` remains unchanged and unreachable
  from the delete handler;
- assert the delete route is `.standalone`, the Photos wait never runs on the
  main route queue, and `/alert/*` remains serviceable while the route is
  blocked on `performChangesAndWait`;
- cover confirmation accepted, confirmation declined, an unexpected alert,
  no maintenance lane, transport timeout after submission, late native
  callback, and cleanup quiescence/no-retry state. A full authorization grant
  must not be treated as evidence that the edit confirmation was accepted.

Released-device qualification must use a disposable run and the exact WDA,
agent, backend, iOS, and Photos permission tuple. It must import two known
assets, retain the exact returned identifiers and import receipts, delete one,
prove that target’s explicit post-readback is absent, and prove the control
asset remains present through a direct explicit-ID PhotoKit test observation.
It must repeat the delete for idempotence, test limited/denied/full permission,
exercise a malformed/duplicate/nonexistent ID, and exercise an interrupted
transport after submission. It must not enumerate/export the whole library,
delete Recently Deleted, or use unrelated media as a disposable fixture.
Qualification records local Photos facts only. iCloud propagation, other-device
state, server media records, and permanent erasure remain unobserved unless a
separately owned, explicitly approved producer is later added.

The following are concrete facts established during planning: Apple documents
the per-change edit alert and indefinite blocking possibility; the current WDA
server routes ordinary handlers on the main queue; the current Photos bridge
requires synchronous completion; and WDA already exposes alert endpoints. The
standalone route, maintenance lane, alert classification, late-callback
handling, and quiescence rules above are future contract/qualification
requirements. No phone test was run, so this plan does not claim the exact
Photos alert text, button labels, timing, error code, or iOS-version behavior
for a released device.

## Release dependency and disposition

The dependency chain is:

```text
WDA route + token + typed PhotoKit result
  -> agent fixed client/port/opcode + provenance-aware admission/result
  -> backend manifest/import-receipt gate + cleanup consumer
  -> released WDA/agent/BE qualification on the named device/build/permission tuple
```

The WDA branch cannot be released as U5 support until the agent owner agrees
to the typed consumer and unknown-effect handling, and the backend owner agrees
to run-issued import provenance and rejects arbitrary/test-helper identifiers.
The agent cannot implement the missing capability by adding a WDA client alone;
the backend must carry the run-owned manifest contract, and the WDA route must
remain a narrow physical producer.

Current status stays **UNAPPROVED / BLOCKED**. This proposal does not make any
strategy eligible and does not close the U5 blocker.

## Required receipt recovery contract

Read [the complete normative recovery appendix](../docs/architecture/proposals/2026-09-22-wda-task-owned-photos-delete-recovery-contract.md). It defines BOTH fixed routes, exact schemas, bounded storage, source identity, independent status scheduling, Stop semantics and mandatory regression cases. This is part of WDA1, not deferred design or runtime proof.

## Files And Phases — R1

W1→W2→W3 is sequential; the exact production and test manifest is below. Required normative appendix files are planning inputs and Xcode source membership is explicitly owned. No equivalent-name/unlisted-file allowance exists.

### W1 Strict request/result and process-local store

Files: `WebDriverAgentLib/Commands/FBPhotoDeleteRequest.swift`, `WebDriverAgentLib/Commands/FBPhotoDeleteStatusRequest.swift`, `WebDriverAgentLib/Commands/FBPhotoDeleteOperationStore.swift`.

### W2 Standalone routes and executor

Files: `WebDriverAgentLib/Commands/FBPhotosBridge.m`, `WebDriverAgentLib/Commands/FBPhotosCommands.swift`, `WebDriverAgentLib/Commands/FBCustomEndpointTokens.m`, `WebDriverAgent.xcodeproj/project.pbxproj`.

### W3 Producer regressions

Files: `WebDriverAgentTests/UnitTests/FBPhotoDeleteRequestTests.swift`, `WebDriverAgentTests/UnitTests/FBPhotoDeleteOperationStoreTests.swift`, `WebDriverAgentTests/UnitTests/FBPhotoDeleteExecutionTests.swift`.
