/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Global Logger object that understands log levels
 */
@interface FBLogger : NSObject

/**
 Log to stdout.
 */
+ (void)log:(NSString *)message;
+ (void)logFmt:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 Log to stdout, only if WDA is Verbose
 */
+ (void)verboseLog:(NSString *)message;
+ (void)verboseLogFmt:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

@end

#ifndef FBLogVerbose
#define FBLogVerbose(format, ...) [FBLogger verboseLogFmt:(format), ##__VA_ARGS__]
#endif

#ifndef FBLogInfo
#define FBLogInfo(format, ...) [FBLogger logFmt:(format), ##__VA_ARGS__]
#endif

#ifndef FBLogWarn
#define FBLogWarn(format, ...) [FBLogger logFmt:(format), ##__VA_ARGS__]
#endif

#ifndef FBLogError
#define FBLogError(format, ...) [FBLogger logFmt:(format), ##__VA_ARGS__]
#endif

NS_ASSUME_NONNULL_END
