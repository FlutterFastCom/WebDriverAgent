/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

#if os(iOS)
import Photos

@objc(FBPhotosPermissionHelper)
final class FBPhotosPermissionHelper: NSObject {
  static func hasReadWriteAuthorization(allowLimited: Bool) -> Bool {
    // PATCH 2026-05-10: branch shipped with `.notDetermined → unsupported` semantics
    // (skipping requestAuthorization). Empirical test on iPhone 14 Pro / iOS 26.1 showed
    // bundle never appeared in Settings → Privacy & Security → Photos because
    // requestAuthorization was never called → no TCC registration.
    //
    // Fix: trigger requestAuthorization once on .notDetermined. iOS auto-denies for
    // XCTest test runners (no UI surface to show prompt) but the call REGISTERS the
    // bundle in the TCC database — TrafficTitans row then appears in Settings →
    // Privacy & Security → Photos. From there, EITHER user grants manually, OR our
    // /wda/system/photos-permission/grant endpoint (TIER 3b #21, F-WDA-FORK-EXTENSIONS)
    // auto-navigates Settings to tap Full Access. dispatch_semaphore wait runs on
    // DispatchQueue.global() (NOT main) per F-doc P0 invariant — avoids deadlocking
    // the WDA HTTP server.
    if #available(iOS 14, *) {
      var currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
      if currentStatus == .notDetermined {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
          PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            currentStatus = status
            semaphore.signal()
          }
        }
        _ = semaphore.wait(timeout: .now() + 5)
      }
      return currentStatus == .authorized || (allowLimited && currentStatus == .limited)
    }

    return PHPhotoLibrary.authorizationStatus() == .authorized
  }

  static func hasFullReadWriteAuthorization() -> Bool {
    return hasReadWriteAuthorization(allowLimited: false)
  }
}
#else
@objc(FBPhotosPermissionHelper)
final class FBPhotosPermissionHelper: NSObject {
  static func hasReadWriteAuthorization(allowLimited: Bool) -> Bool {
    return false
  }

  static func hasFullReadWriteAuthorization() -> Bool {
    return false
  }
}
#endif
