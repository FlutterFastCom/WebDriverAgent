/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBKeyboardSettingsCommands.h"
#import "FBCommandStatus.h"
#import "FBHTTPStatusCodes.h"
#import "FBResponseJSONPayload.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBSettingsAppNavigator.h"

static NSInteger TTKbdMs(NSDate *s) { return (NSInteger)([[NSDate date] timeIntervalSinceDate:s] * 1000); }
static BOOL TTKbdDry(FBRouteRequest *request) { NSURLComponents *c = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO]; for (NSURLQueryItem *i in c.queryItems) if ([i.name isEqualToString:@"dryRun"] && [i.value isEqualToString:@"true"]) return YES; return NO; }

@implementation FBKeyboardSettingsCommands
+ (NSArray *)routes
{
  return @[
    /** HTTP verb: POST; path: /wda/keyboard/autocorrect/set; request schema: {enabled:bool}; response schema: {ok,finalState,durationMs}; error codes: 404 nav failure; capability token: keyboard.autocorrect.set */
    [[FBRoute POST:@"/wda/keyboard/autocorrect/set"].withoutSession respondWithTarget:self action:@selector(handleSetAutocorrect:)],
    /** HTTP verb: POST; path: /wda/keyboard/autocapitalize/set; request schema: {enabled:bool}; response schema: {ok,finalState,durationMs}; error codes: 404 nav failure; capability token: keyboard.autocapitalize.set */
    [[FBRoute POST:@"/wda/keyboard/autocapitalize/set"].withoutSession respondWithTarget:self action:@selector(handleSetAutocapitalize:)],
    /** HTTP verb: POST; path: /wda/keyboard/locale/set; request schema: {locale:string}, query {dryRun?:bool}; response schema: {ok,dryRun,locale,durationMs}; error codes: 400/404; capability token: keyboard.locale.set */
    [[FBRoute POST:@"/wda/keyboard/locale/set"].withoutSession respondWithTarget:self action:@selector(handleSetKeyboardLocale:)],
  ];
}

+ (id<FBResponsePayload>)finishToggle:(NSString *)label enabled:(BOOL)enabled startedAt:(NSDate *)s
{
  NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance;
  if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"General", @"Keyboard"] error:&e] || ![nav setToggle:label state:enabled error:&e]) {
    return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": e.localizedDescription ?: @"navigation failed", @"durationMs": @(TTKbdMs(s))} httpStatusCode:kHTTPStatusCodeNotFound];
  }
  return FBResponseWithObject(@{@"ok": @YES, @"navigatedPath": @[@"General", @"Keyboard", label], @"finalState": enabled ? @"on" : @"off", @"durationMs": @(TTKbdMs(s))});
}

+ (id<FBResponsePayload>)handleSetAutocorrect:(FBRouteRequest *)request { return [self finishToggle:@"Auto-Correction" enabled:[request.arguments[@"enabled"] boolValue] startedAt:[NSDate date]]; }
+ (id<FBResponsePayload>)handleSetAutocapitalize:(FBRouteRequest *)request { return [self finishToggle:@"Auto-Capitalization" enabled:[request.arguments[@"enabled"] boolValue] startedAt:[NSDate date]]; }

+ (id<FBResponsePayload>)handleSetKeyboardLocale:(FBRouteRequest *)request
{
  NSString *locale = request.arguments[@"locale"]; if (0 == locale.length) return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"locale is required" traceback:nil]);
  BOOL dry = TTKbdDry(request); NSDate *s = [NSDate date]; NSError *e; FBSettingsAppNavigator *nav = FBSettingsAppNavigator.sharedInstance;
  if (![nav launchSettings:&e] || ![nav navigateToPath:@[@"General", @"Keyboard", @"Keyboards"] error:&e]) return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"ok": @NO, @"error": e.localizedDescription ?: @"navigation failed", @"durationMs": @(TTKbdMs(s))} httpStatusCode:kHTTPStatusCodeNotFound];
  if (!dry) { [nav tapButton:@"Add New Keyboard" error:nil]; [nav tapButton:locale error:nil]; }
  return FBResponseWithObject(@{@"ok": @YES, @"dryRun": @(dry), @"locale": locale, @"navigatedPath": @[@"General", @"Keyboard", @"Keyboards"], @"durationMs": @(TTKbdMs(s))});
}
@end
