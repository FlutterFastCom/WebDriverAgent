/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBForegroundTracker.h"

#import <UIKit/UIKit.h>

#import "FBLogger.h"
#import "XCUIApplication.h"
#import "XCUIApplication+FBHelpers.h"

@interface FBForegroundTracker ()

@property (nonatomic, copy, readwrite, nullable) NSString *currentBundleId;
@property (nonatomic, copy, readwrite, nullable) NSDate *lastChangedAt;
@property (nonatomic, assign) NSUInteger observerEventCount;
@property (nonatomic, strong, nullable) NSTimer *fallbackArmTimer;
@property (nonatomic, strong, nullable) NSTimer *pollTimer;

@end

@implementation FBForegroundTracker

+ (instancetype)sharedInstance
{
  static FBForegroundTracker *instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [FBForegroundTracker new];
    [instance startObserving];
  });
  return instance;
}

- (void)startObserving
{
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(handleForegroundSignal:) name:@"XCUIApplicationActivationDidChangeNotification" object:nil];
  [center addObserver:self selector:@selector(handleForegroundSignal:) name:UIApplicationDidBecomeActiveNotification object:nil];

  __weak typeof(self) weakSelf = self;
  self.fallbackArmTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:NO block:^(NSTimer *timer) {
    typeof(self) strongSelf = weakSelf;
    if (nil == strongSelf || strongSelf.observerEventCount > 0) {
      return;
    }
    FBLogInfo(@"FBForegroundTracker: observer silence; engaging 1s poll fallback");
    strongSelf.pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *pollTimer) {
      [strongSelf pollActiveBundleId];
    }];
  }];
  [self pollActiveBundleId];
}

- (void)handleForegroundSignal:(NSNotification *)notification
{
  self.observerEventCount++;
  [self pollActiveBundleId];
}

- (void)pollActiveBundleId
{
  XCUIApplication *activeApp = XCUIApplication.fb_activeApplication;
  [self updateBundleId:activeApp.bundleID];
}

- (void)updateBundleId:(nullable NSString *)bundleId
{
  if (0 == bundleId.length || [bundleId isEqualToString:self.currentBundleId]) {
    return;
  }
  self.currentBundleId = bundleId;
  self.lastChangedAt = [NSDate date];
  FBLogVerbose(@"FBForegroundTracker: foreground=%@", bundleId);
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self.fallbackArmTimer invalidate];
  [self.pollTimer invalidate];
}

@end
