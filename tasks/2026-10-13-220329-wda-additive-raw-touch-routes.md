# Add Accessibility-Free Group B Routes Beside Existing WDA Routes

Status: READY_FOR_IMPLEMENTATION
Risk-Class: critical-stateful
Risk-Class-Justification: This unit adds device-level physical input whose timeout can leave delivery uncertain, adds a foreground-state alternative consumed for ownership decisions, and changes HTTP connection finalization for every WDA route. A wrong coordinate authority, duplicate synthesis, swallowed completion failure, close flag lost across an interruption path, or accidental legacy-route migration can mutate the wrong visible surface or make a caller repeat a command after a false timeout.
Created: 2026-10-13
Feature-Folder: /Users/dmitrydyachenko/orca/workspaces/titan-ai-mediator/testing-strategy/missions/2026-10-12-new-standalone-tiktok-strategy-reply-to-buyer-qu/features/wda-raw-touch
Execution mode: one unit, one builder turn
Supersedes: tasks/2026-10-13-wda-accessibility-free-coordinate-input.md
Test-Mandate: SUSPENDED by operator decision 2026-08-14. Add, edit, adapt, delete, or run no tests, fixtures, snapshots, coverage, benchmarks, or red proofs. Acceptance is real-stack TESTBED behavior.

## Goal

Add one accessibility-free raw twin for every operator-defined Group B family while retaining every existing route unchanged: coordinate tap, linear swipe, main-screen geometry, long press, direction scroll, Bezier/held swipe, delayed typing, clear-field input, and foreground checking by caller-supplied bundle state. Raw physical input must use bounded `XCSynthesizedEventRecord` delivery without an application, element, accessibility snapshot, window, status bar, quiescence wait, or foreground tracker.

Also make WDA honor a client's `Connection: close` request after writing that request's complete response, so the unchanged Titan agent can finish its EOF-framed reads and reach the new routes. Deliver AC-01 through AC-12 as one release slice.

## Files To Modify

| File | Required change |
| --- | --- |
| `WebDriverAgentLib/Routing/FBWebServer.m` | At the shared request adapter, distinguish zero-length raw bodies from nonempty malformed or non-object JSON before mounting only the `/wda/raw/` namespace; pass `{}` for zero-length bodies, pass parsed dictionaries unchanged, and return W3C `invalid argument` for every other nonempty raw body while preserving every non-raw route's current parse/fallback behavior. |
| `WebDriverAgentLib/Routing/FBHTTPServer.m` | Parse `Connection` as a case-insensitive token list, carry the request-local close decision through every response path, discard later bytes for that client, emit `Connection: close`, and close only after the complete response write. |
| `WebDriverAgentLib/Utilities/FBScreen.h` | Declare the shared captured portrait/main-display context used by raw geometry and all raw coordinate routes. |
| `WebDriverAgentLib/Utilities/FBScreen.m` | Read `XCUIScreen.mainScreen` bounds/scale/display ID once, reject non-main `currentDisplayId`, validate finite positive portrait geometry, and return logical points without consulting an app. |
| `WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.h` | Declare the bounded event-synthesis overload; retain the existing overload and contract. |
| `WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.m` | Implement one-shot bounded synthesis that honors completion Boolean and error, distinguishes timeout, ignores late completion for response purposes, and never resends. |
| `WebDriverAgentLib/Commands/FBInputCommands.m` | Register and implement raw tap, swipe, screen, long-press, direction-scroll, Bezier/held-swipe, delayed-type, and clear-field routes with closed schemas and shared raw builders. Do not change existing handlers. |
| `WebDriverAgentLib/Commands/FBSessionCommands.m` | Add the sessionless per-bundle raw app-state route by reading only `XCUIApplication.state` for the supplied bundle. Do not change existing session/app/status routes. |
| `WebDriverAgentLib/Commands/FBCustomEndpointTokens.m` | Advertise exactly the nine raw family tokens on iOS/iPadOS while retaining every existing token. |
| `docs/multiple-displays.md` | Document the additive raw family, portrait/main-display boundary, keyboard-focus and app-state meanings, queue behavior, timeout uncertainty, and unchanged legacy behavior. |
| `package.json` | Conditional release companion: bump only if the staged-runtime version guard requires an increase; otherwise leave byte-identical. Change no script, dependency, or other metadata. |

No source file is created or extracted, and `WebDriverAgent.xcodeproj/project.pbxproj` is not edited. No test file is created, edited, adapted, or deleted.

## Architect Intake

Intent-Surfaces: wda-group-b-raw-input, wda-http-framing, wda-bundle-state, multiple-displays
GROUNDED-IN: docs/multiple-displays.md

```architect-intake-v1 json
{
  "intent_surfaces": [
    "wda-group-b-raw-input",
    "wda-http-framing",
    "wda-bundle-state",
    "multiple-displays"
  ],
  "grounded_in": [
    "docs/multiple-displays.md"
  ],
  "invariants": [
    {
      "id": "raw-input-handlers-have-no-active-application-dependency",
      "universal": "EVERY activeApplication occurrence in WebDriverAgentLib/Commands/FBInputCommands.m remains confined to pre-existing non-raw handlers; every /wda/raw input, keyboard, and geometry handler plus every helper reachable only from those handlers contains no activeApplication read or call.",
      "census_needle": "activeApplication",
      "search_roots": [
        "WebDriverAgentLib/Commands/FBInputCommands.m"
      ],
      "planned_files": [
        "WebDriverAgentLib/Routing/FBWebServer.m",
        "WebDriverAgentLib/Routing/FBHTTPServer.m",
        "WebDriverAgentLib/Utilities/FBScreen.h",
        "WebDriverAgentLib/Utilities/FBScreen.m",
        "WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.h",
        "WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.m",
        "WebDriverAgentLib/Commands/FBInputCommands.m",
        "WebDriverAgentLib/Commands/FBSessionCommands.m",
        "WebDriverAgentLib/Commands/FBCustomEndpointTokens.m",
        "docs/multiple-displays.md",
        "package.json"
      ],
      "sites": [
        {
          "path": "WebDriverAgentLib/Commands/FBInputCommands.m",
          "classification": "not-applicable",
          "reason": "Existing delayed typing, clear-field, no-a11y clear-field, and Bezier handlers retain their application reads; additive raw handlers neither call those handlers nor add another activeApplication occurrence."
        }
      ]
    }
  ]
}
```

## Scope & Decomposition

- **One binding unit:** the later operator decision in `OPERATOR-DECISION-2026-10-13.md` requires all Group B raw families in one unit. The earlier three-route scope in `REPLAN-BRIEF.md` is superseded where it conflicts.
- **Why this still fits one turn:** nine runtime source files are modified, with the ninth limited to the raw-only request-adapter seam; no new source/project wiring is needed, and the repeated route work shares one geometry capture, event-record builder family, bounded synthesizer, error mapper, queue contract, capability publication, and IPA/version boundary.
- **Why no parallel cut helps:** the input families converge in `FBInputCommands.m`; all mutations depend on the same bounded proxy; all coordinate mutations depend on the same screen context; and the unchanged agent cannot observe any route until the HTTP close fix lands. Splitting creates ordered units that edit shared files without enabling parallel building.
- **Pattern:** additive capability endpoints beside retained accessibility endpoints, with closed validation and a fail-closed device-event adapter. This is not a migration of any W3C/Appium/custom route.

## Architecture Locks

### L1 — Exact additive wire and capability set

Register exactly these ordinary, sessionless routes on iOS/iPadOS (`!TARGET_OS_TV && !TARGET_OS_WATCH`):

| method and path | exact request body | success `value` | token |
| --- | --- | --- | --- |
| `POST /wda/raw/tap` | `{"x":number,"y":number}` | `null` | `raw.tap` |
| `POST /wda/raw/swipe` | `{"fromX":number,"fromY":number,"toX":number,"toY":number,"duration":number}` | `null` | `raw.swipe` |
| `GET /wda/raw/screen` | no body fields | `{"width":number,"height":number,"scale":number}` | `raw.screen` |
| `POST /wda/raw/long-press` | `{"x":number,"y":number,"duration":number}` | `null` | `raw.long-press` |
| `POST /wda/raw/scroll` | `{"direction":string enum}` | `null` | `raw.scroll` |
| `POST /wda/raw/swipe-bezier` | L5 legacy or held shape | `null` | `raw.swipe-bezier` |
| `POST /wda/raw/keyboard/type-with-delay` | `{"text":string,"charDelayMs":integer}` | `null` | `raw.keyboard.type-with-delay` |
| `POST /wda/raw/keyboard/clear-field` | `{}` or `{"approxChars":integer}` | `null` | `raw.keyboard.clear-field` |
| `POST /wda/raw/apps/state` | `{"bundleId":string}` | `{"bundleId":string,"state":integer,"isForeground":boolean}` | `raw.apps.state` |

All mutation successes use `FBResponseWithOK()`. All nine routes reject any query parameter with W3C `invalid argument`. Do not add aliases, session-prefixed registrations, display selectors, retry/idempotency fields, success metrics, or raw variants for Group A or Group C. Each route is `.withoutSession` and deliberately not `.standalone`.

Append exactly the nine table tokens to `FBCustomEndpointTokensList` under the same platform guard. `/status` remains the publisher through `customEndpoints`. A raw-mode consumer must require all nine; neither WDA nor a later consumer may silently fall back to an accessibility route.

### L2 — One captured portrait main-display context

Add this exact utility shape to `FBScreen.h`:

```objc
typedef struct {
  CGSize logicalSize;
  double scale;
  unsigned long long displayID;
} FBRawMainScreenContext;

+ (BOOL)rawPortraitMainScreenContext:(FBRawMainScreenContext *)context
                               error:(NSError **)error;
```

For each call, read `XCUIScreen.mainScreen` once and `FBConfiguration.sharedInstance.currentDisplayId` once. Accept a nil selection or the captured main screen's exact `displayID`; reject every other selected display before returning geometry or attempting input. Never fall back silently from a selected secondary display.

Capture `bounds`, `scale`, and `displayID` from that screen. Require finite positive bounds width/height and scale; derive logical width/height as bounds divided by scale; require finite positive results and `logicalWidth < logicalHeight`. Version 1 is portrait-only and does not inspect device orientation, application interface orientation, a window, status bar, or accessibility-derived orientation. Return the one captured context used for validation and record construction. `GET /wda/raw/screen` serializes only its logical width, height, and scale.

Do not call `currentScreenWithError:` because it follows the selected display. Do not instantiate or query an application, element, `UIScreen`, app window, status bar, `FBXCAXClient`, or `FBForegroundTracker` from this helper or a raw input/keyboard handler.

### L3 — Common closed validation and event-record authority

`FBWebServer.m` owns raw-body envelope admission before constructing and mounting an `FBRouteRequest`. For a registered route whose final path is in the `/wda/raw/` namespace, apply exactly this family rule:

- When `request.body.length == 0`, use an empty dictionary. This is the sole representation of an absent/no-content body at this adapter and keeps `{}`-accepting raw clear-field plus bodyless raw screen reachable.
- When the body is nonempty, parse it with the adapter's existing `NSJSONReadingMutableContainers` option. Pass the parsed value onward only when it is an `NSDictionary`; an empty JSON object is valid at this layer.
- When parsing fails or the top-level JSON value is any non-dictionary fragment/container (including a Boolean, number, string, `null`, or array), dispatch W3C `invalid argument` with message `Raw route body must be a JSON object`, do not mount the route, and therefore perform no app-state read, event-record construction, or event submission.

The branch is selected from the registered raw route path, not from client-controlled body content. Every non-raw route must continue through the existing `JSONObjectWithData:options:error:` plus `arguments ?: @{}` behavior with the same observable status, message, logging, exception, and handler semantics; do not make strict JSON-object admission global.

Reuse `FBInputCommands.m`'s exact-dictionary and finite-JSON-number helpers and extend local helpers rather than creating another command/service file. JSON Booleans are not numbers. Every raw body is a closed schema: reject unknown/missing fields, wrong container types, strings/null/Booleans in numeric positions, non-finite values, non-integral integer fields, and out-of-range values with W3C `invalid argument` before constructing or submitting an event.

Every raw coordinate, including Bezier control points, must satisfy `0 <= x < logicalWidth` and `0 <= y < logicalHeight` against one L2 context. Do not clamp, normalize, percent-convert, hit-test, infer a target app, or transform orientation.

For pointer input, create exactly one `XCSynthesizedEventRecord` and one `XCPointerEventPath`. Use `UIInterfaceOrientationPortrait`. Follow the existing runtime-compatibility branch from `XCUIApplication+FBTouchAction.m`: when `initWithName:displayID:interfaceOrientation:` is available, pass the captured main `displayID`; otherwise use `initWithName:interfaceOrientation:`, whose no-display fallback targets the main screen. Add the path once.

For keyboard input, create one record with `initWithName:` and one `initForTextInput` path; keyboard events go to the system's current keyboard focus. They do not select, find, inspect, or verify a field or keyboard. A successful response acknowledges XCTest synthesis only, never field content.

### L4 — Tap, linear swipe, long press, and direction scroll

- **Tap:** exact `x,y`; touch down at offset `0`, lift at `0.125` seconds.
- **Swipe:** exact four points plus finite seconds `duration` in `[0.01, 10.0]`; touch down at the start at `0`, linearly move to the end at `duration`, and lift at the same offset.
- **Long press:** exact `x,y,duration` with finite seconds in `[0.01, 10.0]`; touch down at `0`, lift at `duration`.
- **Direction scroll:** require the exact sole key `direction` and one of the four case-sensitive values `up`, `down`, `left`, or `right`. Preserve the existing scroll direction's content semantics with a fixed `0.25`-second linear swipe through the central 60% of the raw screen: `up` moves the finger from `(50%,20%)` to `(50%,80%)`; `down` reverses it; `left` moves `(20%,50%)` to `(80%,50%)`; `right` reverses it. Compute those points from the captured logical size, then pass through the common bounds rule.

### L5 — Raw Bezier and continuous-held swipe

`POST /wda/raw/swipe-bezier` accepts exactly one of these mutually exclusive shapes:

```json
{"from":{"x":1,"y":2},"to":{"x":3,"y":4},"controlPoints":[{"x":2,"y":3}],"durationMs":500}
```

```json
{"from":{"x":1,"y":2},"to":{"x":3,"y":4},"controlPoints":[],"durationMs":500,"held":{"mode":"continuous_drag_v1","startHoldMs":100,"moveSteps":30,"endHoldMs":100}}
```

The legacy top level has exactly `from,to,controlPoints,durationMs`; the held top level adds exactly `held`, whose dictionary has exactly `mode,startHoldMs,moveSteps,endHoldMs`. Every point dictionary has exactly `x,y`; `controlPoints` is an array with at most 10 points. All millisecond fields are exact nonnegative integers.

- **Legacy curve:** no `held` key; require `durationMs` in `[100,10000]`. Set steps to `MAX(10, floor(durationMs / 1000.0 * 60.0))`. Reuse `FBBezierInterpolator` and require exactly `steps + 1` returned points. Touch down on the first point at `0`; move through each later point at its proportional cumulative offset; lift at `durationMs / 1000.0`.
- **Held curve:** require `controlPoints` empty, `mode == "continuous_drag_v1"`, `durationMs` in `[100,5000]`, `startHoldMs` and `endHoldMs` each in `[0,2000]`, `moveSteps` in `[1,60]`, and total duration at most `8000` ms. Pass exactly `moveSteps` to `FBBezierInterpolator` with no controls and require `moveSteps + 1` returned points; begin at `0`, start proportional moves after `startHoldMs`, and lift after start hold + move duration + end hold.

Do not construct W3C action dictionaries or call `fb_performW3CActions:`. The existing `/wda/touch/swipe-bezier` handler and both of its schemas remain unchanged.

### L6 — Raw delayed typing and clear field

For delayed typing, require nonempty UTF-8 text of at most 8192 bytes and an exact integer `charDelayMs` in `[0,5000]`. Enumerate extended grapheme clusters in source order. Require `(clusterCount - 1) * charDelayMs <= 10000` ms, guarding multiplication overflow before the comparison. Add one `typeKey:modifiers:atOffset:` entry per cluster with no modifiers at cumulative offsets `index * charDelayMs / 1000.0`.

For clear field, accept either an empty dictionary or exactly one `approxChars` exact integer in `[1,256]`. Use `128` when absent. Add exactly that many `XCUIKeyboardKeyDelete` entries with no modifiers at offsets `index * 0.025` seconds. Do not use command-A, IOHID clear, an app/window/field/keyboard query, keyboard-relative coordinates, sleeps, or post-clear inspection. The caller must supply enough deletes for the focused field and verify the visible result.

The existing `/wda/keyboard/type-with-delay`, `/wda/keyboard/clear-field`, and `/wda/keyboard/clear-field-no-a11y` handlers remain byte-for-contract unchanged, including their current application/AX behavior and response shapes.

### L7 — Per-bundle state, not active-app discovery

`POST /wda/raw/apps/state` requires an exact body containing one nonempty `bundleId` string whose UTF-8 representation is at most 512 bytes. Construct `XCUIApplication` with that supplied identifier, read its `state` exactly once, and return the original bundle ID, numeric `XCUIApplicationState`, and `isForeground` equal only to `state == XCUIApplicationStateRunningForeground`. Catch an Objective-C exception as W3C `unknown error`.

This route may instantiate the named application solely for `.state`; it must not call `fb_activeApplication`, read `.identifier`, resolve an element/snapshot, enumerate active apps, launch/activate/terminate anything, or touch `FBForegroundTracker`. It does not discover an arbitrary foreground bundle and does not claim exclusive visible ownership: XCTest may report more than one bundle in foreground state. Consumers query the bundle they already know and use screenshot evidence when visible-surface identity matters.

The existing `/wda/activeAppInfo`, `/wda/foreground`, and session `/wda/apps/state` routes remain unchanged.

### L8 — Bounded synthesis and uncertain timeout

Keep `+[FBXCTestDaemonsProxy synthesizeEventWithRecord:error:]` and all existing callers unchanged. Add this raw-only overload:

```objc
+ (BOOL)synthesizeEventWithRecord:(XCSynthesizedEventRecord *)record
                          timeout:(NSTimeInterval)timeout
                       didTimeOut:(BOOL *)didTimeOut
                            error:(NSError **)error;
```

The overload validates a nonnil record plus finite positive timeout before submission, initializes `didTimeOut` to `NO`, submits to `XCUIDevice.sharedDevice.eventSynthesizer` exactly once, and spins the current run loop only until one completion or the deadline. It returns success only for completion Boolean `YES` with nil error. Convert Boolean `NO` with no error into a deterministic local error. On expiry, set `didTimeOut` to `YES`, return an error stating that physical delivery is uncertain, release the route queue, and let any later callback be ignored for HTTP-response/state purposes. Never cancel-and-resend, retry, replay, or call the unbounded overload.

Every raw mutation validates `record.maximumOffset` as finite and in `[0,10]`, then passes `record.maximumOffset + 2.0` seconds. A non-timeout completion failure maps to W3C `unknown error`. Timeout maps to W3C `timeout` (HTTP 408) with the semantic message `Raw input synthesis timed out; physical delivery is uncertain and WDA did not retry.`

### L9 — Honor `Connection: close` end to end

`FBHTTPServer.m` already normalizes request-header names to lowercase. Extend only its internal request/pending values and response dispatch:

1. Interpret every `Connection` field as comma-separated, case-insensitive tokens with surrounding HTTP whitespace trimmed. When duplicate `Connection` lines occur, append their values for this decision so a later line cannot mask an earlier exact `close` token. Preserve the duplicate handling of framing fields and the existing last-value behavior of unrelated fields.
2. Store `closeAfterResponse` on `FBPendingHTTPRequestHeader`, pass it through `dispatchMethod`, capture it for sessionless ordinary responses, and store it on every `FBPendingRequest` used by session abandonment and standalone leader/joiner paths. It belongs to one request/client, never a route, coalescing key, or server-global flag.
3. As soon as a complete close-marked request is consumed, discard already-buffered pipelined bytes and stop accepting later request bytes for that client while retaining enough state to write its response. Never dispatch those bytes.
4. Use the bit on normal completion, invalid-session-before-dispatch, session abandonment, route-not-found, and every standalone leader/joiner response. Existing malformed/framing failures already close and remain closing failures.
5. In `writeResponse`, remove every case-insensitive `Connection` field from that write's private header copy, add the single field `Connection: close`, write the complete status/headers/body, and call `closeClient:` only from the write completion. Do this normalization only when the bit is set. Without the bit, retain the existing response headers, keep-alive, ordered response, buffer, reaper, abandonment, and standalone behavior exactly.

Do not edit the agent's EOF reader or add `Content-Length` parsing outside existing WDA behavior in this unit.

### L10 — Queue, foreground, and retry boundary

All nine raw routes use `FBWebServer`'s existing shared main route queue. None is `.standalone`: that coalescing key is method plus path/query and omits the body, so different coordinates, text, bundle IDs, or clear counts could share one execution. Ordinary dispatch serializes raw calls in request order.

A raw request queued behind an earlier AX request that is already stuck does not execute and does not rescue that WDA. The supported operating condition is a fresh WDA process with no AX-producing request submitted while the target app's accessibility tree is unresponsive. A raw synthesis timeout releases only its own bounded wait; it cannot cancel earlier native work.

Raw mutations affect the system's visible main-display surface or current keyboard focus at physical delivery time. Success does not prove target-app identity, control activation, field contents, UI settlement, or exactly-once delivery after a lost response. WDA never retries. Raw handlers do not initialize or read `FBForegroundTracker`.

## Exceptions and Retained Behavior

- Group B is cut by capability family, not by legacy alias: `/wda/raw/screen` is the sole raw geometry twin for both `/window/size` and `/wda/screen`; `/wda/raw/keyboard/clear-field` is the sole raw clear twin for both existing clear-field strategies; and `/wda/raw/apps/state` is the sole named-bundle alternative for both active-app and cached-foreground checks. Do not add `/wda/raw/window/size`, `/wda/raw/keyboard/clear-field-no-a11y`, `/wda/raw/activeAppInfo`, or `/wda/raw/foreground` aliases.
- Existing `/session/{id}/wda/tap`, `/wda/dragfromtoforduration`, `/wda/touchAndHold`, `/wda/scroll`, `/wda/touch/swipe-bezier`, `/window/size`, `/wda/screen`, `/wda/keyboard/type-with-delay`, `/wda/keyboard/clear-field`, `/wda/keyboard/clear-field-no-a11y`, `/wda/activeAppInfo`, `/wda/foreground`, and session `/wda/apps/state` retain their registrations, bodies, handlers, responses, accessibility/app authority, display/orientation rules, and error behavior.
- Element routes, alerts, source, Settings, Wi-Fi, Photos, ordinary `/wda/keys`, buttons/home, lock state, app lifecycle, and every operator-defined Group A/Group C route remain unchanged and gain no twin here.
- Existing routes may continue using sessions, applications, elements, AX, selected displays, W3C synthesis, quiescence, status bars, and the existing unbounded synthesizer. This task neither repairs nor broadens them.
- Existing test files stay byte-identical. The superseded task's migrations and test deletions are revoked.
- No landscape, secondary-display, multi-finger, pressure, raw alert/source/element/Settings route, foreground discovery, cancellation, deduplication, idempotency key, or UI verification is added.

## Case table

| case family | deciding rule | outcome | code site |
| --- | --- | --- | --- |
| Close-delimited HTTP request | Any case-insensitive `Connection` token is exactly `close` | Write one complete response with `Connection: close`, then close that client; later buffered/received requests do not dispatch | `FBHTTPServer.m` parser → pending values → every response writer |
| Persistent HTTP request | No exact `close` token | Existing keep-alive, ordering, pipelining, abandonment, and standalone behavior | `FBHTTPServer.m` |
| Raw HTTP body envelope | The matched registered route is under `/wda/raw/`: a zero-length body maps to `{}`; a nonempty body is admitted only when JSON parsing succeeds with a dictionary root | Admitted dictionary proceeds to route-specific closed-schema validation; malformed JSON or any non-dictionary root returns W3C `invalid argument` before route mount and has no command side effect | `FBHTTPServer.m` body bytes → raw-only adapter branch in `FBWebServer.m` → raw handlers |
| Valid raw coordinate mutation | Exact route schema, admitted portrait main context, all points in half-open bounds, admitted duration/path limits | One record, one path, one bounded submission; success only after positive completion | `FBInputCommands.m` → `FBScreen.m` → `FBXCTestDaemonsProxy.m` |
| Valid raw keyboard mutation | Exact text/clear schema and bounded schedule | One text-input path against current keyboard focus; no field discovery or result claim | `FBInputCommands.m` → `FBXCTestDaemonsProxy.m` |
| Valid raw geometry | Main display selected and finite positive portrait context | Exact logical `{width,height,scale}` without app/AX reads | `FBInputCommands.m` → `FBScreen.m` |
| Valid raw bundle-state query | Exact admitted caller-supplied bundle ID | One `.state` read and explicit nonexclusive foreground Boolean; no mutation/tracker | `FBSessionCommands.m` |
| Admitted raw dictionary refusal | After raw-envelope admission, a closed-schema/field-type/finite/range/path/context/bundle rule fails | W3C `invalid argument`; zero event submissions and zero app-state reads where validation fails | raw handlers plus `FBScreen.m` |
| Synthesizer completion failure | Completion error or Boolean `NO` | W3C `unknown error`; no retry | bounded proxy and shared response mapper |
| Synthesizer timeout | No completion within `maximumOffset + 2s` | HTTP 408 W3C `timeout`; delivery uncertain; no retry; own queue wait released | bounded proxy and shared response mapper |
| Earlier AX work owns main route queue | Any raw request arrives behind it | Raw request stays queued; no bypass/coalescing claim; recovery is fresh WDA plus no AX producer | ordinary raw registrations; unchanged main-route-queue ownership in `FBWebServer.m` |
| Visible surface/focus differs from caller assumption | Foreground, keyboard focus, or pose changes after request validation | Captured portrait event still targets main display/current keyboard focus; no ownership/result guarantee | L2, L3, L7, L10 |
| Existing route or unsupported platform | Path is not the exact raw family, or target is tvOS/watchOS | Existing behavior remains; raw routes/tokens are absent on unsupported targets | existing command owners and compile guards |

### Shared-invariant writer/reader census

| invariant | every writer/owner | every reader/consumer | disposition |
| --- | --- | --- | --- |
| Request-local close decision | lowercase header parser combines `Connection`; `FBPendingHTTPRequestHeader` writes parsed bit; ordinary dispatch closure and each `FBPendingRequest` copy it | invalid-session, abandonment, normal, not-found, standalone leader/joiner writers; `writeResponse` header/close branch; Titan session/proxy/loopback readers wait for EOF | Every response uses its own bit; keep-alive remains default. |
| Raw body-envelope classification | `FBHTTPServer.m` writes the exact zero-length or declared body bytes into `RouteRequest`; `FBWebServer.m` alone classifies a matched raw route's body as zero-length, parsed dictionary, parse failure, or non-dictionary root | all eight raw input/geometry handlers in `FBInputCommands.m` and the raw app-state handler in `FBSessionCommands.m` consume only `{}` or the admitted dictionary; the adapter consumes the two refusal classes before mounting; every non-raw handler remains a reader of the legacy fallback | Empty body and `{}` remain distinguishable from malformed/non-object input for all nine raw routes; strict admission is not global and refusal has no raw command side effect. |
| Raw main geometry/display | `FBSettingsHandler.m` sets/clears `currentDisplayId`; `FBConfiguration.m` resets it; XCTest owns `XCUIScreen.mainScreen` bounds/scale/ID; new `FBScreen` method captures/derives context | raw screen plus tap/swipe/long-press/scroll/Bezier validators and record constructors; later agent/BE percentage tools | One derivation owner; explicit non-main refusal; existing selected-display readers unchanged. |
| Raw event schedule | route validators/builders write tap/swipe/hold/scroll/Bezier/type/delete offsets; `XCSynthesizedEventRecord.maximumOffset` aggregates them | bounded proxy validates deadline; response mapper distinguishes success/failure/timeout | Every schedule is finite and at most 10 seconds before the single submission. |
| Current keyboard focus | iOS/app/user interaction writes focus; WDA does not select it in raw mode | raw delayed-type and clear-field text paths deliver to it | No app/field/keyboard read; caller establishes and visibly verifies focus/content. |
| Per-bundle app state | caller writes exact bundle ID; XCTest process state owns `.state` | raw state serializer and later agent/BE admission/verification | One named-bundle read; no active-app discovery or exclusivity claim. |
| Raw capability set | `FBCustomEndpointTokens.m` writes nine tokens; `FBSessionCommands.m` publishes the list in `/status` | future agent capability check and backend rollout admission | Full set required; WDA provides no fallback. |
| Input dispatch order | raw route declarations choose ordinary dispatch; `FBWebServer.m` assigns main queue; `FBHTTPServer.m` owns standalone machinery | all raw callers and earlier AX-producing requests | Raw calls serialize and cannot overtake stuck AX; body-blind coalescing is never used. |
| Foreground tracking | existing tracker activation sites and existing active-app/foreground endpoints remain the only writers/readers | raw routes consume none; raw state directly reads only named `.state` | No raw route initializes, reads, updates, or relies on tracker state. |

## Proof: State Table

| reachable state / event class | next observable state |
| --- | --- |
| Complete request parsed without close token | Existing dispatch; response leaves the connection available for its next request. |
| Complete request parsed with close token | Request-local bit follows the response; subsequent bytes are dropped; complete response writes before socket closure. |
| Valid raw mutation before context/schedule validation | No event exists; it either reaches one admitted immutable record or refuses with no submission. |
| Admitted record before submission | One route owns one record/path; no application/AX/foreground state was read for input. |
| Completion `YES`, nil error | Raw mutation returns the success envelope; visible result remains caller-verified. |
| Completion `NO` or error | Failure response; no second submission. |
| Wait expires | Timeout states uncertainty; no second submission; late completion cannot change the response. |
| Valid named-bundle query | One state sample returns with nonexclusive semantics and no tracker activation. |
| Earlier AX work owns main queue | Raw work remains queued until that work returns or WDA restarts. |
| Legacy route | Existing handler/state machine remains authoritative. |

## Proof: Linearization

A raw physical mutation linearizes at the single `eventSynthesizer synthesizeEvent:` submission's physical handling, not at HTTP receipt, validation, or response serialization. Completion establishes only XCTest's Boolean/error result. Timeout does not establish non-delivery. Keyboard focus and visible target are the OS state at physical handling.

The close decision linearizes when the complete request header is parsed and remains attached to that client request through response races. Socket closure occurs only after Network.framework finishes that response write. Raw coordinate geometry linearizes at the one captured main screen/current-display-selection context. Bundle state linearizes at the sole `.state` property read.

## Proof: Interruption Matrix

| interruption point | determined outcome |
| --- | --- |
| Before raw submission | No physical input; corrected input may be sent as a new request. |
| During synthesizer wait | Input may or may not have occurred; failure/timeout is uncertain and WDA does not retry. |
| After physical delivery but before HTTP response | Transport failure may hide delivery; WDA has no deduplication and does not replay. |
| After state validation but before `.state` read | No mutation; request may fail or be retried as a fresh observation. |
| During a close-marked response write | No later request on that client dispatches; connection closes from write completion. |
| WDA dies with raw work queued behind AX | Queued input did not begin unless it reached its sole submission; fresh WDA is the recovery boundary. |
| Surface/focus changes after capture | Event keeps captured portrait coordinates/schedule and current text focus at delivery; no retarget or rollback. |

## Proof: Supersession

No raw request supersedes, cancels, coalesces, or deduplicates another. Ordinary route order decides which admitted request submits first. A later request, display setting, focus, foreground, rotation, TCP disconnect, or caller timeout does not authorize replay or cancellation of an already submitted event. Restarting WDA drops queued work but cannot undo delivered physical input.

This task fully supersedes `tasks/2026-10-13-wda-accessibility-free-coordinate-input.md`. Its route migrations, file authority, acceptance items, and test deletions have no effect. The later Group B decision also supersedes the narrower three-route interpretation: long press, scroll, Bezier, delayed typing, clear-field, and named-bundle state are required in this same unit.

## Proof: Red Tests

The operator suspended the test mandate on 2026-08-14 and banned test/fixture changes on 2026-09-24. No red test, test edit, fixture, snapshot, coverage target, or replacement test is authorized. AC-01 through AC-12 are real-stack TESTBED observations; this section adds no test-file implementation obligation.

## Acceptance

- **AC-01:** With the unchanged Titan agent connected to this WDA on the home screen, each `Connection: close` bootstrap/session response is complete and followed by EOF, and the device reaches Ready rather than repeating the ten-second bootstrap timeout.
- **AC-02:** A client without a close token retains ordered keep-alive across sequential requests. Mixed-case/comma-list/duplicate-field close requests, including close-marked invalid-session, not-found, abandonment, and standalone responses, close only after their own complete response and never execute pipelined followers.
- **AC-03:** From a fresh WDA on a portrait TikTok video with no AX producer, raw tap opens the comment sheet and raw swipe advances to the next video; each returns within its bounded deadline, a fresh screenshot proves the visible effect, and the next `/status` succeeds.
- **AC-04:** Under the same operating condition, raw long-press produces the expected visible hold action, raw `down` scroll advances content with the specified direction semantics, and both legacy and held raw Bezier shapes follow their requested path/timing; each leaves `/status` responsive.
- **AC-05:** Raw screen returns positive portrait logical `width`/`height` and positive `scale` from the main display without resolving an app. Coordinates derived from it land at the expected portrait point, while a selected non-main display is refused before submission.
- **AC-06:** With a caller-focused text field, raw delayed typing enters the supplied grapheme sequence in order with the requested inter-key schedule, and raw clear with a count at least as large as the focused value removes it. Neither route resolves an app/field/keyboard, and a fresh screenshot—not HTTP success alone—confirms the content.
- **AC-07:** Raw app state returns the sampled XCTest state and matching Boolean for a caller-supplied bundle through foreground/background transitions without reading active-app info or initializing `FBForegroundTracker`; its result is not treated as exclusive visible-surface proof.
- **AC-08:** `/status` advertises all nine exact raw tokens, and unsupported tvOS/watchOS builds advertise/register none of them. WDA performs no accessibility fallback when any raw route fails or is unavailable.
- **AC-09:** Unknown/missing fields, wrong JSON types, Booleans/non-finite/out-of-bounds points, inadmissible durations/path shapes/text schedules/delete counts/bundle IDs, invalid portrait geometry, and non-main selection are rejected before physical submission or state lookup, and `/status` remains responsive.
- **AC-10:** A synthesizer Boolean failure or callback error is never reported as success. Timeout returns HTTP 408 with uncertain-delivery wording, releases its own wait, and produces no cancellation/retry/second event even if completion arrives later.
- **AC-11:** Two concurrent raw requests with different bodies execute serially as distinct operations. A raw request behind an already-stuck AX request neither bypasses nor coalesces with it; restarting WDA and avoiding AX producers restores the supported raw path.
- **AC-12:** Existing accessibility tap, drag/swipe, long-press, direction-scroll, Bezier/held swipe, window/screen geometry, delayed typing, both clear-field routes, active-app/foreground checks, named app state, element/alert/source, Settings/Wi-Fi/Photos, keyboard, and all Group A/Group C routes retain their current wire results and authority; a Settings element tap behaves as on WDA 16.2.2.

## Verification Commands

Do not run repository tests. After implementation, the builder runs only the unsigned compile and hygiene commands below. The `xcodebuild` command is the builder gate and must exit 0; its derived data and redirected log stay in the dispatch-provided scratch directory.

```bash
# From this WebDriverAgent checkout
xcodebuild \
  -project WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -configuration Debug \
  -destination generic/platform=iOS \
  -derivedDataPath "$TMPDIR/wda-dd" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  build-for-testing \
  >"$TMPDIR/wda-xcodebuild.log" 2>&1

git diff --check
git diff -- WebDriverAgentLib/Routing/FBHTTPServer.m \
  WebDriverAgentLib/Routing/FBWebServer.m \
  WebDriverAgentLib/Utilities/FBScreen.h \
  WebDriverAgentLib/Utilities/FBScreen.m \
  WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.h \
  WebDriverAgentLib/Utilities/FBXCTestDaemonsProxy.m \
  WebDriverAgentLib/Commands/FBInputCommands.m \
  WebDriverAgentLib/Commands/FBSessionCommands.m \
  WebDriverAgentLib/Commands/FBCustomEndpointTokens.m \
  docs/multiple-displays.md package.json
```

The conductor/testbed verifies AC-01 through AC-12 on device 7 using fresh WDA instances for independent AX-blocking controls. Physical-input success requires visible screenshot evidence plus a healthy subsequent `/status`; HTTP 200 alone is insufficient.

## Builder/Reviewer Handoff

- Resume the same held builder; its stopped attempt made no source, documentation, manifest, task, or test edit. The builder runs the exact unsigned `xcodebuild` gate above from this checkout, requires exit 0, keeps derived data and the redirected log under `$TMPDIR`, and also runs `git diff --check`.
- `bash wda/scripts/build-wda-ipa.sh` is not a builder step. The conductor owns that signed IPA build after independent review, outside builder-lane containment, before device-7 TESTBED qualification.
- `WebDriverAgent/.githooks/pre-push` does not exist, so no hook command applies. The reviewer treats the absence of a builder-produced signed IPA as the required custody boundary and reviews the candidate against the unchanged contract, locks, case table, and acceptance.

## Non-Goals

- No agent, backend, frontend, strategy 88, tool registry, operation catalog, allowlist, app-state consumer, preset/tool-set version, or rollout database edit.
- No agent `Content-Length` reader, session-start/attachment/press-home foreground repair, raw-route allowlist, capability enforcement, or consumer retry policy.
- No immutable R2 publication, device assignment, local install, version negotiation, or device-7 rollout action.
- No raw twin for Group A or Group C, and no landscape, secondary-display, multi-finger, pressure, element-relative, percentage, alert, source, Settings, Wi-Fi, or Photos raw route.
- No active-foreground discovery, exclusive-ownership claim, cancellation, automatic retry, deduplication, idempotency key, UI-settled check, screenshot verification, or physical-delivery receipt inside WDA.
- No route-queue redesign, `.standalone` raw dispatch, foreground-tracker edit, or existing accessibility-producer edit.
- No test/fixture changes and no test execution.

## Adversarial Review

- Reject any diff that changes an existing route registration/body/response, edits/deletes a test, migrates a legacy handler, or carries forward any authority from the superseded task.
- Trace the shared JSON adapter before any raw handler: zero body must become `{}`, nonempty `{}` must remain valid, and every malformed or non-dictionary JSON root must return W3C `invalid argument` without mounting. Reject a global strictness change, a sentinel inserted into route arguments, a fragment coerced to `{}`, or any changed parse/fallback behavior for a non-raw route.
- Account for all nine Group B raw tokens and exact routes. Trace every raw mutation transitively; reject any reachability to a session, active application, element/window/status bar, AX client/snapshot, W3C action synthesizer, quiescence wait, sleep-based scheduler, or foreground tracker. The sole exception is raw app state constructing the caller-named `XCUIApplication` and reading `.state` once.
- Trace `Connection: close` through normal, invalid-session, abandonment, not-found, standalone-leader, and standalone-joiner responses. Reject a global/sticky flag, close before complete write, lost bit, post-close buffered dispatch, shared response-header mutation, or changed no-close behavior.
- Confirm raw routes are ordinary rather than `.standalone`; geometry has one capture/owner and rejects selected secondary display; pointer initializers target that main display with the stated runtime fallback; keyboard routes make no focus/content claim.
- Confirm the bounded overload is used by every raw physical mutation and no existing caller; completion `NO` is failure; record offsets and wait are bounded; timeout says uncertain; and no error/timeout path submits twice.
- Confirm the version edit, if required, is version-only; documentation states the complete Group B family and fresh-WDA/no-AX operating condition; agent/BE/rollout work remains follow-up only.

Builder notes retained from the contract precheck; these are determined applications of the family rules above, not extra case-table rows:

- If a caller selects a secondary display and then sends raw delayed typing or raw clear-field, the keyboard route does not consult or reject that display selection; its sole text-input path targets the system's current keyboard focus. The portrait/main-display context gates geometry and coordinate input only.
- If a raw mutation times out, releases the shared route queue, and its callback arrives after a later raw request begins, that late callback cannot change the timed-out HTTP result or cause a retry. The first event's physical delivery remains uncertain, so HTTP response order does not prove physical-effect order.
- If a close-marked standalone request joins an in-flight standalone execution also joined by a keep-alive request from another client, execution may be shared but connection lifetime remains per request/client: only the close-marked response receives one `Connection: close` and EOF after its complete write; the keep-alive client retains existing behavior.
