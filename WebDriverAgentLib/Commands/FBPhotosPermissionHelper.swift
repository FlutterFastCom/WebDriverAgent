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
    // WDA 11.4.3 routes are synchronous and run on the main queue, so these
    // endpoints do not trigger a PhotoKit permission prompt. Callers must
    // pre-grant Photos access; .notDetermined is treated as unsupported.
    if #available(iOS 14, *) {
      let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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
