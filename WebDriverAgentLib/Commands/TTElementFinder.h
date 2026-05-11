// Copyright (c) 2025-present, TrafficTitan
// SPDX-License-Identifier: BSD-3-Clause

#import <Foundation/Foundation.h>
#import "XCUIApplication.h"
#import "XCUIElement.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Resilient element lookups for iOS-26-era Settings-style screens.
 *
 * All finders are case-insensitive and combine label AND identifier predicates,
 * so they survive marketing renames (e.g., "Cellular" -> "Mobile Service") AND
 * lowercase changes (e.g., "5 Minutes" -> "5 minutes") between iOS releases.
 *
 * iOS 17+ Settings uses UICollectionView-backed lists where:
 *  - XCUIElementTypeCell is a transparent container with an empty `label`
 *  - The visible row text lives on a child XCUIElementTypeButton or XCUIElementTypeStaticText
 *
 * findRowInApp:byText: explicitly excludes XCUIElementTypeStaticText to avoid
 * tapping a non-interactive label child whose text duplicates the surrounding
 * Cell's row text.
 */
@interface TTElementFinder : NSObject

/// Find a tappable row by visible text. Prefers XCUIElementTypeCell first, then
/// XCUIElementTypeButton. Explicitly EXCLUDES XCUIElementTypeStaticText (non-tappable).
/// Match is case-insensitive across BOTH `label` (visible text) AND `identifier`
/// (stable accessibility id, e.g. `com.apple.settings.cellular`).
+ (nullable XCUIElement *)findRowInApp:(XCUIApplication *)app byText:(NSString *)text;

/// Find a toggle by text. XCUIElementTypeSwitch only. Identifier-first match
/// (Switches typically expose a stable accessibility id; label may be empty).
+ (nullable XCUIElement *)findToggleInApp:(XCUIApplication *)app byText:(NSString *)text;

/// Find a button by text. XCUIElementTypeButton only. Case-insensitive
/// label-or-identifier match.
+ (nullable XCUIElement *)findButtonInApp:(XCUIApplication *)app byText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
