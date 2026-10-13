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
#import "FBScreen.h"
#import "FBXCTestDaemonsProxy.h"
#import "XCPointerEventPath.h"
#import "XCUIApplication.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIApplication+FBTouchAction.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
static NSInteger TTInputMs(NSDate *s) { return (NSInteger)([[NSDate date] timeIntervalSinceDate:s] * 1000); }
static const NSTimeInterval TTClearHoldBase = 2.5;  // floor hold; clears short fields (proven: 2.5s cleared 7 chars)
static const NSTimeInterval TTClearHoldPerChar = 0.03; // linear add per estimated char (conservative vs accel-delete)
static const NSTimeInterval TTClearHoldMax = 8.0;   // cap — stays well under the 15s WDA HTTP timeout
static const NSTimeInterval TTClearHoldBlind = 5.5; // hold when no length estimate is supplied
typedef struct {
  CGPoint from;
  CGPoint to;
  NSUInteger startHoldMs;
  NSUInteger moveDurationMs;
  NSUInteger moveSteps;
  NSUInteger endHoldMs;
} TTHeldSwipeRequest;

static NSString *TTElementDebugName(XCUIElement *element);
static BOOL TTElementIsInsideKeyboard(XCUIElement *element, CGRect keyboardFrame);
static XCUIElement *TTFirstExistingElement(XCUIElementQuery *query, NSTimeInterval timeout);
static BOOL TTKeyboardIndicatorsExist(XCUIApplication *app);
static XCUIElement *TTFindDeleteKeyByAX(XCUIApplication *app, XCUIElement *keyboard, NSString **strategy);
static BOOL TTPressKeyboardDeleteCoordinateFallback(XCUIElement *keyboard, NSTimeInterval hold, NSString **strategy);
static BOOL TTPressThirdPartyDeleteCoordinateFallback(XCUIApplication *app, NSTimeInterval hold, NSString **strategy, NSString **failureReason);
static BOOL TTDictionaryHasExactKeys(NSDictionary *dictionary, NSSet *expectedKeys);
static BOOL TTParseFiniteJSONDouble(id value, double *output);
static BOOL TTParseExactNonnegativeInteger(id value, NSUInteger *output);
static BOOL TTParseHeldSwipeRequest(NSDictionary *arguments, TTHeldSwipeRequest *output, XCUIApplication **application);

static BOOL TTDictionaryHasExactKeys(NSDictionary *dictionary, NSSet *expectedKeys)
{
  return nil != dictionary
    && dictionary.count == expectedKeys.count
    && [[NSSet setWithArray:dictionary.allKeys] isEqualToSet:expectedKeys];
}

static BOOL TTIsJSONNumber(id value)
{
  return [value isKindOfClass:[NSNumber class]]
    && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID();
}

static BOOL TTParseFiniteJSONDouble(id value, double *output)
{
  if (!TTIsJSONNumber(value)) {
    return NO;
  }
  double parsed = [value doubleValue];
  if (!isfinite(parsed)) {
    return NO;
  }
  if (nil != output) {
    *output = parsed;
  }
  return YES;
}

static BOOL TTParseExactNonnegativeInteger(id value, NSUInteger *output)
{
  double parsed = 0;
  if (!TTParseFiniteJSONDouble(value, &parsed)
      || parsed < 0
      || floor(parsed) != parsed
      || parsed > 9007199254740991.0) {
    return NO;
  }
  NSUInteger integerValue = (NSUInteger)parsed;
  if ((double)integerValue != parsed) {
    return NO;
  }
  if (nil != output) {
    *output = integerValue;
  }
  return YES;
}

static BOOL TTFiniteViewportFrame(CGRect frame)
{
  return !CGRectIsNull(frame)
    && !CGRectIsEmpty(frame)
    && isfinite(CGRectGetMinX(frame))
    && isfinite(CGRectGetMinY(frame))
    && isfinite(CGRectGetMaxX(frame))
    && isfinite(CGRectGetMaxY(frame));
}

static BOOL TTPointIsInsideViewport(double x, double y, CGRect frame)
{
  return x >= CGRectGetMinX(frame)
    && x <= CGRectGetMaxX(frame)
    && y >= CGRectGetMinY(frame)
    && y <= CGRectGetMaxY(frame);
}

static BOOL TTParseHeldSwipeRequest(NSDictionary *arguments, TTHeldSwipeRequest *output, XCUIApplication **application)
{
  NSSet *topLevelKeys = [NSSet setWithObjects:@"from", @"to", @"controlPoints", @"durationMs", @"held", nil];
  if (!TTDictionaryHasExactKeys(arguments, topLevelKeys)) {
    return NO;
  }

  NSDictionary *from = arguments[@"from"];
  NSDictionary *to = arguments[@"to"];
  NSDictionary *held = arguments[@"held"];
  if (![from isKindOfClass:[NSDictionary class]]
      || ![to isKindOfClass:[NSDictionary class]]
      || ![held isKindOfClass:[NSDictionary class]]
      || !TTDictionaryHasExactKeys(from, [NSSet setWithObjects:@"x", @"y", nil])
      || !TTDictionaryHasExactKeys(to, [NSSet setWithObjects:@"x", @"y", nil])
      || !TTDictionaryHasExactKeys(held, [NSSet setWithObjects:@"mode", @"startHoldMs", @"moveSteps", @"endHoldMs", nil])
      || ![arguments[@"controlPoints"] isKindOfClass:[NSArray class]]
      || [arguments[@"controlPoints"] count] != 0
      || ![held[@"mode"] isKindOfClass:[NSString class]]
      || ![held[@"mode"] isEqualToString:@"continuous_drag_v1"]) {
    return NO;
  }

  double fromX = 0;
  double fromY = 0;
  double toX = 0;
  double toY = 0;
  NSUInteger moveDurationMs = 0;
  NSUInteger startHoldMs = 0;
  NSUInteger moveSteps = 0;
  NSUInteger endHoldMs = 0;
  if (!TTParseFiniteJSONDouble(from[@"x"], &fromX)
      || !TTParseFiniteJSONDouble(from[@"y"], &fromY)
      || !TTParseFiniteJSONDouble(to[@"x"], &toX)
      || !TTParseFiniteJSONDouble(to[@"y"], &toY)
      || !TTParseExactNonnegativeInteger(arguments[@"durationMs"], &moveDurationMs)
      || !TTParseExactNonnegativeInteger(held[@"startHoldMs"], &startHoldMs)
      || !TTParseExactNonnegativeInteger(held[@"moveSteps"], &moveSteps)
      || !TTParseExactNonnegativeInteger(held[@"endHoldMs"], &endHoldMs)) {
    return NO;
  }

  if (moveDurationMs < 100 || moveDurationMs > 5000
      || startHoldMs > 2000 || endHoldMs > 2000
      || moveSteps < 1 || moveSteps > 60) {
    return NO;
  }
  if (startHoldMs > NSUIntegerMax - moveDurationMs) {
    return NO;
  }
  NSUInteger plannedDurationMs = startHoldMs + moveDurationMs;
  if (endHoldMs > NSUIntegerMax - plannedDurationMs
      || plannedDurationMs + endHoldMs > 8000) {
    return NO;
  }

  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  XCUIElement *window = [app.windows firstMatch];
  if (nil == app || nil == window || ![window exists]) {
    return NO;
  }
  CGRect frame = window.frame;
  if (!TTFiniteViewportFrame(frame)
      || !TTPointIsInsideViewport(fromX, fromY, frame)
      || !TTPointIsInsideViewport(toX, toY, frame)) {
    return NO;
  }

  if (nil != output) {
    output->from = CGPointMake((CGFloat)fromX, (CGFloat)fromY);
    output->to = CGPointMake((CGFloat)toX, (CGFloat)toY);
    output->startHoldMs = startHoldMs;
    output->moveDurationMs = moveDurationMs;
    output->moveSteps = moveSteps;
    output->endHoldMs = endHoldMs;
  }
  if (nil != application) {
    *application = app;
  }
  return YES;
}

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

static BOOL TTKeyboardIndicatorsExist(XCUIApplication *app)
{
  XCUIElement *nextKeyboard = app.buttons[@"Next keyboard"];
  if ([nextKeyboard waitForExistenceWithTimeout:0.1]) {
    return YES;
  }
  XCUIElement *dictation = app.buttons[@"dictation"];
  return [dictation waitForExistenceWithTimeout:0.1];
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

  NSPredicate *deletePredicate = [NSPredicate predicateWithFormat:@"identifier CONTAINS[c] %@ OR label CONTAINS[c] %@ OR identifier CONTAINS[c] %@ OR label CONTAINS[c] %@", @"delete", @"delete", @"backspace", @"backspace"];
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

static BOOL TTPressThirdPartyDeleteCoordinateFallback(XCUIApplication *app, NSTimeInterval hold, NSString **strategy, NSString **failureReason)
{
  XCUIElement *target = [app.windows firstMatch];
  if (![target exists]) {
    target = app;
  }

  if (![target exists]) {
    if (nil != failureReason) {
      *failureReason = @"target_missing";
    }
    return NO;
  }

  @try {
    XCUICoordinate *coordinate = [target coordinateWithNormalizedOffset:CGVectorMake(0.935, 0.815)];
    [coordinate pressForDuration:hold];
    if (nil != strategy) {
      *strategy = [NSString stringWithFormat:@"third-party-coordinate-hold:0.94,0.82:%.2f", hold];
    }
    return YES;
  } @catch (NSException *e) {
    FBLogWarn(@"keyboard.clear-field-no-a11y third-party coordinate fallback threw hold=%.2f reason=%@", hold, e.reason);
    if (nil != failureReason) {
      *failureReason = e.reason ?: @"coordinate_press_threw";
    }
    return NO;
  }
}

#if !TARGET_OS_TV && !TARGET_OS_WATCH
static id<FBResponsePayload> TTRawInvalidArgument(NSString *message)
{
  return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:message traceback:nil]);
}

static BOOL TTRawRequestHasExactKeys(FBRouteRequest *request, NSSet *keys)
{
  return request.parameters.count == 0
    && [request.arguments isKindOfClass:NSDictionary.class]
    && TTDictionaryHasExactKeys(request.arguments, keys);
}

static BOOL TTRawPointIsInsideContext(CGPoint point, FBRawMainScreenContext context)
{
  return isfinite(point.x) && isfinite(point.y)
    && point.x >= 0 && point.x < context.logicalSize.width
    && point.y >= 0 && point.y < context.logicalSize.height;
}

static BOOL TTRawParsePoint(id x, id y, FBRawMainScreenContext context, CGPoint *point)
{
  double parsedX = 0;
  double parsedY = 0;
  if (!TTParseFiniteJSONDouble(x, &parsedX) || !TTParseFiniteJSONDouble(y, &parsedY)) {
    return NO;
  }
  CGPoint parsed = CGPointMake(parsedX, parsedY);
  if (!TTRawPointIsInsideContext(parsed, context)) {
    return NO;
  }
  *point = parsed;
  return YES;
}

static BOOL TTRawParsePointDictionary(id value, FBRawMainScreenContext context, CGPoint *point)
{
  if (![value isKindOfClass:NSDictionary.class]
      || !TTDictionaryHasExactKeys(value, [NSSet setWithObjects:@"x", @"y", nil])) {
    return NO;
  }
  return TTRawParsePoint(value[@"x"], value[@"y"], context, point);
}

static XCSynthesizedEventRecord *TTRawPointerRecord(FBRawMainScreenContext context, XCPointerEventPath *path)
{
  XCSynthesizedEventRecord *record = [XCSynthesizedEventRecord instancesRespondToSelector:@selector(initWithName:displayID:interfaceOrientation:)]
    ? [[XCSynthesizedEventRecord alloc] initWithName:@"Raw pointer input"
                                           displayID:context.displayID
                                interfaceOrientation:UIInterfaceOrientationPortrait]
    : [[XCSynthesizedEventRecord alloc] initWithName:@"Raw pointer input" interfaceOrientation:UIInterfaceOrientationPortrait];
  [record addPointerEventPath:path];
  return record;
}

static id<FBResponsePayload> TTRawSubmitRecord(XCSynthesizedEventRecord *record)
{
  double maximumOffset = record.maximumOffset;
  if (nil == record || !isfinite(maximumOffset) || maximumOffset < 0 || maximumOffset > 10) {
    return TTRawInvalidArgument(@"Raw input record offsets must be finite and between 0 and 10 seconds");
  }
  BOOL didTimeOut = NO;
  NSError *error = nil;
  @try {
    if ([FBXCTestDaemonsProxy synthesizeEventWithRecord:record timeout:maximumOffset + 2.0 didTimeOut:&didTimeOut error:&error]) {
      return FBResponseWithOK();
    }
  } @catch (NSException *exception) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:exception.reason traceback:nil]);
  }
  if (didTimeOut) {
    return FBResponseWithStatus([FBCommandStatus timeoutErrorWithMessage:@"Raw input synthesis timed out; physical delivery is uncertain and WDA did not retry."
                                                              traceback:nil]);
  }
  return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:error.localizedDescription ?: @"Raw input synthesis failed" traceback:nil]);
}

static id<FBResponsePayload> TTRawLinearInput(FBRawMainScreenContext context, CGPoint from, CGPoint to,
                                            NSTimeInterval duration, BOOL moves)
{
  XCPointerEventPath *path = [[XCPointerEventPath alloc] initForTouchAtPoint:from offset:0];
  if (moves) {
    [path moveToPoint:to atOffset:duration];
  }
  [path liftUpAtOffset:duration];
  return TTRawSubmitRecord(TTRawPointerRecord(context, path));
}

static id<FBResponsePayload> TTRawHandlePress(FBRouteRequest *request, BOOL longPress)
{
  NSSet *keys = longPress
    ? [NSSet setWithObjects:@"x", @"y", @"duration", nil]
    : [NSSet setWithObjects:@"x", @"y", nil];
  double duration = 0.125;
  if (!TTRawRequestHasExactKeys(request, keys)
      || (longPress && (!TTParseFiniteJSONDouble(request.arguments[@"duration"], &duration)
                        || duration < 0.01 || duration > 10))) {
    return TTRawInvalidArgument(@"Invalid raw press schema or duration");
  }
  FBRawMainScreenContext context;
  NSError *error = nil;
  if (![FBScreen rawPortraitMainScreenContext:&context error:&error]) {
    return TTRawInvalidArgument(error.localizedDescription);
  }
  CGPoint point;
  if (!TTRawParsePoint(request.arguments[@"x"], request.arguments[@"y"], context, &point)) {
    return TTRawInvalidArgument(@"Raw press coordinates must be finite numbers within the main screen");
  }
  return TTRawLinearInput(context, point, point, duration, NO);
}
#endif

@implementation FBInputCommands
+ (NSArray *)routes
{
  return @[
    /** HTTP verb: POST; path: /wda/keyboard/type-with-delay; request schema: {text:string,charDelayMs:number}; response schema: {ok,charCount,charDelayMs,durationMs}; error codes: 400/500; capability token: keyboard.type-with-delay */
    [[FBRoute POST:@"/wda/keyboard/type-with-delay"].withoutSession respondWithTarget:self action:@selector(handleTypeWithDelay:)],
    /** HTTP verb: POST; path: /wda/touch/swipe-bezier; request schema: {from:{x,y},to:{x,y},controlPoints:[{x,y}],durationMs:number,held?:{mode,startHoldMs,moveSteps,endHoldMs}}; response schema: legacy {ok,steps,controlPointCount,durationMs} or held {ok,mode,steps,controlPointCount,startHoldMs,moveDurationMs,durationMs,endHoldMs}; error codes: 400/500; capability token: touch.swipe-bezier */
    [[FBRoute POST:@"/wda/touch/swipe-bezier"].withoutSession respondWithTarget:self action:@selector(handleSwipeBezier:)],
    /** HTTP verb: POST; path: /wda/keyboard/clear-field; request schema: none; response schema: {ok,durationMs}; error codes: 404/500; capability token: keyboard.clear-field */
    [[FBRoute POST:@"/wda/keyboard/clear-field"].withoutSession respondWithTarget:self action:@selector(handleClearField:)],
    /** HTTP verb: POST; path: /wda/keyboard/clear-field-no-a11y; request schema: {approxChars?:number}; response schema: {ok,holdSeconds,durationMs}; error codes: 404/500; capability token: keyboard.clear-field-no-a11y */
    [[FBRoute POST:@"/wda/keyboard/clear-field-no-a11y"].withoutSession respondWithTarget:self action:@selector(handleClearFieldNoA11y:)],
#if !TARGET_OS_TV && !TARGET_OS_WATCH
    [[FBRoute POST:@"/wda/raw/tap"].withoutSession respondWithTarget:self action:@selector(handleRawTap:)],
    [[FBRoute POST:@"/wda/raw/swipe"].withoutSession respondWithTarget:self action:@selector(handleRawSwipe:)],
    [[FBRoute GET:@"/wda/raw/screen"].withoutSession respondWithTarget:self action:@selector(handleRawScreen:)],
    [[FBRoute POST:@"/wda/raw/long-press"].withoutSession respondWithTarget:self action:@selector(handleRawLongPress:)],
    [[FBRoute POST:@"/wda/raw/scroll"].withoutSession respondWithTarget:self action:@selector(handleRawScroll:)],
    [[FBRoute POST:@"/wda/raw/swipe-bezier"].withoutSession respondWithTarget:self action:@selector(handleRawSwipeBezier:)],
    [[FBRoute POST:@"/wda/raw/keyboard/type-with-delay"].withoutSession respondWithTarget:self action:@selector(handleRawTypeWithDelay:)],
    [[FBRoute POST:@"/wda/raw/keyboard/clear-field"].withoutSession respondWithTarget:self action:@selector(handleRawClearField:)],
#endif
  ];
}
#if !TARGET_OS_TV && !TARGET_OS_WATCH
+ (id<FBResponsePayload>)handleRawTap:(FBRouteRequest *)request
{
  return TTRawHandlePress(request, NO);
}

+ (id<FBResponsePayload>)handleRawLongPress:(FBRouteRequest *)request
{
  return TTRawHandlePress(request, YES);
}

+ (id<FBResponsePayload>)handleRawSwipe:(FBRouteRequest *)request
{
  double duration = 0;
  if (!TTRawRequestHasExactKeys(request, [NSSet setWithObjects:@"fromX", @"fromY", @"toX", @"toY", @"duration", nil])
      || !TTParseFiniteJSONDouble(request.arguments[@"duration"], &duration)
      || duration < 0.01 || duration > 10) {
    return TTRawInvalidArgument(@"Invalid raw swipe schema or duration");
  }
  FBRawMainScreenContext context;
  NSError *error = nil;
  if (![FBScreen rawPortraitMainScreenContext:&context error:&error]) {
    return TTRawInvalidArgument(error.localizedDescription);
  }
  CGPoint from;
  CGPoint to;
  if (!TTRawParsePoint(request.arguments[@"fromX"], request.arguments[@"fromY"], context, &from)
      || !TTRawParsePoint(request.arguments[@"toX"], request.arguments[@"toY"], context, &to)) {
    return TTRawInvalidArgument(@"Raw swipe coordinates must be finite numbers within the main screen");
  }
  return TTRawLinearInput(context, from, to, duration, YES);
}

+ (id<FBResponsePayload>)handleRawScreen:(FBRouteRequest *)request
{
  if (!TTRawRequestHasExactKeys(request, [NSSet set])) {
    return TTRawInvalidArgument(@"Raw screen accepts no body fields or query parameters");
  }
  FBRawMainScreenContext context;
  NSError *error = nil;
  if (![FBScreen rawPortraitMainScreenContext:&context error:&error]) {
    return TTRawInvalidArgument(error.localizedDescription);
  }
  return FBResponseWithObject(@{@"width": @(context.logicalSize.width),
                                @"height": @(context.logicalSize.height),
                                @"scale": @(context.scale)});
}

+ (id<FBResponsePayload>)handleRawScroll:(FBRouteRequest *)request
{
  NSString *direction = request.arguments[@"direction"];
  if (!TTRawRequestHasExactKeys(request, [NSSet setWithObject:@"direction"])
      || ![direction isKindOfClass:NSString.class]
      || ![@[@"up", @"down", @"left", @"right"] containsObject:direction]) {
    return TTRawInvalidArgument(@"Raw scroll requires only direction: up, down, left, or right");
  }
  FBRawMainScreenContext context;
  NSError *error = nil;
  if (![FBScreen rawPortraitMainScreenContext:&context error:&error]) {
    return TTRawInvalidArgument(error.localizedDescription);
  }
  double width = context.logicalSize.width;
  double height = context.logicalSize.height;
  BOOL vertical = [direction isEqualToString:@"up"] || [direction isEqualToString:@"down"];
  CGPoint from = vertical ? CGPointMake(width * 0.5, height * 0.2) : CGPointMake(width * 0.2, height * 0.5);
  CGPoint to = vertical ? CGPointMake(width * 0.5, height * 0.8) : CGPointMake(width * 0.8, height * 0.5);
  if ([direction isEqualToString:@"down"] || [direction isEqualToString:@"right"]) {
    CGPoint swap = from;
    from = to;
    to = swap;
  }
  if (!TTRawPointIsInsideContext(from, context) || !TTRawPointIsInsideContext(to, context)) {
    return TTRawInvalidArgument(@"Raw scroll points must lie within the main screen");
  }
  return TTRawLinearInput(context, from, to, 0.25, YES);
}

+ (id<FBResponsePayload>)handleRawSwipeBezier:(FBRouteRequest *)request
{
  NSDictionary *arguments = request.arguments;
  BOOL held = nil != arguments[@"held"];
  NSSet *keys = held
    ? [NSSet setWithObjects:@"from", @"to", @"controlPoints", @"durationMs", @"held", nil]
    : [NSSet setWithObjects:@"from", @"to", @"controlPoints", @"durationMs", nil];
  NSUInteger durationMs = 0;
  if (!TTRawRequestHasExactKeys(request, keys)
      || ![arguments[@"controlPoints"] isKindOfClass:NSArray.class]
      || [arguments[@"controlPoints"] count] > 10
      || !TTParseExactNonnegativeInteger(arguments[@"durationMs"], &durationMs)
      || durationMs < 100 || durationMs > (held ? 5000 : 10000)) {
    return TTRawInvalidArgument(@"Invalid raw Bezier schema, controls, or durationMs");
  }
  NSUInteger startHoldMs = 0;
  NSUInteger endHoldMs = 0;
  NSUInteger steps = MAX((NSUInteger)10, (NSUInteger)floor(durationMs / 1000.0 * 60.0));
  if (held) {
    NSDictionary *hold = arguments[@"held"];
    if (![hold isKindOfClass:NSDictionary.class]
        || !TTDictionaryHasExactKeys(hold, [NSSet setWithObjects:@"mode", @"startHoldMs", @"moveSteps", @"endHoldMs", nil])
        || ![hold[@"mode"] isKindOfClass:NSString.class]
        || ![hold[@"mode"] isEqualToString:@"continuous_drag_v1"]
        || [arguments[@"controlPoints"] count] != 0
        || !TTParseExactNonnegativeInteger(hold[@"startHoldMs"], &startHoldMs)
        || !TTParseExactNonnegativeInteger(hold[@"endHoldMs"], &endHoldMs)
        || !TTParseExactNonnegativeInteger(hold[@"moveSteps"], &steps)
        || startHoldMs > 2000 || endHoldMs > 2000 || steps < 1 || steps > 60
        || startHoldMs + durationMs + endHoldMs > 8000) {
      return TTRawInvalidArgument(@"Invalid raw continuous_drag_v1 schedule");
    }
  }

  FBRawMainScreenContext context;
  NSError *error = nil;
  if (![FBScreen rawPortraitMainScreenContext:&context error:&error]) {
    return TTRawInvalidArgument(error.localizedDescription);
  }
  CGPoint from;
  CGPoint to;
  if (!TTRawParsePointDictionary(arguments[@"from"], context, &from)
      || !TTRawParsePointDictionary(arguments[@"to"], context, &to)) {
    return TTRawInvalidArgument(@"Raw Bezier endpoints must be exact x,y objects within the main screen");
  }
  NSMutableArray<NSValue *> *controls = [NSMutableArray array];
  for (id value in arguments[@"controlPoints"]) {
    CGPoint point;
    if (!TTRawParsePointDictionary(value, context, &point)) {
      return TTRawInvalidArgument(@"Raw Bezier controls must be exact x,y objects within the main screen");
    }
    [controls addObject:[NSValue valueWithCGPoint:point]];
  }
  NSArray<NSValue *> *points = [FBBezierInterpolator pointsAlongCurveFrom:from to:to controlPoints:controls steps:steps];
  if (points.count != steps + 1) {
    return TTRawInvalidArgument(@"Raw Bezier interpolation must return exactly steps + 1 points");
  }
  for (NSValue *value in points) {
    if (!TTRawPointIsInsideContext(value.CGPointValue, context)) {
      return TTRawInvalidArgument(@"Raw Bezier path must remain within the main screen");
    }
  }

  CGPoint first = points.firstObject.CGPointValue;
  XCPointerEventPath *path = [[XCPointerEventPath alloc] initForTouchAtPoint:first offset:0];
  if (startHoldMs > 0) {
    [path moveToPoint:first atOffset:startHoldMs / 1000.0];
  }
  for (NSUInteger i = 1; i < points.count; i++) {
    [path moveToPoint:points[i].CGPointValue atOffset:(startHoldMs + (double)durationMs * i / steps) / 1000.0];
  }
  [path liftUpAtOffset:(startHoldMs + durationMs + endHoldMs) / 1000.0];
  return TTRawSubmitRecord(TTRawPointerRecord(context, path));
}

+ (id<FBResponsePayload>)handleRawTypeWithDelay:(FBRouteRequest *)request
{
  NSString *text = request.arguments[@"text"];
  NSUInteger delayMs = 0;
  if (!TTRawRequestHasExactKeys(request, [NSSet setWithObjects:@"text", @"charDelayMs", nil])
      || ![text isKindOfClass:NSString.class] || text.length == 0
      || !TTParseExactNonnegativeInteger(request.arguments[@"charDelayMs"], &delayMs) || delayMs > 5000) {
    return TTRawInvalidArgument(@"Raw typing requires nonempty text and integer charDelayMs from 0 to 5000");
  }
  NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (nil == utf8 || utf8.length > 8192) {
    return TTRawInvalidArgument(@"Raw typing text must be UTF-8 and at most 8192 bytes");
  }
  NSMutableArray<NSString *> *clusters = [NSMutableArray array];
  [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                          options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
    [clusters addObject:substring];
  }];
  if (clusters.count == 0
      || (delayMs > 0 && (clusters.count - 1 > NSUIntegerMax / delayMs
                         || (clusters.count - 1) * delayMs > 10000))) {
    return TTRawInvalidArgument(@"Raw typing schedule must be at most 10000 milliseconds");
  }
  XCPointerEventPath *path = [[XCPointerEventPath alloc] initForTextInput];
  for (NSUInteger i = 0; i < clusters.count; i++) {
    [path typeKey:clusters[i] modifiers:0 atOffset:i * delayMs / 1000.0];
  }
  XCSynthesizedEventRecord *record = [[XCSynthesizedEventRecord alloc] initWithName:@"Raw delayed typing"];
  [record addPointerEventPath:path];
  return TTRawSubmitRecord(record);
}

+ (id<FBResponsePayload>)handleRawClearField:(FBRouteRequest *)request
{
  NSUInteger count = 128;
  BOOL hasCount = nil != request.arguments[@"approxChars"];
  NSSet *keys = hasCount ? [NSSet setWithObject:@"approxChars"] : [NSSet set];
  if (!TTRawRequestHasExactKeys(request, keys)
      || (hasCount && (!TTParseExactNonnegativeInteger(request.arguments[@"approxChars"], &count)
                       || count < 1 || count > 256))) {
    return TTRawInvalidArgument(@"Raw clear accepts only optional integer approxChars from 1 to 256");
  }
  XCPointerEventPath *path = [[XCPointerEventPath alloc] initForTextInput];
  for (NSUInteger i = 0; i < count; i++) {
    [path typeKey:XCUIKeyboardKeyDelete modifiers:0 atOffset:i * 0.025];
  }
  XCSynthesizedEventRecord *record = [[XCSynthesizedEventRecord alloc] initWithName:@"Raw clear field"];
  [record addPointerEventPath:path];
  return TTRawSubmitRecord(record);
}
#endif

+ (id<FBResponsePayload>)handleTypeWithDelay:(FBRouteRequest *)request
{
  NSString *text = request.arguments[@"text"]; NSNumber *delayNum = request.arguments[@"charDelayMs"]; if (nil == text || nil == delayNum) return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"text and charDelayMs are required" traceback:nil]); NSTimeInterval delay = MIN(MAX(delayNum.doubleValue / 1000.0, 0), 5.0); NSDate *s = [NSDate date]; XCUIElement *target = [XCUIApplication.fb_activeApplication.windows firstMatch]; NSUInteger charCount = text.length;
  for (NSUInteger i = 0; i < charCount; i++) { @try { [target typeKey:[text substringWithRange:NSMakeRange(i, 1)] modifierFlags:0]; } @catch (NSException *e) { FBLogWarn(@"keyboard.type-with-delay failed index=%lu charCount=%lu reason=%@", (unsigned long)i, (unsigned long)charCount, e.reason); return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"typeKey_threw", @"failedAtIndex": @(i), @"durationMs": @(TTInputMs(s))} httpStatusCode:kHTTPStatusCodeInternalServerError]; } if (i + 1 < charCount && delay > 0) [NSThread sleepForTimeInterval:delay]; }
  FBLogVerbose(@"keyboard.type-with-delay charCount=%lu charDelayMs=%@ durationMs=%ld", (unsigned long)charCount, delayNum, (long)TTInputMs(s)); return FBResponseWithObject(@{@"ok": @YES, @"charCount": @(charCount), @"charDelayMs": delayNum, @"durationMs": @(TTInputMs(s))});
}
+ (id<FBResponsePayload>)handleSwipeBezier:(FBRouteRequest *)request
{
  if ([request.arguments.allKeys containsObject:@"held"]) {
    TTHeldSwipeRequest heldRequest = {0};
    XCUIApplication *app = nil;
    if (!TTParseHeldSwipeRequest(request.arguments, &heldRequest, &app)) {
      return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"invalid held request" traceback:nil]);
    }

    NSArray<NSValue *> *path = [FBBezierInterpolator pointsAlongCurveFrom:heldRequest.from
                                                                        to:heldRequest.to
                                                              controlPoints:@[]
                                                                        steps:heldRequest.moveSteps];
    if (path.count != heldRequest.moveSteps + 1) {
      return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"insufficient path points" traceback:nil]);
    }

    NSDate *startedAt = [NSDate date];
    CGFloat perMoveMs = (CGFloat)heldRequest.moveDurationMs / (CGFloat)heldRequest.moveSteps;
    NSMutableArray *actionItems = [NSMutableArray arrayWithCapacity:heldRequest.moveSteps + 5];
    CGPoint startPoint = [path[0] CGPointValue];
    [actionItems addObject:@{
      @"type": @"pointerMove",
      @"x": @(startPoint.x),
      @"y": @(startPoint.y),
      @"origin": @"viewport",
      @"duration": @(0),
    }];
    [actionItems addObject:@{
      @"type": @"pointerDown",
      @"button": @(0),
    }];
    [actionItems addObject:@{
      @"type": @"pause",
      @"duration": @(heldRequest.startHoldMs),
    }];
    for (NSUInteger i = 1; i < path.count; i++) {
      CGPoint point = [path[i] CGPointValue];
      [actionItems addObject:@{
        @"type": @"pointerMove",
        @"x": @(point.x),
        @"y": @(point.y),
        @"origin": @"viewport",
        @"duration": @(perMoveMs),
      }];
    }
    [actionItems addObject:@{
      @"type": @"pause",
      @"duration": @(heldRequest.endHoldMs),
    }];
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

    FBLogVerbose(@"touch.swipe-bezier mode=continuous_drag_v1 steps=%lu startHoldMs=%lu moveDurationMs=%lu endHoldMs=%lu durationMs=%ld",
                 (unsigned long)heldRequest.moveSteps,
                 (unsigned long)heldRequest.startHoldMs,
                 (unsigned long)heldRequest.moveDurationMs,
                 (unsigned long)heldRequest.endHoldMs,
                 (long)durationMs);
    return FBResponseWithObject(@{@"ok": @YES,
                                  @"mode": @"continuous_drag_v1",
                                  @"steps": @(heldRequest.moveSteps),
                                  @"controlPointCount": @(0),
                                  @"startHoldMs": @(heldRequest.startHoldMs),
                                  @"moveDurationMs": @(heldRequest.moveDurationMs),
                                  @"durationMs": @(durationMs),
                                  @"endHoldMs": @(heldRequest.endHoldMs)});
  }

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
  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  XCUIElement *keyboard = [app.keyboards firstMatch];
  if (nil == keyboard || ![keyboard exists]) {
    NSString *strategy = nil;
    if (TTKeyboardIndicatorsExist(app)) {
      NSString *failureReason = nil;
      if (TTPressThirdPartyDeleteCoordinateFallback(app, hold, &strategy, &failureReason)) {
        FBLogVerbose(@"keyboard.clear-field-no-a11y strategy=%@ holdSeconds=%.2f approxChars=%@ durationMs=%ld", strategy ?: @"(none)", hold, approx ?: @"(blind)", (long)TTInputMs(s));
        return FBResponseWithObject(@{@"ok": @YES, @"holdSeconds": @(hold), @"durationMs": @(TTInputMs(s))});
      }
      FBLogWarn(@"keyboard.clear-field-no-a11y third-party delete coordinate failed reason=%@", failureReason ?: @"unknown");
      BOOL didThrow = nil != failureReason && ![failureReason isEqualToString:@"target_missing"];
      return [[FBResponseJSONPayload alloc]
              initWithDictionary:@{@"ok": @NO,
                                   @"error": didThrow ? @"press_threw" : @"no_delete_key",
                                   @"durationMs": @(TTInputMs(s))}
              httpStatusCode:didThrow ? kHTTPStatusCodeInternalServerError : kHTTPStatusCodeNotFound];
    }
    FBLogWarn(@"keyboard.clear-field-no-a11y no keyboard on screen");
    return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"no_keyboard", @"durationMs": @(TTInputMs(s))} httpStatusCode:kHTTPStatusCodeNotFound];
  }
  NSString *strategy = @"xcui-keyboard";
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
