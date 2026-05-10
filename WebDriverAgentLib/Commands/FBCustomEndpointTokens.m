/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCustomEndpointTokens.h"

NSArray<NSString *> *FBCustomEndpointTokensList(void)
{
  static NSArray<NSString *> *tokens;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    tokens = @[
      @"photos.import",
      @"photos.import-batch",
      @"photos.clear",
      @"photos.list",
    ];
  });
  return tokens;
}
