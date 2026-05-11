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
      @"source.budgeted",
      @"source.per-app",
      @"tap.predicate",
      @"foreground.cached",
      @"launch.and-wait",
      @"apps.cleardata",
      @"network.airplane.toggle",
      @"keyboard.paste",
      @"system.reset-all-settings",
      @"system.motion.reduce",
      @"system.language.set",
      @"keyboard.autocorrect.set",
      @"keyboard.autocapitalize.set",
      @"keyboard.locale.set",
      @"system.advertising-id.reset",
      @"system.cellular.data-reset",
      @"system.photos-permission.grant",
      @"system.auto-lock.set",
      @"wifi.connect",
      @"wifi.disconnect",
      @"wifi.forget",
      @"apps.installed.list",
      @"apps.uninstall",
      @"apps.install-from-url",
      @"keyboard.type-with-delay",
      @"touch.swipe-bezier",
      @"keyboard.clear-field",
    ];
  });
  return tokens;
}
