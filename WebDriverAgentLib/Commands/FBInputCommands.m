/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBInputCommands.h"
#import "FBBezierInterpolator.h"
#import "FBCommandStatus.h"
#import "FBHTTPStatusCodes.h"
#import "FBLogger.h"
#import "FBResponseJSONPayload.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "XCUIApplication.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIApplication+FBTouchAction.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"
static NSInteger TTInputMs(NSDate *s) { return (NSInteger)([[NSDate date] timeIntervalSinceDate:s] * 1000); }
static const NSTimeInterval TTClearHoldBase = 2.5;  // floor hold; clears short fields (proven: 2.5s cleared 7 chars)
static const NSTimeInterval TTClearHoldPerChar = 0.03; // linear add per estimated char (conservative vs accel-delete)
static const NSTimeInterval TTClearHoldMax = 8.0;   // cap — stays well under the 15s WDA HTTP timeout
static const NSTimeInterval TTClearHoldBlind = 5.5; // hold when no length estimate is supplied
static NSString *TTElementDebugName(XCUIElement *element);
static BOOL TTElementIsInsideKeyboard(XCUIElement *element, CGRect keyboardFrame);
static XCUIElement *TTFirstExistingElement(XCUIElementQuery *query, NSTimeInterval timeout);
static XCUIElement *TTFindDeleteKeyByAX(XCUIApplication *app, XCUIElement *keyboard, NSString **strategy);
static BOOL TTPressKeyboardDeleteCoordinateFallback(XCUIElement *keyboard, NSTimeInterval hold, NSString **strategy);

static NSString *TTElementDebugName(XCUIElement *element)
{
  NSString *identifier = element.identifier;
  NSString *label = element.label;
  id value = element.value;
  return [NSString stringWithFormat:@"identifier=%@ label=%@ value=%@ frame=%@ hittable=%@",
          identifier.length ? identifier : @"(none)",
          label.length ? label : @"(none)",
          nil != value ? value : @"(none)",
          NSStringFromCGRect(element.frame),
          element.hittable ? @"YES" : @"NO"];
}

static BOOL TTElementIsInsideKeyboard(XCUIElement *element, CGRect keyboardFrame)
{
  if (CGRectIsNull(keyboardFrame) || CGRectIsEmpty(keyboardFrame)) {
    return YES;
  }
  CGRect elementFrame = element.frame;
  if (CGRectIsNull(elementFrame) || CGRectIsEmpty(elementFrame)) {
    return NO;
  }
  return CGRectContainsRect(CGRectInset(keyboardFrame, -1.0, -1.0), elementFrame)
    || CGRectIntersectsRect(keyboardFrame, elementFrame);
}

static XCUIElement *TTFirstExistingElement(XCUIElementQuery *query, NSTimeInterval timeout)
{
  XCUIElement *element = [query firstMatch];
  return [element waitForExistenceWithTimeout:timeout] ? element : nil;
}

static XCUIElement *TTFirstDeleteCandidate(XCUIElementQuery *query, CGRect keyboardFrame)
{
  (void)TTFirstExistingElement(query, 0.1);
  XCUIElement *fallback = nil;
  for (XCUIElement *candidate in query.allElementsBoundByIndex) {
    if (![candidate exists] || !TTElementIsInsideKeyboard(candidate, keyboardFrame)) {
      continue;
    }
    if (candidate.hittable) {
      return candidate;
    }
    if (nil == fallback) {
      fallback = candidate;
    }
  }
  return fallback;
}

static XCUIElement *TTFindDeleteKeyByAX(XCUIApplication *app, XCUIElement *keyboard, NSString **strategy)
{
  CGRect keyboardFrame = keyboard.frame;
  XCUIElement *exact = app.keys[@"delete"];
  if ([exact waitForExistenceWithTimeout:1.0] && TTElementIsInsideKeyboard(exact, keyboardFrame)) {
    if (nil != strategy) {
      *strategy = @"ax-exact";
    }
    FBLogVerbose(@"keyboard.clear-field-no-a11y ax candidate strategy=ax-exact %@", TTElementDebugName(exact));
    return exact;
  }

  NSPredicate *deletePredicate = [NSPredicate predicateWithFormat:@"identifier CONTAINS[c] %@ OR label CONTAINS[c] %@ OR name CONTAINS[c] %@ OR identifier CONTAINS[c] %@ OR label CONTAINS[c] %@ OR name CONTAINS[c] %@", @"delete", @"delete", @"delete", @"backspace", @"backspace", @"backspace"];
  XCUIElement *keyCandidate = TTFirstDeleteCandidate([app.keys matchingPredicate:deletePredicate], keyboardFrame);
  if (nil != keyCandidate) {
    if (nil != strategy) {
      *strategy = @"ax-key-predicate";
    }
    FBLogVerbose(@"keyboard.clear-field-no-a11y ax candidate strategy=ax-key-predicate %@", TTElementDebugName(keyCandidate));
    return keyCandidate;
  }

  XCUIElement *buttonCandidate = TTFirstDeleteCandidate([app.buttons matchingPredicate:deletePredicate], keyboardFrame);
  if (nil != buttonCandidate) {
    if (nil != strategy) {
      *strategy = @"ax-button-predicate";
    }
    FBLogVerbose(@"keyboard.clear-field-no-a11y ax candidate strategy=ax-button-predicate %@", TTElementDebugName(buttonCandidate));
    return buttonCandidate;
  }

  return nil;
}

static BOOL TTPressKeyboardDeleteCoordinateFallback(XCUIElement *keyboard, NSTimeInterval hold, NSString **strategy)
{
  if (CGRectIsNull(keyboard.frame) || CGRectIsEmpty(keyboard.frame)) {
    return NO;
  }
  NSArray<NSValue *> *offsets = @[
    [NSValue valueWithCGVector:CGVectorMake(0.92, 0.58)],
    [NSValue valueWithCGVector:CGVectorMake(0.92, 0.46)],
    [NSValue valueWithCGVector:CGVectorMake(0.92, 0.30)],
  ];
  NSException *lastException = nil;
  for (NSValue *offset in offsets) {
    CGVector vector = offset.CGVectorValue;
    @try {
      XCUICoordinate *coordinate = [keyboard coordinateWithNormalizedOffset:vector];
      [coordinate pressForDuration:hold];
      if (nil != strategy) {
        *strategy = [NSString stringWithFormat:@"coordinate-fallback:%.2f,%.2f", vector.dx, vector.dy];
      }
      return YES;
    } @catch (NSException *e) {
      lastException = e;
      FBLogWarn(@"keyboard.clear-field-no-a11y coordinate fallback threw x=%.2f y=%.2f reason=%@", vector.dx, vector.dy, e.reason);
    }
  }
  if (nil != lastException) {
    @throw lastException;
  }
  return NO;
}

@implementation FBInputCommands
+ (NSArray *)routes
{
  return @[
    /** HTTP verb: POST; path: /wda/keyboard/type-with-delay; request schema: {text:string,charDelayMs:number}; response schema: {ok,charCount,charDelayMs,durationMs}; error codes: 400/500; capability token: keyboard.type-with-delay */
    [[FBRoute POST:@"/wda/keyboard/type-with-delay"].withoutSession respondWithTarget:self action:@selector(handleTypeWithDelay:)],
    /** HTTP verb: POST; path: /wda/touch/swipe-bezier; request schema: {from:{x,y},to:{x,y},controlPoints:[{x,y}],durationMs:number}; response schema: {ok,steps,controlPointCount,durationMs}; error codes: 400/500; capability token: touch.swipe-bezier */
    [[FBRoute POST:@"/wda/touch/swipe-bezier"].withoutSession respondWithTarget:self action:@selector(handleSwipeBezier:)],
    /** HTTP verb: POST; path: /wda/keyboard/clear-field; request schema: none; response schema: {ok,durationMs}; error codes: 404/500; capability token: keyboard.clear-field */
    [[FBRoute POST:@"/wda/keyboard/clear-field"].withoutSession respondWithTarget:self action:@selector(handleClearField:)],
    /** HTTP verb: POST; path: /wda/keyboard/clear-field-no-a11y; request schema: {approxChars?:number}; response schema: {ok,holdSeconds,durationMs}; error codes: 404/500; capability token: keyboard.clear-field-no-a11y */
    [[FBRoute POST:@"/wda/keyboard/clear-field-no-a11y"].withoutSession respondWithTarget:self action:@selector(handleClearFieldNoA11y:)],
  ];
}
+ (id<FBResponsePayload>)handleTypeWithDelay:(FBRouteRequest *)request
{
  NSString *text = request.arguments[@"text"]; NSNumber *delayNum = request.arguments[@"charDelayMs"]; if (nil == text || nil == delayNum) return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"text and charDelayMs are required" traceback:nil]); NSTimeInterval delay = MIN(MAX(delayNum.doubleValue / 1000.0, 0), 5.0); NSDate *s = [NSDate date]; XCUIElement *target = [XCUIApplication.fb_activeApplication.windows firstMatch]; NSUInteger charCount = text.length;
  for (NSUInteger i = 0; i < charCount; i++) { @try { [target typeKey:[text substringWithRange:NSMakeRange(i, 1)] modifierFlags:0]; } @catch (NSException *e) { FBLogWarn(@"keyboard.type-with-delay failed index=%lu charCount=%lu reason=%@", (unsigned long)i, (unsigned long)charCount, e.reason); return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"typeKey_threw", @"failedAtIndex": @(i), @"durationMs": @(TTInputMs(s))} httpStatusCode:kHTTPStatusCodeInternalServerError]; } if (i + 1 < charCount && delay > 0) [NSThread sleepForTimeInterval:delay]; }
  FBLogVerbose(@"keyboard.type-with-delay charCount=%lu charDelayMs=%@ durationMs=%ld", (unsigned long)charCount, delayNum, (long)TTInputMs(s)); return FBResponseWithObject(@{@"ok": @YES, @"charCount": @(charCount), @"charDelayMs": delayNum, @"durationMs": @(TTInputMs(s))});
}
+ (id<FBResponsePayload>)handleSwipeBezier:(FBRouteRequest *)request
{
  NSDictionary *from = request.arguments[@"from"];
  NSDictionary *to = request.arguments[@"to"];
  NSNumber *dur = request.arguments[@"durationMs"];
  if (!from || !to || !dur) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"from, to, and durationMs are required" traceback:nil]);
  }

  NSDate *startedAt = [NSDate date];
  CGFloat ms = MIN(MAX(dur.doubleValue, 100), 10000);
  NSUInteger steps = MAX(10u, (NSUInteger)(ms / 1000.0 * 60.0));

  NSArray *rawCps = request.arguments[@"controlPoints"] ?: @[];
  if (rawCps.count > 10) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"controlPoints exceeds 10" traceback:nil]);
  }
  NSMutableArray *cps = [NSMutableArray array];
  for (NSDictionary *cp in rawCps) {
    [cps addObject:[NSValue valueWithCGPoint:CGPointMake([cp[@"x"] doubleValue], [cp[@"y"] doubleValue])]];
  }

  CGPoint fromPoint = CGPointMake([from[@"x"] doubleValue], [from[@"y"] doubleValue]);
  CGPoint toPoint = CGPointMake([to[@"x"] doubleValue], [to[@"y"] doubleValue]);
  NSArray<NSValue *> *path = [FBBezierInterpolator pointsAlongCurveFrom:fromPoint to:toPoint
                                                          controlPoints:cps steps:steps];
  // path has (steps + 1) waypoints; first is `from`, last is `to`.
  if (path.count < 2) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"insufficient path points" traceback:nil]);
  }

  // Per-move duration. We distribute the full `ms` across (path.count - 1) moves,
  // since the initial pointerMove-to-start uses duration=0 and the pointerDown +
  // pointerUp do not consume animation time.
  CGFloat perMoveMs = ms / (CGFloat)(path.count - 1);

  // Build W3C actions array. Field names match FBW3CActionsSynthesizer constants
  // (FB_KEY_TYPE, FB_ACTION_ITEM_TYPE_POINTER_*, FB_ACTION_ITEM_KEY_*, etc.).
  NSMutableArray *actionItems = [NSMutableArray array];

  // (a) Move pointer to start position. duration=0 = instant (no animation).
  CGPoint startPoint = [path[0] CGPointValue];
  [actionItems addObject:@{
    @"type": @"pointerMove",
    @"x": @(startPoint.x),
    @"y": @(startPoint.y),
    @"origin": @"viewport",
    @"duration": @(0),
  }];

  // (b) Begin contact. button=0 = primary touch.
  [actionItems addObject:@{
    @"type": @"pointerDown",
    @"button": @(0),
  }];

  // (c) Drag through every waypoint after the first. Each move has duration=perMoveMs.
  for (NSUInteger i = 1; i < path.count; i++) {
    CGPoint p = [path[i] CGPointValue];
    [actionItems addObject:@{
      @"type": @"pointerMove",
      @"x": @(p.x),
      @"y": @(p.y),
      @"origin": @"viewport",
      @"duration": @(perMoveMs),
    }];
  }

  // (d) End contact.
  [actionItems addObject:@{
    @"type": @"pointerUp",
    @"button": @(0),
  }];

  NSArray *w3cActions = @[
    @{
      @"type": @"pointer",
      @"id": @"swipe-bezier",
      @"parameters": @{@"pointerType": @"touch"},
      @"actions": actionItems,
    }
  ];

  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  NSError *synthError = nil;
  BOOL ok = [app fb_performW3CActions:w3cActions elementCache:nil error:&synthError];
  NSInteger durationMs = TTInputMs(startedAt);

  if (!ok) {
    FBLogWarn(@"touch.swipe-bezier synth_failed reason=%@", synthError.localizedDescription);
    return [[FBResponseJSONPayload alloc]
            initWithDictionary:@{@"error": @"gesture_failed",
                                 @"message": synthError.localizedDescription ?: @"unknown",
                                 @"durationMs": @(durationMs)}
            httpStatusCode:kHTTPStatusCodeInternalServerError];
  }

  FBLogVerbose(@"touch.swipe-bezier steps=%lu cps=%lu durationMs=%ld",
               (unsigned long)steps, (unsigned long)cps.count, (long)durationMs);
  return FBResponseWithObject(@{@"ok": @YES,
                                @"steps": @(steps),
                                @"controlPointCount": @(cps.count),
                                @"durationMs": @(durationMs)});
}
+ (id<FBResponsePayload>)handleClearField:(FBRouteRequest *)request
{
  NSDate *s = [NSDate date]; XCUIApplication *app = XCUIApplication.fb_activeApplication; XCUIElement *field = [[app.textFields firstMatch] exists] ? [app.textFields firstMatch] : ([[app.textViews firstMatch] exists] ? [app.textViews firstMatch] : [app.secureTextFields firstMatch]); if (![field exists]) return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"no_focused_field", @"durationMs": @(TTInputMs(s))} httpStatusCode:kHTTPStatusCodeNotFound]; [field pressForDuration:1.0]; [NSThread sleepForTimeInterval:0.4]; XCUIElement *selectAll = [[app.menuItems matchingPredicate:[NSPredicate predicateWithFormat:@"label IN {'Select All', 'select all'}"]] firstMatch]; if ([selectAll exists]) [selectAll tap]; else [field typeKey:@"a" modifierFlags:XCUIKeyModifierCommand]; [NSThread sleepForTimeInterval:0.2]; [field typeKey:XCUIKeyboardKeyDelete modifierFlags:0]; FBLogVerbose(@"keyboard.clear-field durationMs=%ld", (long)TTInputMs(s)); return FBResponseWithObject(@{@"ok": @YES, @"durationMs": @(TTInputMs(s))});
}
+ (id<FBResponsePayload>)handleClearFieldNoA11y:(FBRouteRequest *)request
{
  // Press-and-hold the on-screen keyboard delete control for the already-focused
  // field. TikTok Bio can hide the key from exact AX lookup, so keep AX first and
  // fall back to keyboard-relative coordinates instead of window typeKey.
  NSDate *s = [NSDate date];
  NSNumber *approx = request.arguments[@"approxChars"];
  NSTimeInterval hold = approx
    ? MIN(MAX(TTClearHoldBase + approx.doubleValue * TTClearHoldPerChar, TTClearHoldBase), TTClearHoldMax)
    : TTClearHoldBlind;
  XCUIElement *keyboard = [XCUIApplication.fb_activeApplication.keyboards firstMatch];
  if (![keyboard exists]) {
    FBLogWarn(@"keyboard.clear-field-no-a11y no keyboard on screen");
    return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"no_keyboard", @"durationMs": @(TTInputMs(s))} httpStatusCode:kHTTPStatusCodeNotFound];
  }
  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  NSString *strategy = nil;
  XCUIElement *deleteKey = TTFindDeleteKeyByAX(app, keyboard, &strategy);
  @try {
    if (nil != deleteKey) {
      [deleteKey pressForDuration:hold];
    } else if (!TTPressKeyboardDeleteCoordinateFallback(keyboard, hold, &strategy)) {
      FBLogWarn(@"keyboard.clear-field-no-a11y delete key not found after AX and coordinate fallback keyboardFrame=%@", NSStringFromCGRect(keyboard.frame));
      return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"no_delete_key", @"durationMs": @(TTInputMs(s))} httpStatusCode:kHTTPStatusCodeNotFound];
    }
  } @catch (NSException *e) {
    FBLogWarn(@"keyboard.clear-field-no-a11y press failed strategy=%@ hold=%.2f reason=%@", strategy ?: @"(none)", hold, e.reason);
    return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"press_threw", @"durationMs": @(TTInputMs(s))} httpStatusCode:kHTTPStatusCodeInternalServerError];
  }
  FBLogVerbose(@"keyboard.clear-field-no-a11y strategy=%@ holdSeconds=%.2f approxChars=%@ durationMs=%ld", strategy ?: @"(none)", hold, approx ?: @"(blind)", (long)TTInputMs(s));
  return FBResponseWithObject(@{@"ok": @YES, @"holdSeconds": @(hold), @"durationMs": @(TTInputMs(s))});
}
@end
