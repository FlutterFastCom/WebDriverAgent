/** Copyright (c) 2015-present, Facebook, Inc. */
#import "FBSettingsAppNavigator.h"
#import "FBLogger.h"
#import "TTElementFinder.h"
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

// bugfix-07 (2026-05-11): Option C — terminate + relaunch instead of back-button-loop.
// The previous back-button matcher whitelist drifted on iOS 17+ (Accessibility,
// Display & Brightness, etc. become parent-page labels never enumerated). Inclusive
// alternatives (any-labeled-button) match Edit/search buttons on root → wrong tap.
// Cold-relaunch is locale-independent, iOS-version-stable, and guarantees clean root.
- (BOOL)launchSettings:(NSError **)error
{
  XCUIApplication *settings = self.settingsApp;
  if (settings.state == XCUIApplicationStateRunningForeground) {
    [settings terminate];
    [NSThread sleepForTimeInterval:0.5];
  }
  [settings launch];
  [NSThread sleepForTimeInterval:0.8];
  [self dismissAnyAlerts];
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

    // Strategy 1: TTElementFinder handles the iOS-26 reality --
    //  - tries XCUIElementTypeCell first (iOS <= 16), then XCUIElementTypeButton (iOS 17+)
    //  - matches label CONTAINS[c] OR identifier CONTAINS[c]
    //  - excludes XCUIElementTypeStaticText (non-interactive label children)
    // Callers can pass either a marketing label (e.g., "Cellular") OR a
    // stable accessibility id (e.g., "com.apple.settings.cellular") -- both
    // resolve to the same row when present in the tree.
    XCUIElement *target = [TTElementFinder findRowInApp:settings byText:label];

    // Strategy 2: scroll-and-retry up to 8x for lazy/virtualized rows.
    // iOS 26.1 Settings.app uses UICollectionView-backed lists where off-screen
    // rows are not in the accessibility tree until scrolled into view.
    NSUInteger maxScrolls = 8;
    XCUIElement *scrollContainer = [self preferredScrollContainerIn:settings];
    for (NSUInteger i = 0; i < maxScrolls && ![target exists]; i++) {
      [scrollContainer swipeUp];
      [NSThread sleepForTimeInterval:0.35];
      [self dismissAnyAlerts];
      target = [TTElementFinder findRowInApp:settings byText:label];
    }

    if (![target exists]) {
      if (error) *error = TTNavError(2, [NSString stringWithFormat:@"label not found: %@", label], @{@"missingLabel": label});
      FBLogWarn(@"FBSettingsAppNavigator label_not_found=%@", label);
      return NO;
    }
    [target tap];
    [NSThread sleepForTimeInterval:0.45];
  }
  return YES;
}

// Explicit scroll-container preference. iOS 26.1 Settings.app uses
// XCUIElementTypeCollectionView (UICollectionView migration); fall back through
// scrollViews and finally the window root.
- (XCUIElement *)preferredScrollContainerIn:(XCUIApplication *)settings
{
  XCUIElement *collection = [settings.collectionViews firstMatch];
  if ([collection exists]) { return collection; }
  XCUIElement *scroll = [settings.scrollViews firstMatch];
  if ([scroll exists]) { return scroll; }
  return [settings.windows firstMatch];
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
