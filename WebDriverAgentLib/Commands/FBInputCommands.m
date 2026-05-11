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
@end
