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

@objc enum FBPhotoMediaType: Int {
  case image
  case video

  init?(rawString: String) {
    switch rawString {
    case "image": self = .image
    case "video": self = .video
    default: return nil
    }
  }

  var responseString: String {
    switch self {
    case .image: return "image"
    case .video: return "video"
    }
  }

  var assetResourceType: PHAssetResourceType {
    switch self {
    case .image: return .photo
    case .video: return .video
    }
  }
}

struct FBPhotoImportItem {
  let data: Data
  let byteCount: Int
  let mediaType: FBPhotoMediaType
  let uti: String?
}

enum FBPhotosCommandError: LocalizedError {
  case invalidData
  case invalidItems
  case invalidMediaType
  case permissionDenied
  case assetCreationFailed

  var errorDescription: String? {
    switch self {
    case .invalidData: return "Photo import data must be a base64 string"
    case .invalidItems: return "Photo importBatch items must be an array"
    case .invalidMediaType: return "mediaType must be image or video"
    case .permissionDenied: return "Photo library access was denied"
    case .assetCreationFailed: return "PhotoKit did not return an asset identifier"
    }
  }
}

enum FBPhotoResponseFactory {
  static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static func importResult(assetIdentifier: String, durationMs: Int) -> NSDictionary {
    return [
      "assetIdentifier": assetIdentifier,
      "durationMs": durationMs,
    ]
  }

  static func listItem(asset: PHAsset) -> NSDictionary {
    return [
      "assetIdentifier": asset.localIdentifier,
      "mediaType": mediaTypeString(asset.mediaType),
      "createdAt": asset.creationDate.map { isoFormatter.string(from: $0) } ?? NSNull(),
      "pixelWidth": asset.pixelWidth,
      "pixelHeight": asset.pixelHeight,
    ]
  }

  static func exactList(assets: [NSDictionary], snapshot: FBExactPhotoSnapshot) -> NSDictionary {
    return [
      "assets": assets,
      "snapshot": snapshotValue(
        libraryInstanceId: snapshot.libraryInstanceId,
        changeSequence: snapshot.changeSequence,
        totalCount: snapshot.totalCount
      ),
    ]
  }

  static func snapshotValue(
    libraryInstanceId: UUID,
    changeSequence: UInt64,
    totalCount: Int
  ) -> NSDictionary {
    return [
      "libraryInstanceId": libraryInstanceId.uuidString,
      "changeSequence": String(changeSequence),
      "order": "tiktok_recent_grid_v1",
      "totalCount": totalCount,
    ]
  }

  private static func mediaTypeString(_ mediaType: PHAssetMediaType) -> String {
    switch mediaType {
    case .image: return "image"
    case .video: return "video"
    default: return "unknown"
    }
  }
}
#endif
