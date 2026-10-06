# WDA normative receipt recovery appendix

Status: PROPOSED — planning only, not implemented or qualified.

## Bounded producer receipt recovery — R3 normative contract

This section is a required dependency of the WDA, agent and BE proposals. It
adds a narrow same-process receipt producer; it does not add cancellation,
PhotoKit polling, a generic journal, a library scan or business replay.

### WDA identity, route and bounded storage

The qualified tuple must expose BOTH `photos.delete` and
`photos.delete.status` capabilities. Add the fixed standalone read-only route
`GET /wda/photos/delete/status`. Its strict query is exactly either
`mode=epoch` (no other keys), or
`mode=observe&requestId=<canonical UUID>&expectedEpoch=<canonical UUID>`.
Unknown/duplicate query keys, malformed UUIDs, non-GET requests and query bytes
above 512 are HTTP 400 before any Photos API. The epoch query reports only
process identity; it cannot claim anything about an earlier operation.

WDA mints one random `producerEpoch` UUID at process start. The existing proposed
POST strict schema additionally requires `requestId` and `expectedEpoch`, both
canonical UUIDs. The agent pins the epoch before handoff. WDA rejects a mismatching
epoch before fetch/submission. `bodySha256` is lowercase SHA-256 of the exact
received POST body bytes (including the budget), not a caller assertion. The
agent saves those exact bytes' digest before sending them. Every accepted POST
result additionally echoes `requestId`, `producerEpoch`, `bodySha256`; all existing
native result fields and meanings remain unchanged. The request still contains
no account, run, backend ownership or media-row fields.

`FBPhotoDeleteOperationStore` has one pending slot and at most 16 terminal
records per WDA process, protected by a short in-memory lock. On validated
admission, atomically reserve the pending slot with request ID, epoch and digest
BEFORE queueing any PhotoKit executor; release the lock before all I/O, fetch,
PhotoKit, confirmation or HTTP work. A second different operation while pending
is a typed pre-effect busy refusal. For the same request ID/digest, a duplicate
POST never resubmits: pending is HTTP 409 `operation_pending`, completed returns
the stored original result. A different digest is HTTP 409
`request_identity_conflict`. The agent never deliberately retries POST.

The executor publishes the complete original typed result to the store BEFORE
writing its HTTP response. Publication marks the pending slot terminal even if
post-readback is unavailable; physical call return and postcondition certainty
remain distinct. Terminal records expire 30 minutes after publication using
WDA's monotonic clock; oldest terminal records may be evicted at capacity.
Pending records are never evicted or made terminal by age/client timeout. WDA
restart loses the store and changes epoch; no durable PhotoKit journal is added.
A missing/evicted record is never evidence of no submission.

Status response (strict, at most 64 KiB):

```text
PhotoDeleteStatus {
 version: 1,
 producerEpoch: UUID,
 requestId: UUID | null,
 bodySha256: lowercase_hex_64 | null,
 state: epoch | pending | completed | not_found | wrong_epoch,
 result: NativePhotoDeleteResult | null
}
```

`epoch` has null request/digest/result. An observe response echoes the requested
ID; wrong expected epoch produces `wrong_epoch` before lookup, with null digest
and result. `not_found` has null digest/result. `pending` has the saved digest
and null result. `completed` has the saved digest and the EXACT stored original
result, including matching request/epoch/digest. No status path fetches Photos,
checks permission, accepts an alert, changes a lease, starts/restarts WDA, waits
on PhotoKit, or submits/deletes/imports anything.

The status handler must be independently schedulable while the standalone POST
blocks in `performChangesAndWait`. It snapshots the store without acquiring the
Photos executor's serial queue or any lock held across that call. Register it
standalone as well; tests must block PhotoKit and still get status within the
10-second caller budget. Generic `/list` cannot replace this route: its bounded
newest-assets view proves neither an exact ID's absence nor pending work's end.

### Agent binding, independent read lane and finite budget

Before POST, the agent writes its bounded local operation record atomically:
original source command ID, originating agent process epoch, inherited UDID/device,
original session and attachment generation, imported-receipt bindings/provenance digest, WDA request ID (equal to
the source command UUID), pinned producer epoch, exact body digest and original
deadline. This is operation receipt retention, never command replay. Store it
with the Photos-family safety guard before handoff; failed persistence refuses
POST. Local state has one pending source per device plus at most 16 completed
source records, a 1 MiB per-device cap and owner-only permissions. Never evict
an unresolved source to admit a mutator. Completed records expire after 30
minutes; restart cannot invent a new automatic timeout window. Missing/corrupt
state becomes `not_observable`, with uncertainty retained.

The full initial media cleanup operation has ONE monotonic 90-second window
from agent admission, clipped to the original command/stage deadline. It includes:
(1) one epoch GET, maximum 5 seconds; (2) at most one POST/client wait, maximum
30 seconds with WDA pre-submit budget at most 30,000 ms after transport margin;
(3) at most TWO observe GETs, each at most 10 seconds. First observe follows a
lost/malformed/timeout POST response immediately if budget remains. If still
pending, the second starts at min(admission+80 seconds, outer deadline-10 seconds),
never before the first finishes. Skip a probe when no positive budget remains;
all waits are cancellation-aware. Direct valid POST completion needs no probe.
Confirmation observations/tap and client teardown share this original window;
no timer, retry, reconnect or observation resets it. At its end, terminate/reap
agent client and alert-lane resources and report their own cleanup honestly;
never wait indefinitely for PhotoKit. Unknown agent-resource teardown retains
its own guard even when WDA has a completed receipt.

The closed `task_media_delete` family gains a second strict variant:
`TaskMediaDeleteObserveRequest { op: observe_delete, sourceCommandId: UUID }`.
It accepts NO asset IDs, epoch, digest, arbitrary URL, ownership or retry flags.
It resolves only that agent-retained original source and current authorized
same-device transport; wrong device or unavailable original binding returns
`not_observable` without dispatch. Reconnection may authorize the read through
current host/device ownership; it never rewrites the original source tuple.
An agent process restart may reload the intact source binding for read-only
observation only, not resume POST or the automatic 90-second window.

The result is a new operation-tagged variant, not a change to the canonical
existing delete result or a `wdaResult` wrapper:

```text
TaskMediaDeleteObserveResult {
 op: observe_delete,
 sourceCommandId: UUID,
 observation: pending | completed | not_observable,
 reason: null | wrong_epoch | record_missing | binding_unavailable |
         transport_unavailable | malformed_receipt,
 workerCleanup: confirmed | unknown,
 result: TaskMediaDeleteResult | null
}
```

Only `completed` has non-null canonical delete result and null reason;
`pending` has null result/reason; `not_observable` has one reason and null result.
Validate exact WDA request ID, pinned epoch and digest before accepting pending
or completed. Epoch, digest and native identity stay in the typed internal
receipt; public/log output stays redacted. The canonical delete result still
maps WDA submission to agent delivery and keeps client/maintenance cleanup
separate from PhotoKit effect.

Provide a supervisor-owned status lane with one in-flight read per device,
10-second per-request deadline, zero waiting behind the mutator actor/Photos
maintenance lane, and immediate typed busy refusal if already occupied. Its
admission still checks authentication, exact source and current owned device,
but MUST permit read-only observation while that source's Photos guard is
pending, after the mutator command ended and after Stop when explicitly owner
authorized. It has no alert-input authority and bypasses no mutation gate.
The original delete command cannot monopolize the shared WSS dispatcher: it
runs under the owned command supervisor while status is routed independently.
No ordinary health/preflight may restart WDA to make observation succeed.
Persist confirmed original agent-client/alert-lane teardown before publishing it.
If that original agent epoch is lost without a retained confirmed teardown fact,
new-process observation reports `workerCleanup=unknown`; it cannot manufacture
old resource proof from restart. BE uses the explicit lost-authority limit, not
an indefinite promise that another observation will resolve those old resources.

An original matching terminal POST result or matching completed status proves
the original PhotoKit executor returned. Along with confirmed original-agent
client/maintenance teardown, it clears ONLY that source's Photos safety guard.
It does not clear a backup guard, prove successful deletion when per-ID states
are unknown/present, authorize replay, reopen a closed run or make privacy
eligibility true. `pending`, `not_found`, wrong epoch, timeout, missing local
binding or malformed receipts never clear the guard.

### Stop and loss are different boundaries — R2

Before the agent hands POST to its HTTP transport, one local atomic handoff
fence arbitrates Stop/deadline/session loss versus submission. If the fence
wins and transport was never handed the request, return `not_submitted` with
zero WDA request/effect. Epoch/status reads before that point are read-only.
Once handed off, the agent cannot observe whether WDA has entered PhotoKit.
Stop BEFORE WDA's internal change call can still be followed by WDA submitting
that already delivered request within its original budget. Therefore handoff
without a matching terminal receipt is `submitted_uncertain` and
`postcondition_unknown`, even when no PhotoKit callback has yet begun. No remote
cancel handshake is introduced. Stop fences every new POST and confirmation
tap. Pure receipt observations after Stop require an explicit owner maintenance
request; no automatic probe is silently dispatched after the fence. The active
read may finish and deliver facts. WDA's own pre-submit deadline remains its
independent native safety boundary.

### Counterexamples and release qualification

The new route is selected over permanent exclusion after every lost HTTP reply:
Dev=medium (one store, fixed status route and typed consumer), Test=bounded
cross-owner failure matrix, Coverage=ordinary response loss while authority
survives, Confidence=design/source-supported, runtime not yet measured. A generic
durable journal/readback framework has greater cost and does not recover a
PhotoKit call whose process authority was actually lost; it is excluded.

Mandatory regressions/physical qualification: submit once and deliberately drop
only its HTTP response after store publication; recover the exact completed
receipt and reuse the same phone through normal gates with zero second POST.
Block PhotoKit and prove status remains responsive under Photos quarantine and
Stop; no mutator/alert tap is admitted. Finish after initial 90 seconds and
recover through explicit owner observation, preserving the original closed
run. Test wrong epoch, evicted/missing record, body mismatch, duplicate POST,
16-record cap, monotonic TTL, restart, malformed/oversized response, per-ID
partial/unknown result, source device mismatch, unknown agent worker cleanup,
Stop just before local handoff and Stop after HTTP handoff but before PhotoKit.
The latter permits only already-delivered bounded native work and must NEVER
assert zero submission. These are future builder/reviewer/qualification tests;
none ran in this planning correction.
