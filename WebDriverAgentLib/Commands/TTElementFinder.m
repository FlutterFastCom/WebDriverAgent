// Copyright (c) 2025-present, TrafficTitan
// SPDX-License-Identifier: BSD-3-Clause

#import "TTElementFinder.h"
#import "XCUIElementQuery.h"

@implementation TTElementFinder

+ (nullable XCUIElement *)findRowInApp:(XCUIApplication *)app byText:(NSString *)text
{
  if (text.length == 0) { return nil; }

  // Combined predicate: case-insensitive label OR identifier match.
  // The same predicate is reused for both Cell and Button scans -- only the
  // element-type query changes between attempts.
  NSPredicate *p = [NSPredicate predicateWithFormat:
                    @"label CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
                    text, text];

  // 1) Prefer Cell. On iOS <= 16 the row label is on the cell itself.
  XCUIElement *cell = [[app.cells matchingPredicate:p] firstMatch];
  if ([cell exists]) { return cell; }

  // 2) Fall back to Button. On iOS 17+ the row's visible text lives on a
  //    child Button inside a transparent Cell.
  XCUIElement *button = [[app.buttons matchingPredicate:p] firstMatch];
  if ([button exists]) { return button; }

  // 3) Explicitly DO NOT return XCUIElementTypeStaticText hits. StaticText
  //    is non-interactive -- tapping it does not toggle the row's selection
  //    state.
  return nil;
}

+ (nullable XCUIElement *)findToggleInApp:(XCUIApplication *)app byText:(NSString *)text
{
  if (text.length == 0) { return nil; }
  NSPredicate *p = [NSPredicate predicateWithFormat:
                    @"identifier CONTAINS[c] %@ OR label CONTAINS[c] %@",
                    text, text];
  XCUIElement *sw = [[app.switches matchingPredicate:p] firstMatch];
  return [sw exists] ? sw : nil;
}

+ (nullable XCUIElement *)findButtonInApp:(XCUIApplication *)app byText:(NSString *)text
{
  if (text.length == 0) { return nil; }
  NSPredicate *p = [NSPredicate predicateWithFormat:
                    @"label CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
                    text, text];
  XCUIElement *btn = [[app.buttons matchingPredicate:p] firstMatch];
  return [btn exists] ? btn : nil;
}

@end
