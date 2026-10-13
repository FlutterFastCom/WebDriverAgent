# Make Coordinate-Only WDA Input Accessibility-Free

Status: SUPERSEDED
Superseded-By: tasks/2026-10-13-220329-wda-additive-raw-touch-routes.md
Risk-Class: critical-stateful
Risk-Class-Justification: Existing remote physical-input routes change target authority from an accessibility-resolved application to device-level delivery on the selected display. A foreground replacement, pose/display change, synthesis timeout, retry, or partially completed multi-chunk scroll can mutate the wrong visible surface or duplicate a mutation.
Created: 2026-10-13
Feature-Folder: /Users/dmitrydyachenko/orca/workspaces/titan-ai-mediator/testing-strategy/missions/2026-10-12-new-standalone-tiktok-strategy-reply-to-buyer-qu/features/wda-raw-touch
Execution mode: single builder turn
Test-Mandate: SUSPENDED by operator decision 2026-08-14. Add, edit, adapt, restore, or run no tests, fixtures, snapshots, coverage, benchmarks, or red proofs. Delete only the two contradicted integration-test methods named below. Acceptance is real-stack TESTBED behavior.

## Goal

Route the iOS/iPadOS coordinate-only tap, drag, touch-and-hold, direction-scroll,
Bezier-swipe, window-size, and screen-info families through selected-screen and
device-event APIs without resolving an application, element, accessibility
snapshot, window, status bar, or quiescence state. Preserve every listed HTTP
path, request body, success envelope, and downstream agent/backend contract.
Deliver AC-01 through AC-10 in one builder turn.

## Files To Modify

| File | Required change |
| --- | --- |
| `WebDriverAgentLib/Commands/FBElementCommands.m` | Split the no-UUID tap, drag, touch-and-hold, and direction-scroll branches before `targetFromRequest:`; use the raw selected-screen path. Make both `/window/size` registrations use device screen metrics. Preserve all UUID-bearing branches and `/window/rect`. |
| `WebDriverAgentLib/Commands/FBCustomCommands.m` | Produce `/wda/screen` from the same device screen metrics, remove the system/active-app and status-bar queries, preserve the response keys, and report `statusBarSize` as zero. |
| `WebDriverAgentLib/Commands/FBInputCommands.m` | Replace both `/wda/touch/swipe-bezier` W3C/application paths with the raw path while retaining the legacy and `continuous_drag_v1` schemas, timing limits, response bodies, and 400/500 family. |
| `WebDriverAgentLib/Categories/XCUIApplication+FBTouchAction.h` | Declare the class-level raw viewport-path synthesis entry point on the existing touch owner; add no new helper type or file. |
| `WebDriverAgentLib/Categories/XCUIApplication+FBTouchAction.m` | Build raw `XCPointerEventPath`/`XCSynthesizedEventRecord` records from captured screen context, apply the existing secondary-display correction, and call the bounded daemon proxy without app stability waits. Preserve the instance/element path. |
| `WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.h` | Declare bounded device-interface orientation lookup and bounded event synthesis while preserving the existing unbounded API for unchanged consumers. |
| `WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.m` | Implement the two bounded device calls through `XCUIDevice.sharedDevice.deviceEventAndStateInterface` and `eventSynthesizer`; do not touch the accessibility interface. |
| `WebDriverAgentLib/Utilities/FBScreen.h` | Declare one shared selected-screen context/geometry method used by all new raw callers. |
| `WebDriverAgentLib/Utilities/FBScreen.m` | Resolve the selected `XCUIScreen`, current device interface orientation, and oriented logical size once per request; retain the existing display-selection owner. |
| `docs/multiple-displays.md` | Document device-orientation geometry, raw coordinate targeting, captured display context, zero status-bar metadata, and the retained element/app-relative behavior. |
| `package.json` | Conditional release companion: bump only if the staged-runtime version guard requires an increase; otherwise leave byte-identical. Do not change scripts, dependencies, or metadata. |

No source file is created, extracted, or added to the Xcode project. The nine
runtime header/implementation edits are one coupled input slice; splitting the
screen context from its consumers would leave an unused intermediate API and
does not buy parallel work or a required review foundation.

## Required Test Deletions

Delete only these now-contradicted methods from
`WebDriverAgentTests/IntegrationTests/FBScreenTests.m`; do not adapt, replace, or
add test content, and do not put this test file in `planned_files`:

- `testScreenInfoAcrossPortraitAndLandscapeOrientations`, because it requires a
  nonzero accessibility-derived status bar in portrait.
- `testScreenInfoIncludesTopStatusBarOnSingleDisplay`, because the new
  accessibility-free `/wda/screen` contract always publishes a zero status bar.

All other content in that file remains unchanged. No other existing test was
found to require the removed status-bar query or the migrated raw route internals.

## Non-Goals

- No change to element-UUID tap, drag, touch-and-hold, scroll, scroll-to-visible,
  element origins, or W3C actions.
- No change to `/window/rect`, `/wda/swipe`, double-tap, force-touch,
  press-and-drag-with-velocity, picker, alert, source, active-app, foreground,
  tap-by-predicate, Settings, Wi-Fi, Photos, or keyboard endpoints.
- No active-application replacement, foreground assertion, app allowlist,
  acknowledgement from the target app, retry, deduplication, rollback, or UI
  settled guarantee.
- No change in the agent allowlist, backend descriptors/interpreters, desktop
  WDA client, route names, session substitution, capability token, or response
  envelope.
- No new raw-input component, action synthesizer, orientation store, display
  setting, dependency, project-file entry, or generated source.
- No tvOS/watchOS raw-input behavior claim. Keep those targets compiling and
  retain their existing platform-specific behavior where the iOS private touch
  APIs are unavailable.
- No committed test/fixture work beyond the two deletion-only removals above.

## Architect Intake

Intent-Surfaces: wda-coordinate-input, multiple-displays
GROUNDED-IN: docs/multiple-displays.md

```architect-intake-v1 json
{
  "intent_surfaces": [
    "wda-coordinate-input",
    "multiple-displays"
  ],
  "grounded_in": [
    "docs/multiple-displays.md"
  ],
  "invariants": [
    {
      "id": "coordinate-only-input-has-no-accessibility-reachability",
      "universal": "EVERY activeApplication occurrence in the three declared command owners is classified so the enumerated no-UUID coordinate and geometry branches have no reachable application or accessibility read while all excluded application/element branches retain their existing owner.",
      "census_needle": "activeApplication",
      "search_roots": [
        "WebDriverAgentLib/Commands/FBElementCommands.m",
        "WebDriverAgentLib/Commands/FBCustomCommands.m",
        "WebDriverAgentLib/Commands/FBInputCommands.m"
      ],
      "planned_files": [
        "WebDriverAgentLib/Commands/FBElementCommands.m",
        "WebDriverAgentLib/Commands/FBCustomCommands.m",
        "WebDriverAgentLib/Commands/FBInputCommands.m",
        "WebDriverAgentLib/Categories/XCUIApplication+FBTouchAction.h",
        "WebDriverAgentLib/Categories/XCUIApplication+FBTouchAction.m",
        "WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.h",
        "WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.m",
        "WebDriverAgentLib/Utilities/FBScreen.h",
        "WebDriverAgentLib/Utilities/FBScreen.m",
        "docs/multiple-displays.md",
        "package.json"
      ],
      "sites": [
        {
          "path": "WebDriverAgentLib/Commands/FBElementCommands.m",
          "classification": "migrated",
          "reason": "Only the no-UUID coordinate branches and window-size handler move to captured device screen context; every UUID-bearing or excluded application branch keeps its existing accessibility owner."
        },
        {
          "path": "WebDriverAgentLib/Commands/FBCustomCommands.m",
          "classification": "migrated",
          "reason": "The screen-info handler stops reading the system/active application and status-bar elements; unrelated custom handlers keep their existing application behavior."
        },
        {
          "path": "WebDriverAgentLib/Commands/FBInputCommands.m",
          "classification": "migrated",
          "reason": "Only both swipe-bezier modes stop obtaining fb_activeApplication; keyboard and field commands remain accessibility-owned."
        }
      ]
    }
  ]
}
```

The repository reuse search is recorded in the feature `design.md`. Its locked
result is to extend `XCUIApplication+FBTouchAction`, `FBScreen`, and
`FBXCTestDaemonsProxy`, and reuse `FBDisplayCoordinateOffset`,
`FBScrollGestureOffsets`, `XCPointerEventPath`, and
`XCSynthesizedEventRecord`; do not create a parallel raw-touch helper.

## Rules

### R1 — One captured device screen context

Add one `FBScreen` method that returns the display selected by
`currentDisplayId` (or the main display), the current device **interface**
orientation, and that screen's oriented logical size. On iOS/iPadOS it must:

1. call the existing `currentScreenWithError:` exactly once;
2. read orientation once through the new bounded daemon-proxy method;
3. require a nonempty finite `screen.bounds`, a finite positive scale, and one
   of portrait, portrait-upside-down, landscape-left, or landscape-right;
4. divide native bounds by scale, normalize a landscape-native panel back to
   portrait when the interface is portrait, then reuse
   `FBAdjustDimensionsForApplication` for the final orientation; and
5. return no context on either display or orientation failure. Never fall back
   to the main display, portrait, physical `UIDeviceOrientation`, or an app.

The handler captures this context after request validation and before the first
event. Every event in one request, including every scroll chunk, uses that same
screen ID, orientation, size, and correction. A concurrent setting/pose change
affects the next request; it does not cause resampling inside this one. Preserve
the existing native-bounds behavior on tvOS/watchOS without introducing an app
lookup.

### R2 — Bounded device calls, not accessibility calls

In `FBXCTestDaemonsProxy`, add a two-second bounded orientation lookup through
`XCUIDevice.sharedDevice.deviceEventAndStateInterface` and
`getInterfaceOrientationWithReply:`. The Xcode 27 callback is
`(NSInteger orientation, NSError *error)`. Reject a missing selector, timeout,
reported error, or `UIInterfaceOrientationUnknown`; never consult
`XCUIApplication`, `FBXCAXClient`, an application monitor, or a snapshot as a
fallback.

Add a separate bounded event-synthesis overload. Keep the existing
`synthesizeEventWithRecord:error:` behavior for its unchanged callers. The raw
path supplies `last path offset + 2 seconds`, with a maximum scheduled path
offset of ten seconds. Treat a false completion result as failure even when
XCTest supplies no `NSError`. On timeout, return an error and release the WDA
command queue; the event's physical outcome is uncertain and neither the proxy
nor a handler retries it.

### R3 — Raw viewport path owner

Extend the existing touch-action category with one class-level method accepting
a name, nonempty point list, same-length absolute-offset list, lift offset, and
the captured screen/orientation. It must reject non-finite points or offsets,
an initial offset other than zero, negative/decreasing later offsets, a lift
before the final move, or a final lift over ten seconds before invoking the
synthesizer.

Construct one `XCPointerEventPath` from the first point at offset zero, add the
remaining moves at their absolute offsets, lift at the supplied offset, add it
to one `XCSynthesizedEventRecord`, and call only the bounded proxy overload. For
the main display, use the orientation initializer. For a secondary display,
require `initWithName:displayID:interfaceOrientation:`; otherwise fail without
touching the main display. Apply `FBDisplayCoordinateOffset` to **every raw
viewport point** using main/selected logical native sizes and the captured
orientation, exactly as the existing W3C selected-display path does.

Do not instantiate or query `XCUIApplication`/`XCUIElement`, resolve
`screenPoint`, build W3C actions, call `fb_waitUntilStableWithTimeout:`, or wait
for application quiescence. Preserve the existing instance methods and
`fb_pressDragEventFromPoint:...` behavior for element-owned callers.

### R4 — Route-family dispatch and gestures

In `FBElementCommands`, test for `request.parameters[@"uuid"]` before any call
to `targetFromRequest:` or `targetWithXyCoordinatesFromRequest:`:

- **Tap, no UUID:** require finite JSON-number `x` and `y`; synthesize touch down
  at offset zero and lift at 0.125 seconds.
- **Touch-and-hold, no UUID:** require finite JSON-number `x`, `y`, and
  `duration`, with `0 <= duration <= 10`; touch down at zero and lift at
  `duration`.
- **Drag, no UUID:** require finite JSON-number `fromX`, `fromY`, `toX`, `toY`,
  and `duration`, with `duration >= 0`. Match the existing default-velocity
  path: optional stationary start move after `duration`, then move to the end at
  500 points/second and lift there. Reject before synthesis if the calculated
  final offset is non-finite or exceeds ten seconds.
- **Scroll, no UUID:** accept only lowercase `up`, `down`, `left`, or `right`,
  plus the existing optional numeric `distance` (default `1.0`), now required to
  be finite and `0 < distance <= 1`. Use the full selected logical screen frame,
  the existing direction signs, 0.75-frame maximum chunk, quarter/three-quarter
  touch anchors, 0.5-second initial/end holds, 300 points/second, and at most two
  deliberate chunks. Capture context once. Stop on the first failed chunk; do
  not roll back or retry a completed prefix.

A no-UUID scroll request with `name`, `predicateString`, or `toVisible` but no
valid direction returns invalid argument before any app lookup. An unsupported
direction no longer returns a false OK. When a UUID is present, execute the
current handler body and precedence exactly, including element-relative
coordinates, name/predicate/to-visible lookup, snapshot scrolling, and existing
errors.

Coordinates are finite viewport points and are not clamped or hit-tested. Edge
or outside-screen delivery remains XCTest's decision; the ten-second path bound
prevents an extreme drag from occupying the queue indefinitely.

### R5 — Bezier modes

Both `/wda/touch/swipe-bezier` modes use R1/R3 and never call
`XCUIApplication.fb_activeApplication` or `fb_performW3CActions:`.
Remove the obsolete `XCUIApplication **` parser output and the private
viewport-frame/point-containment helpers once their only app/window caller is
gone; do not leave dead static functions.

- **Legacy:** retain required `from`, `to`, and `durationMs`; optional
  `controlPoints` defaults empty and remains capped at ten. Require each point
  member to be an exact finite JSON number. Preserve duration clamping to
  100–10000 ms, step calculation, interpolator, evenly distributed moves,
  `controlPointCount`, measured response `durationMs`, and the existing success
  keys.
- **`continuous_drag_v1`:** retain exact top-level/nested keys, empty control
  points, finite endpoints, move duration 100–5000 ms, start/end holds 0–2000
  ms, steps 1–60, and total planned duration at most 8000 ms. Remove only the
  active-app/window existence and containment reads. Touch down, hold at the
  start, distribute moves evenly, hold at the end, then lift.

Malformed requests return the existing invalid-argument/HTTP 400 family before
screen lookup. A selected-display/orientation/synthesis failure retains the
custom HTTP 500 `gesture_failed` object with `message` and measured
`durationMs`. Retain both exact success object shapes and capability token.

### R6 — Geometry endpoints

Both session and sessionless `/window/size` registrations return
`{"width", "height"}` from R1. They no longer represent an app compatibility
window. `/window/rect` remains app-owned and unchanged.

Both `/wda/screen` registrations return the existing object keys:

```json
{
  "screenSize": {"width": 0, "height": 0},
  "statusBarSize": {"width": 0, "height": 0},
  "displayId": 0,
  "scale": 0
}
```

The zeroes above illustrate shape, not literal screen values. `screenSize`,
`displayId`, and `scale` come from R1; `statusBarSize.width` and `.height` are
always exactly zero because WDA cannot discover foreground status-bar geometry
without an accessibility/app query. A missing selected display remains invalid
argument. Device-orientation failure is unknown error for geometry endpoints.
Keep display-selection failures distinguishable from orientation/service
failures with typed error codes; handlers must not classify them by matching
localized message text.

### R7 — Wire, ownership, and acknowledgement

Preserve these exact endpoints and request spellings:

```text
POST /session/{id}/wda/tap                    {x,y}
POST /session/{id}/wda/dragfromtoforduration {fromX,fromY,toX,toY,duration}
POST /session/{id}/wda/touchAndHold           {x,y,duration}
POST /session/{id}/wda/scroll                 {direction[,distance]}
POST /wda/touch/swipe-bezier                  existing legacy/held bodies
GET  /session/{id}/window/size
GET  /wda/screen
```

Tap, drag, hold, and scroll success remains W3C `{value:null}`. Geometry and
Bezier shapes remain as stated above. No agent/backend/desktop change is needed.

Raw delivery intentionally does not assert that the session app is foreground.
It targets the selected display's currently visible surface at physical event
time, including a system alert or a different foreground app. Synthesis
completion means only that XCTest completed the event request; it does not mean
the intended control changed or the UI settled. Callers remain responsible for
fresh screenshot/app-state verification. WDA performs no automatic retry,
deduplication, replay, or rollback.

### R8 — Accessibility exclusion boundary

Every reachable path for the enumerated no-UUID/raw families—including malformed
input, unavailable display, orientation failure, synthesis failure, and timeout—
must avoid all of these: `FBSession.activeApplication`,
`XCUIApplication.fb_activeApplication`, `XCUIApplication.fb_systemApplication`,
app `interfaceOrientation`, windows/status bars, `XCUIElement` queries or
frames, accessibility snapshots, `FBXCAXClient`, coordinate anchors,
`FBW3CActionsSynthesizer`, and app stability/quiescence waits.

This rule does not apply to the expressly retained element/app-relative routes
in Non-Goals. Do not widen it to similarly named endpoints that are not in the
wire list.

## Case table

| case family | deciding rule | outcome | code site |
| --- | --- | --- | --- |
| Valid single-event raw input | No UUID; body passes family limits; R1 context exists | One bounded device event, existing success envelope, no app/AX read | `FBElementCommands.m` → `XCUIApplication+FBTouchAction.m` → `FBXCTestDaemonsProxy.m` |
| Valid direction scroll | No UUID; direction valid; `0 < distance <= 1` | One or two ordered chunks using one captured context; OK only after all complete | `FBElementCommands.m` |
| Valid Bezier input | Legacy or exact held schema passes its stated limits | One raw path; preserve that mode's response object | `FBInputCommands.m` |
| Geometry reads | Selected screen and device orientation available | Oriented logical selected-screen size; `/wda/screen` status bar is zero | `FBScreen.m`, `FBElementCommands.m`, `FBCustomCommands.m` |
| Malformed/unsupported/over-limit input | Any family parser or ten-second path bound fails | Invalid argument/HTTP 400; zero event attempts and zero app/AX reads | owning command handler; common path validation in `XCUIApplication+FBTouchAction.m` |
| Context refusal | Selected display missing, device orientation missing/times out/unknown, or secondary initializer unsupported | No event and no fallback; standard input reports invalid-argument for display or invalid-element-state for other input context failures; geometry reports invalid-argument for display or unknown-error for orientation | `FBScreen.m`, owning handler |
| Synthesis failure or timeout | Event call returns error or exceeds planned offset + 2 seconds | Stop, return existing family error; delivery may be uncertain; never retry | `FBXCTestDaemonsProxy.m`, owning handler |
| Retained accessibility input | UUID present, or route is expressly outside R7 | Existing application/element path and errors unchanged | existing branches in `FBElementCommands.m`, other command owners |
| Foreground/pose/display changes | Foreground may change at any time; screen context is captured once | Event reaches the visible surface; pose/display is not resampled; no ownership claim or main-display fallback | R1/R7; docs |

### Shared-invariant writer/reader census

| invariant | writers/owners | readers/consumers | disposition |
| --- | --- | --- | --- |
| `currentDisplayId` selection | `FBSettingsHandler.m:197-211`; session reset in `FBConfiguration.m:360` | canonical `FBScreen.m:109-116`; settings readback and `FBActiveAppDetectionPoint.m`; indirect screenshot, MJPEG, recording, W3C and element-scroll consumers | Existing writers and outside readers unchanged; new raw callers consume only through `FBScreen` and never write it. |
| Device interface orientation | XCTest device event/state service | new bounded `FBXCTestDaemonsProxy`; aggregated once by `FBScreen`; consumed by the three command owners and touch category | One device-derived value per raw request; existing app-derived orientation readers remain only on excluded paths. |
| Oriented selected-screen geometry | new `FBScreen` context method | `/window/size`, `/wda/screen`, raw touch/drag/scroll/Bezier | One calculation owner; no duplicate screen-size formula in handlers. |
| Raw path duration limit | command-specific parsers plus final common validator | bounded event timeout and every raw gesture family | Final lift is at most ten seconds at every writer; proxy wait is final lift + two seconds. |
| Public wire | WDA handlers write responses | agent `wda_proxy_allowlist.rs`; backend `wda_request_wire.rs`, `wda_assemble_input.rs`, `interpret.rs`; desktop `wda-http-client.ts` | Paths/bodies/success shapes stay compatible; no downstream edit. |

## Proof: State Table

| state/event class | next observable state |
| --- | --- |
| Valid raw request before context capture | No physical input yet; request owns one immutable screen context or refuses. |
| Valid context before bounded synthesis | One event record is ready; still no app/AX state has been read. |
| Single event completion | Return the existing success body; the UI result remains caller-verified. |
| Scroll chunk completion with remainder | Keep the same context and issue the next deliberate chunk; a completed prefix is physical state. |
| Validation/context failure before first event | Return the family error with no touch. |
| Synthesis error/timeout | Return failure; physical outcome is uncertain and no local retry occurs. |
| UUID/app-relative request | Stay in the existing accessibility-owned state machine. |

## Proof: Linearization

A single raw gesture linearizes at XCTest's device event synthesizer, not at HTTP
receipt, context capture, or response serialization. Each scroll chunk has its
own physical linearization point; the route succeeds only after all planned
chunks complete. `/window/size` and `/wda/screen` linearize at the one captured
selected-screen/orientation sample. A success acknowledges synthesis/measurement
only and never acknowledges application intent or UI settlement.

## Proof: Interruption Matrix

| interruption point | determined outcome |
| --- | --- |
| Before first synthesizer call | No touch occurred; return validation/context error when known. |
| During one synthesizer call | Completion error/timeout means uncertain delivery; return failure and do not retry. |
| Between scroll chunks | Earlier chunks remain applied; stop on the first failure, report failure, no rollback/retry. |
| After physical completion but before HTTP response reaches caller | Delivery may have occurred; a caller retry can duplicate it because WDA adds no deduplication. |
| Selected display disappears or orientation changes after capture | Continue with the captured context; failure has no main-display/portrait fallback and any completed prefix remains. |

## Proof: Supersession

No request supersedes, cancels, or deduplicates another. The existing WDA command
queue orders commands. A `currentDisplayId` update or rotation observed after a
raw request captured context applies to later commands, not to later chunks of
the current command. A foreground-app change is not a supersession signal: the
low-level event still targets whatever surface is visible when delivered.

## Proof: Red Tests

The operator suspended the test mandate on 2026-08-14 and banned added/edited
test content on 2026-09-24. No red test, fixture, snapshot, coverage target, or
replacement for the two deletion-only methods is authorized. AC-01 through
AC-10 are real-stack TESTBED observations and this section creates no test-file
implementation obligation.

## Acceptance

- **AC-01:** With a playing TikTok video whose accessibility tree does not
  answer, a coordinate tap on the comment control returns in under one second,
  the comment sheet is visible in a fresh screenshot, and the next `/status`
  request succeeds.
- **AC-02:** On the same AX-blocked surface, raw drag, touch-and-hold,
  direction-scroll, legacy Bezier, and `continuous_drag_v1` each produce their
  intended physical gesture and complete without waiting for an application,
  window, element, snapshot, or quiescence state.
- **AC-03:** `/session/{id}/window/size` and `/wda/screen` remain responsive on
  the AX-blocked surface and report the same positive oriented logical width and
  height for the selected display. `/wda/screen` preserves `screenSize`,
  `statusBarSize`, `displayId`, and `scale`, with both status-bar dimensions zero.
- **AC-04:** Portrait, portrait-upside-down, landscape-left, and
  landscape-right report correctly swapped dimensions and hit the requested
  point; at least one landscape tap lands on the visually expected control.
- **AC-05:** `currentDisplayId` selects the reported/touched display. An
  unavailable display or unsupported secondary-display event initializer fails
  without touching the main display.
- **AC-06:** Missing, Boolean, nonnumeric, non-finite, unsupported-direction,
  invalid-distance, invalid-timing, excessive-path, and malformed Bezier values
  fail before physical input; WDA remains responsive afterward.
- **AC-07:** A synthesizer error or timeout causes no WDA retry. A failed
  multi-chunk scroll stops after its completed prefix, and the response does not
  claim rollback or target-app success.
- **AC-08:** If an alert or another app becomes the visible surface before
  delivery, raw input targets that visible surface without a false session-app
  guarantee; callers can detect the result with their existing fresh
  screenshot/app-state checks.
- **AC-09:** UUID-bearing element gestures, name/predicate/to-visible element
  scroll, `/window/rect`, tap-by-predicate, alerts, source, active-app,
  Settings/Wi-Fi/Photos, keyboard, and other excluded endpoints retain their
  current accessibility behavior and wire results.
- **AC-10:** Existing clients require no wire change: the four standard gesture
  routes still return `{value:null}`, both Bezier success objects keep their
  exact keys, both geometry objects keep their exact keys, and the agent/backend
  continue to read `screenSize.width/height` without adaptation.

## Verification Commands

Do not run repository tests. After implementation, the builder runs only:

```bash
# From /Users/dmitrydyachenko/Desktop/electron-farm
bash wda/scripts/build-wda-ipa.sh

# From this WebDriverAgent checkout: inspect the scoped diff and forbidden raw dependencies.
git diff --check
git diff -- WebDriverAgentLib/Commands/FBElementCommands.m \
  WebDriverAgentLib/Commands/FBCustomCommands.m \
  WebDriverAgentLib/Commands/FBInputCommands.m \
  WebDriverAgentLib/Categories/XCUIApplication+FBTouchAction.h \
  WebDriverAgentLib/Categories/XCUIApplication+FBTouchAction.m \
  WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.h \
  WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.m \
  WebDriverAgentLib/Utilities/FBScreen.h \
  WebDriverAgentLib/Utilities/FBScreen.m \
  WebDriverAgentTests/IntegrationTests/FBScreenTests.m \
  docs/multiple-displays.md package.json
```

The conductor/testbed then installs the built IPA and verifies AC-01 through
AC-10 on the real iPhone/TikTok stack, including a landscape point and a fresh
post-gesture screenshot plus `/status`. A 200 response without visible effect is
not sufficient evidence.
