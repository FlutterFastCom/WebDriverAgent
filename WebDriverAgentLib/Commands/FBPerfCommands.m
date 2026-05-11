/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBPerfCommands.h"

#import "FBCommandStatus.h"
#import "FBForegroundTracker.h"
#import "FBHTTPStatusCodes.h"
#import "FBLogger.h"
#import "FBElementTypeTransformer.h"
#import "FBResponseJSONPayload.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "XCUIApplication.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"

static NSInteger FBDurationMsSince(NSDate *startedAt)
{
  return (NSInteger)([[NSDate date] timeIntervalSinceDate:startedAt] * 1000);
}

static NSString *FBISO8601StringFromDate(NSDate *date)
{
  static NSDateFormatter *formatter;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
  });
  return [formatter stringFromDate:date];
}

static NSDictionary *FBSnapshotDictionary(XCUIElement *element, NSDate *deadline, NSUInteger depth, NSUInteger *walkedCount, BOOL *partial)
{
  if (nil != deadline && [deadline timeIntervalSinceNow] <= 0) {
    if (partial) {
      *partial = YES;
    }
    return @{};
  }
  if (walkedCount) {
    (*walkedCount)++;
  }
  NSMutableDictionary *dict = [@{
    @"type": [FBElementTypeTransformer stringWithElementType:element.elementType] ?: @"XCUIElementTypeUnknown",
    @"label": element.label ?: @"",
    @"name": element.identifier ?: @"",
    @"value": element.value ?: @"",
    @"enabled": @([element isEnabled]),
    @"visible": @([element exists]),
    @"rect": @{
      @"x": @(element.frame.origin.x),
      @"y": @(element.frame.origin.y),
      @"width": @(element.frame.size.width),
      @"height": @(element.frame.size.height),
    },
  } mutableCopy];
  if (depth < 20) {
    NSMutableArray *children = [NSMutableArray array];
    for (XCUIElement *child in [element childrenMatchingType:XCUIElementTypeAny].allElementsBoundByIndex) {
      if (nil != deadline && [deadline timeIntervalSinceNow] <= 0) {
        if (partial) {
          *partial = YES;
        }
        break;
      }
      [children addObject:FBSnapshotDictionary(child, deadline, depth + 1, walkedCount, partial)];
    }
    dict[@"children"] = children;
  }
  return dict.copy;
}

static NSString *FBQueryParam(FBRouteRequest *request, NSString *name)
{
  NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
  for (NSURLQueryItem *item in components.queryItems) {
    if ([item.name isEqualToString:name]) {
      return item.value;
    }
  }
  return nil;
}

// Allowlist of top-level keypaths that XCElementSnapshot is KVC-compliant for.
// `name` is intentionally EXCLUDED -- the /source JSON `name` field is a synthetic
// presentation alias for `identifier`; using it in NSPredicate against the live
// snapshot throws NSUndefinedKeyException.
static NSSet<NSString *> *FBTapPredicateSupportedKeys(void)
{
  static NSSet *keys;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    keys = [NSSet setWithArray:@[
      @"label",
      @"value",
      @"title",
      @"placeholderValue",
      @"identifier",
    ]];
  });
  return keys;
}

// Validate that every keypath used in `predicate` is in the allowlist AND is a
// single (non-dotted) token. Returns nil on success, or a structured error dict
// on failure that the caller wraps in a 400 response.
//
// Implementation: walk the NSPredicate AST. NSPredicate decomposes to
// NSComparisonPredicate (leaf) and NSCompoundPredicate (AND/OR/NOT). Each leaf
// has leftExpression / rightExpression -- we inspect leftExpression.keyPath when
// the expression type is NSKeyPathExpressionType.
static NSDictionary *FBTapPredicateValidationError(NSPredicate *predicate)
{
  NSSet *allowed = FBTapPredicateSupportedKeys();
  NSMutableArray *bad = [NSMutableArray array];
  __block void (^walk)(NSPredicate *);
  walk = ^(NSPredicate *p) {
    if ([p isKindOfClass:[NSCompoundPredicate class]]) {
      for (NSPredicate *sub in ((NSCompoundPredicate *)p).subpredicates) {
        walk(sub);
      }
      return;
    }
    if (![p isKindOfClass:[NSComparisonPredicate class]]) { return; }
    NSComparisonPredicate *c = (NSComparisonPredicate *)p;
    for (NSExpression *expr in @[c.leftExpression, c.rightExpression]) {
      if (expr.expressionType != NSKeyPathExpressionType) { continue; }
      NSString *kp = expr.keyPath;
      // Reject nested keypaths outright (e.g., "children.label").
      // XCElementSnapshot doesn't expose nested KVC keypaths usable via predicate.
      if ([kp containsString:@"."]) {
        [bad addObject:kp];
        continue;
      }
      if (![allowed containsObject:kp]) {
        [bad addObject:kp];
      }
    }
  };
  walk(predicate);
  if (bad.count == 0) { return nil; }
  return @{
    @"error": @"unsupported_predicate_key",
    @"got": [bad firstObject] ?: @"(unknown)",
    @"allUnsupported": [bad copy],
    @"supported": [allowed.allObjects sortedArrayUsingSelector:@selector(compare:)],
    @"hint": @"XCElementSnapshot exposes only these KVC keys. The /source JSON `name` field is a synthetic presentation alias for `identifier` -- use `identifier` in predicates. Nested keypaths (e.g., `children.label`) are not supported."
  };
}

@implementation FBPerfCommands

+ (NSArray *)routes
{
  return @[
    /**
     * HTTP verb: GET
     * path: /wda/source
     * request schema: query { budget_ms?: number }
     * response schema: { value: object, partial: boolean, walkedNodeCount: number, durationMs: number }
     * error codes: 500 on snapshot failure
     * capability token: source.budgeted
     */
    [[FBRoute GET:@"/wda/source"].withoutSession respondWithTarget:self action:@selector(handleSourceBudgeted:)],
    /**
     * HTTP verb: GET
     * path: /wda/source/per-app
     * request schema: query { bundleId: string, budget_ms?: number, force?: "1"|"true"|"yes" }
     * response schema (200): { value: object, walkedNodeCount: number, partial: boolean, durationMs: number, budgetMs: number }
     * response schema (404 app_not_running): { error: "app_not_running", bundleId, durationMs }
     * response schema (400 target_not_foreground): { error: "target_not_foreground", requestedBundleId, foregroundBundleId, message, durationMs }
     * error codes: 400 missing bundleId, 404 app_not_running, 400 target_not_foreground
     * capability token: source.per-app
     */
    [[FBRoute GET:@"/wda/source/per-app"].withoutSession respondWithTarget:self action:@selector(handleSourcePerApp:)],
    /**
     * HTTP verb: POST
     * path: /wda/tap-by-predicate
     * request schema: { predicate: string, why?: string }
     * response schema: { tapped: true, durationMs: number }
     * error codes: 400 invalid predicate, 400 unsupported_predicate_key, 404 no match, 500 tap failure
     * capability token: tap.predicate
     */
    [[FBRoute POST:@"/wda/tap-by-predicate"].withoutSession respondWithTarget:self action:@selector(handleTapByPredicate:)],
    /**
     * HTTP verb: GET
     * path: /wda/foreground
     * request schema: none
     * response schema: { bundleId: string|null, since: string|null }
     * error codes: none expected
     * capability token: foreground.cached
     */
    [[FBRoute GET:@"/wda/foreground"].withoutSession respondWithTarget:self action:@selector(handleForegroundCached:)],
    /**
     * HTTP verb: POST
     * path: /wda/launch-and-wait
     * request schema: { bundleId: string, expectedForeground?: string, timeoutMs?: number }
     * response schema: { launched: boolean, foregroundReached: boolean, durationMs: number, finalBundleId: string|null }
     * error codes: 400 missing bundleId
     * capability token: launch.and-wait
     */
    [[FBRoute POST:@"/wda/launch-and-wait"].withoutSession respondWithTarget:self action:@selector(handleLaunchAndWait:)],
  ];
}

+ (id<FBResponsePayload>)handleSourceBudgeted:(FBRouteRequest *)request
{
  NSInteger budgetMs = [FBQueryParam(request, @"budget_ms") integerValue];
  if (budgetMs <= 0) {
    budgetMs = 5000;
  }
  NSDate *startedAt = [NSDate date];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:budgetMs / 1000.0];
  NSUInteger walked = 0;
  BOOL partial = NO;
  NSDictionary *tree = FBSnapshotDictionary(XCUIApplication.fb_activeApplication, deadline, 0, &walked, &partial);
  NSInteger durationMs = FBDurationMsSince(startedAt);
  FBLogVerbose(@"source.budgeted budgetMs=%ld walked=%lu partial=%d durationMs=%ld", (long)budgetMs, (unsigned long)walked, partial, (long)durationMs);
  return FBResponseWithObject(@{@"value": tree ?: @{}, @"partial": @(partial), @"walkedNodeCount": @(walked), @"durationMs": @(durationMs)});
}

+ (id<FBResponsePayload>)handleSourcePerApp:(FBRouteRequest *)request
{
  NSString *bundleId = FBQueryParam(request, @"bundleId");
  if (0 == bundleId.length) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"bundleId is required" traceback:nil]);
  }

  // Budget — default 5 s if caller didn't specify, capped at 30 s.
  NSInteger budgetMs = [FBQueryParam(request, @"budget_ms") integerValue];
  if (budgetMs <= 0) { budgetMs = 5000; }
  if (budgetMs > 30000) { budgetMs = 30000; }

  NSDate *startedAt = [NSDate date];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:budgetMs / 1000.0];

  XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:bundleId];

  // Fail fast if the target app isn't on the device / not running.
  if (![app exists]) {
    return [[FBResponseJSONPayload alloc]
            initWithDictionary:@{@"error": @"app_not_running",
                                 @"bundleId": bundleId,
                                 @"durationMs": @(FBDurationMsSince(startedAt))}
            httpStatusCode:kHTTPStatusCodeNotFound];
  }

  // Default behavior: refuse to walk a non-foreground app's tree unless caller
  // explicitly opts in with ?force=true. Cross-process accessibility queries
  // are extremely slow on iOS 26 and risk wedging the WDA route queue.
  NSString *forceParam = FBQueryParam(request, @"force");
  BOOL force = forceParam.length > 0 && [@[@"1", @"true", @"yes"] containsObject:forceParam.lowercaseString];
  if (!force) {
    // Use FBForegroundTracker.sharedInstance.currentBundleId — already cached in this file's
    // existing handleForegroundCached: pattern. Reliable, locale-stable, no XPC roundtrip.
    NSString *fgBundleId = FBForegroundTracker.sharedInstance.currentBundleId;
    if (fgBundleId && ![fgBundleId isEqualToString:bundleId]) {
      return [[FBResponseJSONPayload alloc]
              initWithDictionary:@{@"error": @"target_not_foreground",
                                   @"message": @"target app is not foregrounded; pass ?force=true to walk anyway (slow + risky on iOS 26.1)",
                                   @"requestedBundleId": bundleId,
                                   @"foregroundBundleId": fgBundleId,
                                   @"durationMs": @(FBDurationMsSince(startedAt))}
              httpStatusCode:kHTTPStatusCodeBadRequest];
    }
  }

  NSUInteger walked = 0;
  BOOL partial = NO;
  NSDictionary *tree = FBSnapshotDictionary(app, deadline, 0, &walked, &partial);
  NSInteger durationMs = FBDurationMsSince(startedAt);

  FBLogVerbose(@"source.per-app bundleId=%@ walked=%lu partial=%d durationMs=%ld",
               bundleId, (unsigned long)walked, partial, (long)durationMs);

  return FBResponseWithObject(@{@"value": tree ?: @{},
                                @"walkedNodeCount": @(walked),
                                @"partial": @(partial),
                                @"durationMs": @(durationMs),
                                @"budgetMs": @(budgetMs)});
}

+ (id<FBResponsePayload>)handleTapByPredicate:(FBRouteRequest *)request
{
  NSString *predicateString = request.arguments[@"predicate"];
  NSString *why = request.arguments[@"why"];
  if (0 == predicateString.length) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"predicate is required" traceback:nil]);
  }

  NSPredicate *predicate;
  @try {
    predicate = [NSPredicate predicateWithFormat:predicateString];
  } @catch (NSException *exception) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:
                                 [NSString stringWithFormat:@"invalid predicate: %@", exception.reason]
                                 traceback:nil]);
  }

  // Allowlist gate. Reject unsupported keys BEFORE attempting to evaluate the
  // predicate against XCElementSnapshot (which would throw NSUndefinedKeyException
  // and bubble up as a 500 with a framework traceback).
  NSDictionary *validationError = FBTapPredicateValidationError(predicate);
  if (validationError) {
    return [[FBResponseJSONPayload alloc]
            initWithDictionary:validationError
            httpStatusCode:kHTTPStatusCodeBadRequest];
  }

  NSDate *startedAt = [NSDate date];
  XCUIElement *element;
  @try {
    // Defense in depth: even after the allowlist gate, certain edge cases (future
    // iOS versions, exotic operator combinations) could still throw at evaluation
    // time. Catch them here rather than letting them bubble to a 500.
    element = [[XCUIApplication.fb_activeApplication descendantsMatchingType:XCUIElementTypeAny]
               elementMatchingPredicate:predicate];
  } @catch (NSException *exception) {
    FBLogWarn(@"tap.predicate evaluation_failed reason=%@", exception.reason);
    return [[FBResponseJSONPayload alloc]
            initWithDictionary:@{@"error": @"predicate_evaluation_failed",
                                 @"message": exception.reason ?: @"unknown",
                                 @"supported": [FBTapPredicateSupportedKeys().allObjects sortedArrayUsingSelector:@selector(compare:)],
                                 @"hint": @"The predicate parsed but failed to evaluate. This indicates the allowlist gate missed a case; please report."}
            httpStatusCode:kHTTPStatusCodeBadRequest];
  }

  if (![element exists]) {
    NSInteger durationMs = FBDurationMsSince(startedAt);
    FBLogVerbose(@"tap.predicate no_match why=%@ durationMs=%ld", why ?: @"-", (long)durationMs);
    return [[FBResponseJSONPayload alloc]
            initWithDictionary:@{@"error": @"no_match", @"durationMs": @(durationMs)}
            httpStatusCode:kHTTPStatusCodeNotFound];
  }

  // Tap can also throw (element disappeared between match and tap). Guard it too.
  @try {
    [element tap];
  } @catch (NSException *exception) {
    return [[FBResponseJSONPayload alloc]
            initWithDictionary:@{@"error": @"tap_failed",
                                 @"message": exception.reason ?: @"unknown",
                                 @"durationMs": @(FBDurationMsSince(startedAt))}
            httpStatusCode:kHTTPStatusCodeInternalServerError];
  }

  NSInteger durationMs = FBDurationMsSince(startedAt);
  FBLogVerbose(@"tap.predicate tapped why=%@ durationMs=%ld", why ?: @"-", (long)durationMs);
  return FBResponseWithObject(@{@"tapped": @YES, @"durationMs": @(durationMs)});
}

+ (id<FBResponsePayload>)handleForegroundCached:(FBRouteRequest *)request
{
  FBForegroundTracker *tracker = FBForegroundTracker.sharedInstance;
  return FBResponseWithObject(@{@"bundleId": tracker.currentBundleId ?: NSNull.null, @"since": tracker.lastChangedAt ? FBISO8601StringFromDate(tracker.lastChangedAt) : NSNull.null});
}

+ (id<FBResponsePayload>)handleLaunchAndWait:(FBRouteRequest *)request
{
  NSString *bundleId = request.arguments[@"bundleId"];
  if (0 == bundleId.length) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"bundleId is required" traceback:nil]);
  }
  NSString *target = [request.arguments[@"expectedForeground"] length] > 0 ? request.arguments[@"expectedForeground"] : bundleId;
  NSInteger timeoutMs = [request.arguments[@"timeoutMs"] integerValue];
  if (timeoutMs <= 0) {
    timeoutMs = 5000;
  }
  NSDate *startedAt = [NSDate date];
  XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:bundleId];
  [app launch];
  FBForegroundTracker *tracker = FBForegroundTracker.sharedInstance;
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutMs / 1000.0];
  BOOL reached = NO;
  while ([deadline timeIntervalSinceNow] > 0) {
    if ([tracker.currentBundleId isEqualToString:target]) {
      reached = YES;
      break;
    }
    [NSThread sleepForTimeInterval:0.1];
  }
  BOOL launched = app.state == XCUIApplicationStateRunningForeground || app.state == XCUIApplicationStateRunningBackground;
  NSInteger durationMs = FBDurationMsSince(startedAt);
  FBLogInfo(@"launch.and-wait bundleId=%@ target=%@ launched=%d foregroundReached=%d durationMs=%ld", bundleId, target, launched, reached, (long)durationMs);
  return FBResponseWithObject(@{@"launched": @(launched), @"foregroundReached": @(reached), @"durationMs": @(durationMs), @"finalBundleId": tracker.currentBundleId ?: NSNull.null});
}

@end
