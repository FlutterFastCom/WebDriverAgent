/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBAppDataCommands.h"
#import "FBCommandStatus.h"
#import "FBHTTPStatusCodes.h"
#import "FBLogger.h"
#import "FBResponseJSONPayload.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"

static NSInteger TTDurationMsSince(NSDate *startedAt) { return (NSInteger)([[NSDate date] timeIntervalSinceDate:startedAt] * 1000); }

@implementation FBAppDataCommands
+ (NSArray *)routes
{
  return @[
    /**
     * HTTP verb: POST
     * path: /wda/apps/clearData/:bundleId
     * request schema: path { bundleId: string }
     * response schema: success { cleared: true, strategy: "privateApi", bundleId, durationMs } or 501 { error, attempted, bundleId, durationMs }
     * error codes: 400 missing bundleId, 501 PrivateAPI unavailable/failure
     * capability token: apps.cleardata
     */
    [[FBRoute POST:@"/wda/apps/clearData/:bundleId"].withoutSession respondWithTarget:self action:@selector(handleClearAppData:)],
  ];
}

+ (id<FBResponsePayload>)handleClearAppData:(FBRouteRequest *)request
{
  NSString *bundleId = request.parameters[@"bundleId"];
  if (0 == bundleId.length) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"bundleId is required" traceback:nil]);
  }
  NSDate *startedAt = [NSDate date];
  Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
  id workspace = workspaceClass ? [workspaceClass performSelector:@selector(defaultWorkspace)] : nil;
  NSArray<NSString *> *selectors = @[@"removeApplicationDataForBundleIdentifier:", @"removeApplicationDirectoriesForBundleIdentifier:"];
  for (NSString *selectorName in selectors) {
    SEL selector = NSSelectorFromString(selectorName);
    if (workspace && [workspace respondsToSelector:selector]) {
      @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [workspace performSelector:selector withObject:bundleId];
#pragma clang diagnostic pop
        NSInteger durationMs = TTDurationMsSince(startedAt);
        FBLogInfo(@"apps.cleardata bundleId=%@ strategy=privateApi durationMs=%ld", bundleId, (long)durationMs);
        return FBResponseWithObject(@{@"cleared": @YES, @"strategy": @"privateApi", @"bundleId": bundleId, @"durationMs": @(durationMs)});
      } @catch (NSException *exception) {
        FBLogWarn(@"apps.cleardata PrivateAPI selector=%@ failed reason=%@", selectorName, exception.reason);
      }
    }
  }
  NSInteger durationMs = TTDurationMsSince(startedAt);
  return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"error": @"no_strategy_succeeded", @"attempted": @[@"privateApi"], @"bundleId": bundleId, @"strategy": @"501", @"durationMs": @(durationMs)} httpStatusCode:kHTTPStatusCodeNotImplemented];
}
@end
