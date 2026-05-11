/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBSettingsAppNavigator.h"
#import "FBLogger.h"
#import "XCUIApplication.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"

static NSError *TTNavError(NSInteger code, NSString *message, NSDictionary *extra)
{
  NSMutableDictionary *info = [@{NSLocalizedDescriptionKey: message ?: @"unknown"} mutableCopy];
  [info addEntriesFromDictionary:extra ?: @{}];
  return [NSError errorWithDomain:@"FBSettingsAppNavigator" code:code userInfo:info];
}

@implementation FBSettingsAppNavigator
+ (instancetype)sharedInstance
{
  static FBSettingsAppNavigator *instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{ instance = [FBSettingsAppNavigator new]; });
  return instance;
}

- (XCUIApplication *)settingsApp { return [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.Preferences"]; }

- (BOOL)launchSettings:(NSError **)error
{
  XCUIApplication *settings = self.settingsApp;
  [settings activate];
  [NSThread sleepForTimeInterval:0.8];
  for (NSUInteger i = 0; i < 8; i++) {
    [self dismissAnyAlerts];
    XCUIElement *back = [[settings.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label == 'Back' OR label BEGINSWITH 'Settings' OR label BEGINSWITH 'Wi-Fi' OR label BEGINSWITH 'General'"]] firstMatch];
    if (![back exists]) { break; }
    [back tap];
    [NSThread sleepForTimeInterval:0.25];
  }
  if (settings.state != XCUIApplicationStateRunningForeground) {
    if (error) *error = TTNavError(1, @"failed to launch Settings", nil);
    return NO;
  }
  return YES;
}

- (BOOL)navigateToPath:(NSArray<NSString *> *)labels error:(NSError **)error
{
  XCUIApplication *settings = self.settingsApp;
  for (NSString *label in labels) {
    [self dismissAnyAlerts];
    XCUIElement *cell = [[settings.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", label]] firstMatch];
    if (![cell exists]) {
      XCUIElement *scroll = [[settings.scrollViews firstMatch] exists] ? [settings.scrollViews firstMatch] : [settings.windows firstMatch];
      [scroll swipeUp];
      [NSThread sleepForTimeInterval:0.35];
      cell = [[settings.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", label]] firstMatch];
    }
    if (![cell exists]) {
      if (error) *error = TTNavError(2, [NSString stringWithFormat:@"label not found: %@", label], @{@"missingLabel": label});
      FBLogWarn(@"FBSettingsAppNavigator label_not_found=%@", label);
      return NO;
    }
    [cell tap];
    [NSThread sleepForTimeInterval:0.45];
  }
  return YES;
}

- (BOOL)setToggle:(NSString *)label state:(BOOL)on error:(NSError **)error
{
  XCUIApplication *settings = self.settingsApp;
  XCUIElement *toggle = [[settings.switches matchingIdentifier:label] firstMatch];
  if (![toggle exists]) {
    XCUIElement *cell = [[settings.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", label]] firstMatch];
    toggle = [cell.switches firstMatch];
  }
  if (![toggle exists]) {
    if (error) *error = TTNavError(3, [NSString stringWithFormat:@"toggle not found: %@", label], @{@"missingLabel": label});
    return NO;
  }
  BOOL current = [[toggle.value description] isEqualToString:@"1"];
  if (current != on) {
    [toggle tap];
    [NSThread sleepForTimeInterval:0.3];
  }
  return YES;
}

- (BOOL)tapButton:(NSString *)label error:(NSError **)error
{
  XCUIApplication *settings = self.settingsApp;
  XCUIElement *button = [[settings.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", label]] firstMatch];
  if (![button exists]) {
    XCUIElement *cell = [[settings.cells matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", label]] firstMatch];
    button = [cell.buttons firstMatch];
    if (![button exists] && [cell exists]) { button = cell; }
  }
  if (![button exists]) {
    if (error) *error = TTNavError(4, [NSString stringWithFormat:@"button not found: %@", label], @{@"missingLabel": label});
    return NO;
  }
  [button tap];
  [NSThread sleepForTimeInterval:0.4];
  return YES;
}

- (BOOL)dismissAnyAlerts
{
  XCUIApplication *settings = self.settingsApp;
  XCUIElement *alert = [settings.alerts firstMatch];
  if (![alert exists]) { return NO; }
  for (NSString *label in @[@"Cancel", @"Not Now", @"Later", @"OK", @"Dismiss"]) {
    XCUIElement *button = [[alert.buttons matchingIdentifier:label] firstMatch];
    if ([button exists]) {
      [button tap];
      FBLogInfo(@"FBSettingsAppNavigator dismissed alert via %@", label);
      return YES;
    }
  }
  FBLogWarn(@"FBSettingsAppNavigator blocked_by_unknown_alert");
  return NO;
}
@end
