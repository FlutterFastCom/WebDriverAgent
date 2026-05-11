/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBAppsMgmtCommands.h"
#import "FBCommandStatus.h"
#import "FBHTTPStatusCodes.h"
#import "FBLogger.h"
#import "FBResponseJSONPayload.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "XCUIApplication.h"
static NSInteger TTAppsMs(NSDate *s) { return (NSInteger)([[NSDate date] timeIntervalSinceDate:s] * 1000); }
@implementation FBAppsMgmtCommands
+ (NSArray *)routes
{
  return @[
    /** HTTP verb: GET; path: /wda/apps/installed; request schema: none; response schema: {strategy:"privateApi",apps,count,durationMs}|{strategy:"needs_host_query",reason,durationMs}; error codes: none expected; capability token: apps.installed.list */
    [[FBRoute GET:@"/wda/apps/installed"].withoutSession respondWithTarget:self action:@selector(handleListInstalled:)],
    /** HTTP verb: POST; path: /wda/apps/uninstall/:bundleId; request schema: path {bundleId}; response schema: {ok,strategy,bundleId,durationMs}; error codes: 400/500; capability token: apps.uninstall */
    [[FBRoute POST:@"/wda/apps/uninstall/:bundleId"].withoutSession respondWithTarget:self action:@selector(handleUninstall:)],
    /** HTTP verb: POST; path: /wda/apps/install-from-url; request schema: {url,bundleId}; response schema: {strategy:"needs_host_install",acceptedUrl,urlHost,bundleId,durationMs}; error codes: 400; capability token: apps.install-from-url */
    [[FBRoute POST:@"/wda/apps/install-from-url"].withoutSession respondWithTarget:self action:@selector(handleInstallFromUrl:)],
  ];
}
+ (id<FBResponsePayload>)handleListInstalled:(FBRouteRequest *)request
{
  NSDate *s = [NSDate date]; Class cls = NSClassFromString(@"LSApplicationWorkspace"); id workspace = cls ? [cls performSelector:@selector(defaultWorkspace)] : nil; SEL sel = NSSelectorFromString(@"allInstalledApplications");
  if (workspace && [workspace respondsToSelector:sel]) { @try { NSMethodSignature *sig = [workspace methodSignatureForSelector:sel]; NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig]; [inv setTarget:workspace]; [inv setSelector:sel]; [inv invoke]; __unsafe_unretained id apps = nil; [inv getReturnValue:&apps]; NSMutableArray *out = [NSMutableArray array]; for (id proxy in (NSArray *)apps) { NSString *bid = [proxy valueForKey:@"applicationIdentifier"] ?: [proxy valueForKey:@"bundleIdentifier"] ?: @""; [out addObject:@{@"bundleId": bid, @"displayName": [proxy valueForKey:@"localizedName"] ?: @"", @"version": [proxy valueForKey:@"shortVersionString"] ?: @"", @"type": [bid hasPrefix:@"com.apple."] ? @"system" : @"user"}]; } FBLogVerbose(@"apps.installed strategy=privateApi count=%lu durationMs=%ld", (unsigned long)out.count, (long)TTAppsMs(s)); return FBResponseWithObject(@{@"strategy": @"privateApi", @"apps": out, @"count": @(out.count), @"durationMs": @(TTAppsMs(s))}); } @catch (NSException *e) { FBLogWarn(@"apps.installed privateApi failed reason=%@", e.reason); } }
  return FBResponseWithObject(@{@"strategy": @"needs_host_query", @"reason": @"LSApplicationWorkspace selector unavailable; spawn pmd3 apps list", @"durationMs": @(TTAppsMs(s))});
}
+ (id<FBResponsePayload>)handleUninstall:(FBRouteRequest *)request
{
  NSString *bundleId = request.parameters[@"bundleId"]; if (0 == bundleId.length) return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"bundleId is required" traceback:nil]); NSDate *s = [NSDate date]; XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:bundleId];
  @try { if ([app respondsToSelector:@selector(uninstall)]) { [app performSelector:@selector(uninstall)]; } else { @throw [NSException exceptionWithName:@"Unsupported" reason:@"XCUIApplication uninstall selector unavailable" userInfo:nil]; } } @catch (NSException *e) { return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": @"uninstall_failed", @"reason": e.reason ?: @"unknown", @"durationMs": @(TTAppsMs(s))} httpStatusCode:kHTTPStatusCodeInternalServerError]; }
  FBLogInfo(@"apps.uninstall bundleId=%@ durationMs=%ld", bundleId, (long)TTAppsMs(s)); return FBResponseWithObject(@{@"ok": @YES, @"strategy": @"xcuiPublic", @"bundleId": bundleId, @"durationMs": @(TTAppsMs(s))});
}
+ (id<FBResponsePayload>)handleInstallFromUrl:(FBRouteRequest *)request
{
  NSString *url = request.arguments[@"url"]; NSString *bundleId = request.arguments[@"bundleId"]; if (0 == url.length || 0 == bundleId.length) return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"url and bundleId are required" traceback:nil]); NSDate *s = [NSDate date]; NSString *urlHost = [NSURL URLWithString:url].host ?: @"-"; FBLogInfo(@"apps.install-from-url bundleId=%@ urlHost=%@ durationMs=%ld", bundleId, urlHost, (long)TTAppsMs(s)); return FBResponseWithObject(@{@"strategy": @"needs_host_install", @"acceptedUrl": @YES, @"urlHost": urlHost, @"bundleId": bundleId, @"durationMs": @(TTAppsMs(s))});
}
@end
