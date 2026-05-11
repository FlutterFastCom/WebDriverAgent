/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBForegroundTracker : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, copy, readonly, nullable) NSString *currentBundleId;
@property (nonatomic, copy, readonly, nullable) NSDate *lastChangedAt;

@end

NS_ASSUME_NONNULL_END
