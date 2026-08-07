/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBPhotosBridge.h"

#import "FBCommandStatus.h"
#import "FBHTTPStatusCodes.h"
#import "FBResponseJSONPayload.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"

#if __has_include("WebDriverAgentLib-Swift.h")
#import "WebDriverAgentLib-Swift.h"
#elif __has_include(<WebDriverAgentLib/WebDriverAgentLib-Swift.h>)
#import <WebDriverAgentLib/WebDriverAgentLib-Swift.h>
#endif

@implementation FBPhotosBridge

+ (NSArray *)routes
{
  return @[
    [[FBRoute POST:@"/wda/photos/import"].withoutSession respondWithTarget:self action:@selector(handleImport:)],
    [[FBRoute POST:@"/wda/photos/importBatch"].withoutSession respondWithTarget:self action:@selector(handleImportBatch:)],
    [[FBRoute POST:@"/wda/photos/clear"].withoutSession respondWithTarget:self action:@selector(handleClear:)],
    [[FBRoute GET:@"/wda/photos/list"].withoutSession respondWithTarget:self action:@selector(handleList:)],
  ];
}

+ (id<FBResponsePayload>)handleImport:(FBRouteRequest *)request
{
  return [self responseFromCommand:^(void (^completion)(id _Nullable, NSError * _Nullable)) {
    [FBPhotosCommands importWithArguments:request.arguments completion:completion];
  }];
}

+ (id<FBResponsePayload>)handleImportBatch:(FBRouteRequest *)request
{
  return [self responseFromCommand:^(void (^completion)(id _Nullable, NSError * _Nullable)) {
    [FBPhotosCommands importBatchWithArguments:request.arguments completion:completion];
  }];
}

+ (id<FBResponsePayload>)handleClear:(FBRouteRequest *)request
{
  if (![self hasClearConfirmationInRequest:request]) {
    return [[FBResponseJSONPayload alloc] initWithDictionary:@{@"error": @"missing_confirm_marker"}
                                             httpStatusCode:kHTTPStatusCodePreconditionFailed];
  }

  return [self responseFromCommand:^(void (^completion)(id _Nullable, NSError * _Nullable)) {
    [FBPhotosCommands clearWithArguments:request.arguments completion:completion];
  }];
}

+ (id<FBResponsePayload>)handleList:(FBRouteRequest *)request
{
  return [self responseFromCommand:^(void (^completion)(id _Nullable, NSError * _Nullable)) {
    [FBPhotosCommands listWithUrl:request.URL completion:completion];
  }];
}

+ (id<FBResponsePayload>)responseFromCommand:(void (^)(void (^completion)(id _Nullable, NSError * _Nullable)))command
{
  __block id result = nil;
  __block NSError *commandError = nil;
  __block BOOL completedSynchronously = NO;

  command(^(id _Nullable commandResult, NSError * _Nullable error) {
    result = commandResult;
    commandError = error;
    completedSynchronously = YES;
  });

  // FBRoute only exposes a synchronous response payload in this WDA baseline,
  // and routes execute on the main queue. Swift Photos commands therefore avoid
  // permission prompts and use synchronous PhotoKit APIs. If a future command
  // becomes asynchronous, fail closed instead of blocking the main route queue.
  if (!completedSynchronously) {
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:@"Photo command did not complete synchronously" traceback:nil]);
  }

  if (nil != commandError) {
    if ([commandError.domain isEqualToString:@"FBPhotoListRequestError"]) {
      return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:commandError.localizedDescription traceback:nil]);
    }
    return FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:commandError.localizedDescription traceback:nil]);
  }
  return FBResponseWithObject(result ?: @{});
}

+ (BOOL)hasClearConfirmationInRequest:(FBRouteRequest *)request
{
  // This WDA baseline does not expose HTTP headers on FBRouteRequest. The
  // locked wipe-confirm mechanism is the explicit confirmWipe marker in the
  // JSON body or query string. Legacy header-shaped body/query aliases are
  // rejected so clients cannot accidentally rely on stale header semantics.
  if ([request.arguments[@"confirmWipe"] boolValue]) {
    return YES;
  }
  NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
  for (NSURLQueryItem *item in components.queryItems) {
    if ([item.name isEqualToString:@"confirmWipe"] && [item.value.lowercaseString isEqualToString:@"true"]) {
      return YES;
    }
  }
  return NO;
}

@end
