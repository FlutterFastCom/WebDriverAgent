/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBNetworkCommands.h"
#import "FBHTTPStatusCodes.h"
#import "FBLogger.h"
#import "FBResponseJSONPayload.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "XCUIApplication.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"

static NSInteger TTDurationMsSince(NSDate *startedAt) { return (NSInteger)([[NSDate date] timeIntervalSinceDate:startedAt] * 1000); }

@implementation FBNetworkCommands
+ (NSArray *)routes
{
  return @[
    /**
     * HTTP verb: POST
     * path: /wda/network/airplane/toggle
     * request schema: none
     * response schema: { toggled: true, strategy: "xcuiNav", priorState, newState, durationMs } or 501 { error, attempted, durationMs }
     * error codes: 501 Settings switch not found
     * capability token: network.airplane.toggle
     */
    [[FBRoute POST:@"/wda/network/airplane/toggle"].withoutSession respondWithTarget:self action:@selector(handleAirplaneToggle:)],
  ];
}

+ (id<FBResponsePayload>)handleAirplaneToggle:(FBRouteRequest *)request
{
  NSDate *startedAt = [NSDate date];
  XCUIApplication *settings = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.Preferences"];
  [settings activate];
  [NSThread sleepForTimeInterval:0.8];
  XCUIElement *toggle = [[settings.switches matchingIdentifier:@"Airplane Mode"] firstMatch];
  if (![toggle exists]) {
    XCUIElement *cell = [[settings.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", @"Airplane Mode"]] firstMatch];
    toggle = [cell.switches firstMatch];
  }
  if (![toggle exists]) {
    NSInteger durationMs = TTDurationMsSince(startedAt);
    FBLogWarn(@"network.airplane.toggle switch_not_found durationMs=%ld", (long)durationMs);
    return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"error": @"no_strategy_succeeded", @"attempted": @[@"xcuiNav"], @"durationMs": @(durationMs)} httpStatusCode:kHTTPStatusCodeNotImplemented];
  }
  NSString *prior = [toggle.value description] ?: @"unknown";
  [toggle tap];
  [NSThread sleepForTimeInterval:0.5];
  NSString *next = [toggle.value description] ?: @"unknown";
  NSInteger durationMs = TTDurationMsSince(startedAt);
  FBLogInfo(@"network.airplane.toggle prior=%@ new=%@ durationMs=%ld", prior, next, (long)durationMs);
  return FBResponseWithObject(@{@"toggled": @YES, @"strategy": @"xcuiNav", @"priorState": prior, @"newState": next, @"durationMs": @(durationMs)});
}
@end
