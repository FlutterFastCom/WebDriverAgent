/** Copyright (c) 2015-present, Facebook, Inc. */
#import <Foundation/Foundation.h>
@class XCUIApplication;
NS_ASSUME_NONNULL_BEGIN
@interface FBSettingsAppNavigator : NSObject
+ (instancetype)sharedInstance;
- (XCUIApplication *)settingsApp;
- (BOOL)launchSettings:(NSError **)error;
- (BOOL)navigateToPath:(NSArray<NSString *> *)labels error:(NSError **)error;
- (BOOL)setToggle:(NSString *)label state:(BOOL)on error:(NSError **)error;
- (BOOL)tapButton:(NSString *)label error:(NSError **)error;
- (BOOL)dismissAnyAlerts;
@end
NS_ASSUME_NONNULL_END
