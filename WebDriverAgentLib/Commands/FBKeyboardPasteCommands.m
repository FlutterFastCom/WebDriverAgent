/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBKeyboardPasteCommands.h"
#import <UIKit/UIKit.h>
#import "FBCommandStatus.h"
#import "FBHTTPStatusCodes.h"
#import "FBLogger.h"
#import "FBResponseJSONPayload.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "XCUIApplication.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"

static NSInteger TTDurationMsSince(NSDate *startedAt) { return (NSInteger)([[NSDate date] timeIntervalSinceDate:startedAt] * 1000); }

@implementation FBKeyboardPasteCommands
+ (NSArray *)routes
{
  return @[
    /**
     * HTTP verb: POST
     * path: /wda/keyboard/typeViaPaste
     * request schema: { text: string }
     * response schema: { pasted: true, strategy: "cmdV"|"menuLongPress", charCount: number, durationMs: number } or 501 { error, attempted, reason, durationMs }
     * error codes: 400 missing text, 501 paste strategy unavailable
     * capability token: keyboard.paste
     */
    [[FBRoute POST:@"/wda/keyboard/typeViaPaste"].withoutSession respondWithTarget:self action:@selector(handleTypeViaPaste:)],
  ];
}

+ (id<FBResponsePayload>)handleTypeViaPaste:(FBRouteRequest *)request
{
  NSString *text = request.arguments[@"text"];
  if (nil == text) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"text is required" traceback:nil]);
  }
  NSDate *startedAt = [NSDate date];
  NSUInteger charCount = text.length;
  [UIPasteboard generalPasteboard].string = text;
  [NSThread sleepForTimeInterval:0.1];
  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  XCUIElement *target = [app.windows firstMatch];
  @try {
    [target typeKey:@"v" modifierFlags:XCUIKeyModifierCommand];
    NSInteger durationMs = TTDurationMsSince(startedAt);
    FBLogVerbose(@"keyboard.typeViaPaste strategy=cmdV charCount=%lu durationMs=%ld", (unsigned long)charCount, (long)durationMs);
    return FBResponseWithObject(@{@"pasted": @YES, @"strategy": @"cmdV", @"charCount": @(charCount), @"durationMs": @(durationMs)});
  } @catch (NSException *exception) {
    FBLogInfo(@"keyboard.typeViaPaste cmdV failed; trying menuLongPress reason=%@", exception.reason);
  }
  XCUIElement *field = [[app.textFields firstMatch] exists] ? [app.textFields firstMatch] : ([[app.textViews firstMatch] exists] ? [app.textViews firstMatch] : [app.secureTextFields firstMatch]);
  if (![field exists]) {
    NSInteger durationMs = TTDurationMsSince(startedAt);
    return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"error": @"no_strategy_succeeded", @"attempted": @[@"cmdV", @"menuLongPress"], @"reason": @"no text field", @"durationMs": @(durationMs)} httpStatusCode:kHTTPStatusCodeNotImplemented];
  }
  [field pressForDuration:1.0];
  [NSThread sleepForTimeInterval:0.5];
  XCUIElement *paste = [[app.menuItems matchingPredicate:[NSPredicate predicateWithFormat:@"label IN {'Paste', 'paste'}"]] firstMatch];
  if (![paste exists]) {
    NSInteger durationMs = TTDurationMsSince(startedAt);
    return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"error": @"no_strategy_succeeded", @"attempted": @[@"cmdV", @"menuLongPress"], @"reason": @"Paste menu item not found", @"durationMs": @(durationMs)} httpStatusCode:kHTTPStatusCodeNotImplemented];
  }
  [paste tap];
  NSInteger durationMs = TTDurationMsSince(startedAt);
  FBLogVerbose(@"keyboard.typeViaPaste strategy=menuLongPress charCount=%lu durationMs=%ld", (unsigned long)charCount, (long)durationMs);
  return FBResponseWithObject(@{@"pasted": @YES, @"strategy": @"menuLongPress", @"charCount": @(charCount), @"durationMs": @(durationMs)});
}
@end
