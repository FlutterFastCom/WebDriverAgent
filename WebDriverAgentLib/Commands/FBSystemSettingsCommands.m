/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBSystemSettingsCommands.h"
#import "FBCommandStatus.h"
#import "FBHTTPStatusCodes.h"
#import "FBLogger.h"
#import "FBResponseJSONPayload.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBSettingsAppNavigator.h"
#import "XCUIApplication.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"

static NSInteger TTSysMs(NSDate *startedAt) { return (NSInteger)([[NSDate date] timeIntervalSinceDate:startedAt] * 1000); }
static BOOL TTDryRun(FBRouteRequest *request) { NSURLComponents *c = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO]; for (NSURLQueryItem *i in c.queryItems) { if ([i.name isEqualToString:@"dryRun"] && [i.value isEqualToString:@"true"]) return YES; } return NO; }

@implementation FBSystemSettingsCommands
+ (NSArray *)routes
{
  return @[
    /** HTTP verb: POST; path: /wda/system/reset-all-settings; request schema: query {dryRun?:bool}; response schema: {ok,dryRun,navigatedPath,durationMs}; error codes: 404 nav failure; capability token: system.reset-all-settings */
    [[FBRoute POST:@"/wda/system/reset-all-settings"].withoutSession respondWithTarget:self action:@selector(handleResetAllSettings:)],
    /** HTTP verb: POST; path: /wda/system/motion/reduce; request schema: {enabled:bool}; response schema: {ok,finalState,durationMs}; error codes: 404 nav failure; capability token: system.motion.reduce */
    [[FBRoute POST:@"/wda/system/motion/reduce"].withoutSession respondWithTarget:self action:@selector(handleSetMotionReduce:)],
    /** HTTP verb: POST; path: /wda/system/language/set; request schema: {language:string}, query {dryRun?:bool}; response schema: {ok,dryRun,language,durationMs}; error codes: 400/404; capability token: system.language.set */
    [[FBRoute POST:@"/wda/system/language/set"].withoutSession respondWithTarget:self action:@selector(handleSetLanguage:)],
    /** HTTP verb: POST; path: /wda/system/advertising-id/reset; request schema: query {dryRun?:bool}; response schema: {ok,dryRun,durationMs}; error codes: 404 nav failure; capability token: system.advertising-id.reset */
    [[FBRoute POST:@"/wda/system/advertising-id/reset"].withoutSession respondWithTarget:self action:@selector(handleResetAdvertisingId:)],
    /** HTTP verb: POST; path: /wda/system/cellular/data-reset; request schema: query {dryRun?:bool}; response schema: {ok,dryRun,durationMs}; error codes: 404 nav failure; capability token: system.cellular.data-reset */
    [[FBRoute POST:@"/wda/system/cellular/data-reset"].withoutSession respondWithTarget:self action:@selector(handleResetCellularData:)],
    /** HTTP verb: POST; path: /wda/system/photos-permission/grant; request schema: {access?:"full"|"add-only"|"none"}; response schema: {ok,grantedAccess,dryRun,durationMs}; error codes: 400 invalid access, 501 app not in privacy list, 404 radio not found; capability token: system.photos-permission.grant */
    [[FBRoute POST:@"/wda/system/photos-permission/grant"].withoutSession respondWithTarget:self action:@selector(handlePhotosPermissionGrant:)],
  ];
}

+ (id<FBResponsePayload>)errorResponseWith:(NSError *)error startedAt:(NSDate *)startedAt path:(NSArray *)path code:(NSInteger)code
{
  NSMutableDictionary *body = [@{@"ok": @NO, @"error": error.localizedDescription ?: @"unknown", @"navigatedPath": path ?: @[], @"durationMs": @(TTSysMs(startedAt))} mutableCopy];
  if (error.userInfo[@"missingLabel"]) body[@"missingLabel"] = error.userInfo[@"missingLabel"];
  return [[FBResponseJSONPayload alloc] initWithDictionary:body httpStatusCode:code];
}

+ (id<FBResponsePayload>)handleSetMotionReduce:(FBRouteRequest *)request
{
  BOOL enabled = [request.arguments[@"enabled"] boolValue]; NSDate *s = [NSDate date]; NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance;
  if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"Accessibility", @"Motion"] error:&e] || ![nav setToggle:@"Reduce Motion" state:enabled error:&e]) return [self errorResponseWith:e startedAt:s path:@[@"Accessibility", @"Motion", @"Reduce Motion"] code:kHTTPStatusCodeNotFound];
  FBLogInfo(@"system.motion.reduce enabled=%d durationMs=%ld", enabled, (long)TTSysMs(s));
  return FBResponseWithObject(@{@"ok": @YES, @"navigatedPath": @[@"Accessibility", @"Motion", @"Reduce Motion"], @"finalState": enabled ? @"on" : @"off", @"dryRun": @NO, @"durationMs": @(TTSysMs(s))});
}

+ (id<FBResponsePayload>)handleResetAllSettings:(FBRouteRequest *)request
{
  BOOL dry = TTDryRun(request); NSDate *s = [NSDate date]; NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance;
  if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"General", @"Transfer or Reset iPhone", @"Reset"] error:&e]) return [self errorResponseWith:e startedAt:s path:@[@"General", @"Transfer or Reset iPhone", @"Reset"] code:kHTTPStatusCodeNotFound];
  if (!dry) { [nav tapButton:@"Reset All Settings" error:&e]; [nav tapButton:@"Reset All Settings" error:nil]; FBLogWarn(@"system.reset-all-settings executed durationMs=%ld", (long)TTSysMs(s)); }
  return FBResponseWithObject(@{@"ok": @YES, @"dryRun": @(dry), @"navigatedPath": @[@"General", @"Transfer or Reset iPhone", @"Reset", @"Reset All Settings"], @"durationMs": @(TTSysMs(s))});
}

+ (id<FBResponsePayload>)handleSetLanguage:(FBRouteRequest *)request
{
  NSString *language = request.arguments[@"language"]; if (0 == language.length) return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"language is required" traceback:nil]);
  BOOL dry = TTDryRun(request); NSDate *s = [NSDate date]; NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance;
  if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"General", @"Language & Region", @"iPhone Language"] error:&e]) return [self errorResponseWith:e startedAt:s path:@[@"General", @"Language & Region", @"iPhone Language"] code:kHTTPStatusCodeNotFound];
  if (!dry) { [nav tapButton:language error:nil]; [nav tapButton:@"Change" error:nil]; }
  return FBResponseWithObject(@{@"ok": @YES, @"dryRun": @(dry), @"language": language, @"navigatedPath": @[@"General", @"Language & Region", @"iPhone Language"], @"durationMs": @(TTSysMs(s))});
}

+ (id<FBResponsePayload>)handleResetAdvertisingId:(FBRouteRequest *)request
{
  BOOL dry = TTDryRun(request); NSDate *s = [NSDate date]; NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance;
  if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"Privacy & Security", @"Tracking"] error:&e]) return [self errorResponseWith:e startedAt:s path:@[@"Privacy & Security", @"Tracking"] code:kHTTPStatusCodeNotFound];
  if (!dry) { [nav tapButton:@"Reset Advertising Identifier" error:&e]; [nav tapButton:@"Reset Identifier" error:nil]; }
  return FBResponseWithObject(@{@"ok": @YES, @"dryRun": @(dry), @"navigatedPath": @[@"Privacy & Security", @"Tracking"], @"durationMs": @(TTSysMs(s))});
}

+ (id<FBResponsePayload>)handleResetCellularData:(FBRouteRequest *)request
{
  BOOL dry = TTDryRun(request); NSDate *s = [NSDate date]; NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance;
  if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"Cellular"] error:&e]) return [self errorResponseWith:e startedAt:s path:@[@"Cellular"] code:kHTTPStatusCodeNotFound];
  if (!dry) { [nav tapButton:@"Reset Statistics" error:&e]; [nav tapButton:@"Reset Statistics" error:nil]; }
  return FBResponseWithObject(@{@"ok": @YES, @"dryRun": @(dry), @"navigatedPath": @[@"Cellular", @"Reset Statistics"], @"durationMs": @(TTSysMs(s))});
}

+ (id<FBResponsePayload>)handlePhotosPermissionGrant:(FBRouteRequest *)request
{
  NSString *access = request.arguments[@"access"] ?: @"full";
  if (![@[@"full", @"add-only", @"none"] containsObject:access]) return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"access must be full, add-only, or none" traceback:nil]);
  NSDate *s = [NSDate date]; NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance;
  if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"Privacy & Security", @"Photos"] error:&e]) return [self errorResponseWith:e startedAt:s path:@[@"Privacy & Security", @"Photos"] code:kHTTPStatusCodeNotFound];
  XCUIApplication *settings = nav.settingsApp;
  XCUIElement *row = [[settings.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS 'TrafficTitans' OR label CONTAINS 'WebDriverAgent' OR label CONTAINS 'Automation'"]] firstMatch];
  if (![row exists]) return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"app_not_in_privacy_list", @"hint": @"call /wda/photos/list first to trigger TCC registration", @"durationMs": @(TTSysMs(s))} httpStatusCode:kHTTPStatusCodeNotImplemented];
  [row tap]; [NSThread sleepForTimeInterval:0.4];
  NSString *target = [access isEqualToString:@"full"] ? @"Full Access" : ([access isEqualToString:@"add-only"] ? @"Add Photos Only" : @"None");
  XCUIElement *radio = [[settings.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", target]] firstMatch];
  if (![radio exists]) return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"radio_not_found", @"missingLabel": target, @"durationMs": @(TTSysMs(s))} httpStatusCode:kHTTPStatusCodeNotFound];
  [radio tap]; [nav dismissAnyAlerts];
  return FBResponseWithObject(@{@"ok": @YES, @"grantedAccess": access, @"dryRun": @NO, @"navigatedPath": @[@"Privacy & Security", @"Photos", target], @"durationMs": @(TTSysMs(s))});
}
@end
