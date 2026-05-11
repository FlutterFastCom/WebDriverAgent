/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBDisplaySettingsCommands.h"
#import "FBCommandStatus.h"
#import "FBHTTPStatusCodes.h"
#import "FBLogger.h"
#import "FBResponseJSONPayload.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBSettingsAppNavigator.h"
#import "TTElementFinder.h"
#import "XCUIApplication.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"

@implementation FBDisplaySettingsCommands

+ (NSArray *)routes
{
  return @[
    /** HTTP verb: POST; path: /wda/system/auto-lock/set; request schema: {duration: "30s"|"1m"|"2m"|"3m"|"4m"|"5m"|"never"} (default "never"), query {dryRun?: bool}; response schema: {ok, navigatedPath, finalState, grantedDuration, dryRun, durationMs}; error codes: 400 invalid_duration, 404 label_not_found, 409 blocked_by_low_power_mode; capability token: system.auto-lock.set */
    [[FBRoute POST:@"/wda/system/auto-lock/set"].withoutSession respondWithTarget:self action:@selector(handleSetAutoLock:)],
  ];
}

+ (NSDictionary *)durationLabelMap
{
  // Body string -> iOS Settings.app row label.
  // Lowercase labels are the iOS 26 observed form (verified iPhone 14 Pro /
  // iOS 26.1). TTElementFinder.findRowInApp:byText: matches case-insensitively
  // via `label CONTAINS[c]` AND `identifier CONTAINS[c]`, so future label
  // re-capitalization (e.g., "5 Minutes" returns) survives without code change.
  return @{
    @"30s":   @"30 seconds",
    @"1m":    @"1 minute",
    @"2m":    @"2 minutes",
    @"3m":    @"3 minutes",
    @"4m":    @"4 minutes",
    @"5m":    @"5 minutes",
    @"never": @"Never",
  };
}

+ (BOOL)parseDryRun:(FBRouteRequest *)request
{
  NSURLComponents *c = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
  for (NSURLQueryItem *i in c.queryItems) {
    if ([i.name isEqualToString:@"dryRun"] && [i.value isEqualToString:@"true"]) return YES;
  }
  return NO;
}

+ (id<FBResponsePayload>)errorResponseWith:(NSError *)error startedAt:(NSDate *)startedAt path:(NSArray *)path code:(NSInteger)code
{
  NSInteger durationMs = (NSInteger)([[NSDate date] timeIntervalSinceDate:startedAt] * 1000);
  NSMutableDictionary *body = [@{@"ok": @NO, @"error": error.localizedDescription ?: @"unknown", @"navigatedPath": path ?: @[], @"durationMs": @(durationMs)} mutableCopy];
  if (error.userInfo[@"missingLabel"]) body[@"missingLabel"] = error.userInfo[@"missingLabel"];
  return [[FBResponseJSONPayload alloc] initWithDictionary:body httpStatusCode:code];
}

+ (id<FBResponsePayload>)handleSetAutoLock:(FBRouteRequest *)request
{
  NSString *duration = request.arguments[@"duration"] ?: @"never";
  NSDictionary *labelMap = [self durationLabelMap];
  NSString *targetLabel = labelMap[duration];

  // Validation: duration MUST be one of the 7 enum values
  if (!targetLabel) {
    return [[FBResponseJSONPayload alloc] initWithDictionary:@{
      @"ok": @NO,
      @"error": @"invalid_duration",
      @"got": duration,
      @"allowed": labelMap.allKeys,
      @"durationMs": @0,
    } httpStatusCode:kHTTPStatusCodeBadRequest];
  }

  BOOL dryRun = [self parseDryRun:request];
  NSDate *startedAt = [NSDate date];
  FBSettingsAppNavigator *nav = [FBSettingsAppNavigator sharedInstance];
  NSError *err = nil;

  if (![nav launchSettings:&err]) {
    return [self errorResponseWith:err startedAt:startedAt path:@[] code:kHTTPStatusCodeNotFound];
  }
  if (![nav navigateToPath:@[@"Display & Brightness", @"Auto-Lock"] error:&err]) {
    return [self errorResponseWith:err startedAt:startedAt path:@[@"Display & Brightness", @"Auto-Lock"] code:kHTTPStatusCodeNotFound];
  }

  XCUIApplication *settings = nav.settingsApp;

  // LPM detection (DUAL signal): banner present OR Never row absent
  XCUIElement *lpmBanner = [[settings.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"label BEGINSWITH 'Auto-Lock setting cannot be modified'"]] firstMatch];
  XCUIElement *neverRow = [[settings.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label == 'Never'"]] firstMatch];
  BOOL lpmBlocked = [lpmBanner exists] || ![neverRow exists];

  if (lpmBlocked) {
    NSInteger durationMs = (NSInteger)([[NSDate date] timeIntervalSinceDate:startedAt] * 1000);
    FBLogInfo(@"system.auto-lock.set BLOCKED by Low Power Mode (duration=%@ dryRun=%d)", duration, dryRun);
    return [[FBResponseJSONPayload alloc] initWithDictionary:@{
      @"ok": @NO,
      @"error": @"blocked_by_low_power_mode",
      @"currentDuration": @"30s",
      @"navigatedPath": @[@"Display & Brightness"],
      @"durationMs": @(durationMs),
    } httpStatusCode:kHTTPStatusCodeConflict];
  }

  // Find the target duration row via TTElementFinder. The helper combines
  // `label CONTAINS[c]` AND `identifier CONTAINS[c]` and tries Cell-then-Button,
  // explicitly excluding XCUIElementTypeStaticText (non-interactive children).
  // This survives both iOS 26's lowercased labels AND future re-capitalization.
  XCUIElement *targetRow = [TTElementFinder findRowInApp:settings byText:targetLabel];
  if (![targetRow exists]) {
    NSError *notFound = [NSError errorWithDomain:@"FBDisplaySettingsCommands"
                                            code:2
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"label not found: %@", targetLabel],
                                                   @"missingLabel": targetLabel}];
    return [self errorResponseWith:notFound startedAt:startedAt path:@[@"Display & Brightness", @"Auto-Lock"] code:kHTTPStatusCodeNotFound];
  }

  if (dryRun) {
    NSInteger durationMs = (NSInteger)([[NSDate date] timeIntervalSinceDate:startedAt] * 1000);
    FBLogInfo(@"system.auto-lock.set dryRun=YES (row '%@' found but not tapped)", targetLabel);
    return FBResponseWithObject(@{
      @"ok": @YES,
      @"dryRun": @YES,
      @"navigatedPath": @[@"Display & Brightness", @"Auto-Lock", targetLabel],
      @"finalState": @"unchanged",
      @"durationMs": @(durationMs),
    });
  }

  [targetRow tap];
  [NSThread sleepForTimeInterval:0.3];

  NSInteger durationMs = (NSInteger)([[NSDate date] timeIntervalSinceDate:startedAt] * 1000);
  FBLogVerbose(@"system.auto-lock.set duration=%@ durationMs=%ld", duration, (long)durationMs);
  return FBResponseWithObject(@{
    @"ok": @YES,
    @"navigatedPath": @[@"Display & Brightness", @"Auto-Lock", targetLabel],
    @"finalState": duration,
    @"grantedDuration": duration,
    @"dryRun": @NO,
    @"durationMs": @(durationMs),
  });
}

@end
