/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBRouteRequest-Private.h"

static NSString *const FBRouteRequestRedactedValue = @"<redacted>";

static BOOL FBRouteRequestShouldRedactKey(id key)
{
  if (![key isKindOfClass:NSString.class]) {
    return NO;
  }
  NSString *normalizedKey = [(NSString *)key lowercaseString];
  return [normalizedKey isEqualToString:@"data"]
    || [normalizedKey isEqualToString:@"fileurl"]
    || [normalizedKey isEqualToString:@"file_url"];
}

static id FBRouteRequestRedactedObject(id object);

static BOOL FBRouteRequestLooksLikeLargeBase64(NSString *value)
{
  if (value.length < 1024) {
    return NO;
  }
  static NSCharacterSet *allowedCharacters;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    allowedCharacters = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=\r\n"].invertedSet;
  });
  return [value rangeOfCharacterFromSet:allowedCharacters].location == NSNotFound;
}

static id FBRouteRequestRedactedString(NSString *value)
{
  if ([value hasPrefix:@"file://"] || FBRouteRequestLooksLikeLargeBase64(value)) {
    return FBRouteRequestRedactedValue;
  }
  return value;
}

static NSURL *FBRouteRequestRedactedURL(NSURL *URL)
{
  if (nil == URL) {
    return nil;
  }

  NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
  if (nil == components) {
    return URL;
  }

  NSArray<NSURLQueryItem *> *queryItems = components.queryItems;
  if (0 == queryItems.count) {
    return URL;
  }

  NSMutableArray<NSURLQueryItem *> *safeQueryItems = [NSMutableArray arrayWithCapacity:queryItems.count];
  for (NSURLQueryItem *item in queryItems) {
    NSString *safeValue = item.value;
    if (FBRouteRequestShouldRedactKey(item.name) ||
        (nil != safeValue && ![FBRouteRequestRedactedString(safeValue) isEqual:safeValue])) {
      safeValue = FBRouteRequestRedactedValue;
    }
    [safeQueryItems addObject:[NSURLQueryItem queryItemWithName:item.name value:safeValue]];
  }
  components.queryItems = safeQueryItems;
  return components.URL ?: URL;
}

static NSDictionary *FBRouteRequestRedactedDictionary(NSDictionary *dictionary)
{
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];
  [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
    result[key] = FBRouteRequestShouldRedactKey(key)
      ? FBRouteRequestRedactedValue
      : FBRouteRequestRedactedObject(value);
  }];
  return result.copy;
}

static NSArray *FBRouteRequestRedactedArray(NSArray *array)
{
  NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
  for (id item in array) {
    [result addObject:FBRouteRequestRedactedObject(item) ?: NSNull.null];
  }
  return result.copy;
}

static id FBRouteRequestRedactedObject(id object)
{
  if ([object isKindOfClass:NSDictionary.class]) {
    return FBRouteRequestRedactedDictionary((NSDictionary *)object);
  }
  if ([object isKindOfClass:NSArray.class]) {
    return FBRouteRequestRedactedArray((NSArray *)object);
  }
  if ([object isKindOfClass:NSString.class]) {
    return FBRouteRequestRedactedString((NSString *)object);
  }
  return object;
}

@implementation FBRouteRequest

+ (instancetype)routeRequestWithURL:(NSURL *)URL parameters:(NSDictionary *)parameters arguments:(NSDictionary *)arguments
{
  FBRouteRequest *request = [self.class new];
  request.URL = URL;
  request.parameters = parameters;
  request.arguments = arguments;
  return request;
}

- (NSString *)description
{
  NSURL *safeURL = FBRouteRequestRedactedURL(self.URL);
  NSDictionary *safeParameters = FBRouteRequestRedactedDictionary(self.parameters ?: @{});
  NSDictionary *safeArguments = FBRouteRequestRedactedDictionary(self.arguments ?: @{});
  return [NSString stringWithFormat:
    @"Request URL %@ | Params %@ | Arguments %@",
    safeURL,
    safeParameters,
    safeArguments
  ];
}

@end
