/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBWifiCommands.h"
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
static NSInteger TTWifiMs(NSDate *s) { return (NSInteger)([[NSDate date] timeIntervalSinceDate:s] * 1000); }
static NSString *TTWifiQuery(FBRouteRequest *request, NSString *name) { NSURLComponents *c = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO]; for (NSURLQueryItem *i in c.queryItems) if ([i.name isEqualToString:name]) return i.value; return nil; }
@implementation FBWifiCommands
+ (NSArray *)routes
{
  return @[
    /** HTTP verb: POST; path: /wda/wifi/connect; request schema: {ssid,password?,security?:"wpa2"|"wpa3"|"open"}; response schema: {ok,strategy,ssid,security,durationMs}; error codes: 400/404 nav failure; capability token: wifi.connect */
    [[FBRoute POST:@"/wda/wifi/connect"].withoutSession respondWithTarget:self action:@selector(handleWifiConnect:)],
    /** HTTP verb: POST; path: /wda/wifi/disconnect; request schema: query {ssid?:string}; response schema: {ok,strategy,ssid,durationMs}; error codes: 404 target missing; capability token: wifi.disconnect */
    [[FBRoute POST:@"/wda/wifi/disconnect"].withoutSession respondWithTarget:self action:@selector(handleWifiDisconnect:)],
    /** HTTP verb: POST; path: /wda/wifi/forget; request schema: query {ssid:string}; response schema: {ok,strategy,ssid,durationMs}; error codes: 400/404 target missing; capability token: wifi.forget */
    [[FBRoute POST:@"/wda/wifi/forget"].withoutSession respondWithTarget:self action:@selector(handleWifiForget:)],
  ];
}
+ (id<FBResponsePayload>)err:(NSError *)e startedAt:(NSDate *)s { return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": e.localizedDescription ?: @"navigation failed", @"durationMs": @(TTWifiMs(s))} httpStatusCode:kHTTPStatusCodeNotFound]; }
+ (id<FBResponsePayload>)handleWifiConnect:(FBRouteRequest *)request
{
  NSString *ssid = request.arguments[@"ssid"]; NSString *password = request.arguments[@"password"]; NSString *security = request.arguments[@"security"] ?: @"wpa2";
  if (0 == ssid.length) return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"ssid is required" traceback:nil]);
  NSDate *s = [NSDate date]; NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance;
  if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"Wi-Fi"] error:&e]) return [self err:e startedAt:s];
  if (![nav tapButton:@"Other…" error:&e] && ![nav tapButton:@"Other..." error:&e] && ![nav tapButton:@"Other" error:&e]) return [self err:e startedAt:s];
  XCUIApplication *settings = nav.settingsApp; XCUIElement *name = [[settings.textFields matchingIdentifier:@"Name"] firstMatch]; if (![name exists]) return [self err:[NSError errorWithDomain:@"FBWifiCommands" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Name field not found"}] startedAt:s];
  [name tap]; [name typeText:ssid];
  if (![security isEqualToString:@"wpa2"]) { [nav tapButton:@"Security" error:nil]; NSString *choice = [security isEqualToString:@"wpa3"] ? @"WPA3" : @"None"; [nav tapButton:choice error:nil]; [nav tapButton:@"Other Network" error:nil]; }
  if (![security isEqualToString:@"open"] && password.length > 0) { XCUIElement *pf = [settings.secureTextFields firstMatch]; if ([pf exists]) { [pf tap]; [pf typeText:password]; } }
  if (![nav tapButton:@"Join" error:&e]) return [self err:e startedAt:s];
  [NSThread sleepForTimeInterval:1.5]; FBLogInfo(@"wifi.connect ssid=%@ security=%@ durationMs=%ld", ssid, security, (long)TTWifiMs(s));
  return FBResponseWithObject(@{@"ok": @YES, @"strategy": @"xcuiNav", @"ssid": ssid, @"security": security, @"durationMs": @(TTWifiMs(s))});
}
+ (id<FBResponsePayload>)handleWifiDisconnect:(FBRouteRequest *)request
{
  NSString *ssid = TTWifiQuery(request, @"ssid"); NSDate *s = [NSDate date]; NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance;
  if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"Wi-Fi"] error:&e]) return [self err:e startedAt:s];
  XCUIApplication *settings = nav.settingsApp; XCUIElement *cell = ssid.length ? [[settings.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", ssid]] firstMatch] : [settings.cells firstMatch];
  if (![cell exists]) return [self err:[NSError errorWithDomain:@"FBWifiCommands" code:2 userInfo:@{NSLocalizedDescriptionKey:@"target SSID cell not found"}] startedAt:s];
  [cell tap]; [NSThread sleepForTimeInterval:0.3]; if (![nav tapButton:@"Disconnect" error:&e]) return [self err:e startedAt:s];
  FBLogInfo(@"wifi.disconnect ssid=%@ durationMs=%ld", ssid ?: @"<current>", (long)TTWifiMs(s)); return FBResponseWithObject(@{@"ok": @YES, @"strategy": @"xcuiNav", @"ssid": ssid ?: NSNull.null, @"durationMs": @(TTWifiMs(s))});
}
+ (id<FBResponsePayload>)handleWifiForget:(FBRouteRequest *)request
{
  NSString *ssid = TTWifiQuery(request, @"ssid"); if (0 == ssid.length) return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"ssid is required" traceback:nil]);
  NSDate *s = [NSDate date]; NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance; if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"Wi-Fi"] error:&e]) return [self err:e startedAt:s];
  XCUIApplication *settings = nav.settingsApp; XCUIElement *cell = [[settings.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", ssid]] firstMatch]; if (![cell exists]) return [self err:[NSError errorWithDomain:@"FBWifiCommands" code:3 userInfo:@{NSLocalizedDescriptionKey:@"target SSID not found"}] startedAt:s];
  XCUIElement *info = [cell.buttons firstMatch]; if ([info exists]) [info tap]; else [cell tap]; [NSThread sleepForTimeInterval:0.4]; if (![nav tapButton:@"Forget This Network" error:&e]) return [self err:e startedAt:s]; [nav tapButton:@"Forget" error:nil];
  FBLogInfo(@"wifi.forget ssid=%@ durationMs=%ld", ssid, (long)TTWifiMs(s)); return FBResponseWithObject(@{@"ok": @YES, @"strategy": @"xcuiNav", @"ssid": ssid, @"durationMs": @(TTWifiMs(s))});
}
@end
