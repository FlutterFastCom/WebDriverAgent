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
#import "XCUICoordinate.h"
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
  NSDictionary *from = request.arguments[@"from"]; NSDictionary *to = request.arguments[@"to"]; NSNumber *dur = request.arguments[@"durationMs"]; if (!from || !to || !dur) return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"from, to, and durationMs are required" traceback:nil]); NSDate *s = [NSDate date]; CGFloat ms = MIN(MAX(dur.doubleValue, 100), 10000); NSUInteger steps = MAX(10u, (NSUInteger)(ms / 1000.0 * 60.0)); NSMutableArray *cps = [NSMutableArray array]; for (NSDictionary *cp in (request.arguments[@"controlPoints"] ?: @[])) [cps addObject:[NSValue valueWithCGPoint:CGPointMake([cp[@"x"] doubleValue], [cp[@"y"] doubleValue])]]; NSArray *path = [FBBezierInterpolator pointsAlongCurveFrom:CGPointMake([from[@"x"] doubleValue], [from[@"y"] doubleValue]) to:CGPointMake([to[@"x"] doubleValue], [to[@"y"] doubleValue]) controlPoints:cps steps:steps]; XCUIApplication *app = XCUIApplication.fb_activeApplication; XCUICoordinate *current = [[app coordinateWithNormalizedOffset:CGVectorMake(0, 0)] coordinateWithOffset:CGVectorMake([from[@"x"] doubleValue], [from[@"y"] doubleValue])];
  for (NSUInteger i = 1; i < path.count; i++) { CGPoint p = [path[i] CGPointValue]; XCUICoordinate *next = [[app coordinateWithNormalizedOffset:CGVectorMake(0, 0)] coordinateWithOffset:CGVectorMake(p.x, p.y)]; [current pressForDuration:0 thenDragToCoordinate:next withVelocity:0 thenHoldForDuration:(ms / 1000.0) / path.count]; current = next; }
  FBLogVerbose(@"touch.swipe-bezier steps=%lu cps=%lu durationMs=%ld", (unsigned long)steps, (unsigned long)cps.count, (long)TTInputMs(s)); return FBResponseWithObject(@{@"ok": @YES, @"steps": @(steps), @"controlPointCount": @(cps.count), @"durationMs": @(TTInputMs(s))});
}
+ (id<FBResponsePayload>)handleClearField:(FBRouteRequest *)request
{
  NSDate *s = [NSDate date]; XCUIApplication *app = XCUIApplication.fb_activeApplication; XCUIElement *field = [[app.textFields firstMatch] exists] ? [app.textFields firstMatch] : ([[app.textViews firstMatch] exists] ? [app.textViews firstMatch] : [app.secureTextFields firstMatch]); if (![field exists]) return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"no_focused_field", @"durationMs": @(TTInputMs(s))} httpStatusCode:kHTTPStatusCodeNotFound]; [field pressForDuration:1.0]; [NSThread sleepForTimeInterval:0.4]; XCUIElement *selectAll = [[app.menuItems matchingPredicate:[NSPredicate predicateWithFormat:@"label IN {'Select All', 'select all'}"]] firstMatch]; if ([selectAll exists]) [selectAll tap]; else [field typeKey:@"a" modifierFlags:XCUIKeyModifierCommand]; [NSThread sleepForTimeInterval:0.2]; [field typeKey:XCUIKeyboardKeyDelete modifierFlags:0]; FBLogVerbose(@"keyboard.clear-field durationMs=%ld", (long)TTInputMs(s)); return FBResponseWithObject(@{@"ok": @YES, @"durationMs": @(TTInputMs(s))});
}
@end
