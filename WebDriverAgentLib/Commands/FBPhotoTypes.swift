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

struct FBPhotoReferencePreview {
  let jpegData: Data
  let pixelWidth: Int
  let pixelHeight: Int
}

struct FBPhotoReferenceAsset {
  let asset: PHAsset
  let preview: FBPhotoReferencePreview
}

struct FBExactPhotoReferenceSnapshot {
  let assets: [FBPhotoReferenceAsset]
  let libraryInstanceId: UUID
  let changeSequence: UInt64
  let totalCount: Int
}

enum FBPhotoReferenceError: LocalizedError {
  case insufficientAssets
  case unsupportedMediaType
  case previewUnavailable
  case previewTooLarge
  case aggregateTooLarge
  case responseTooLarge

  var errorDescription: String? {
    switch self {
    case .insufficientAssets: return "insufficient_assets"
    case .unsupportedMediaType: return "unsupported_media_type"
    case .previewUnavailable: return "preview_unavailable"
    case .previewTooLarge: return "preview_too_large"
    case .aggregateTooLarge: return "aggregate_too_large"
    case .responseTooLarge: return "response_too_large"
    }
  }
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

  static func referenceList(snapshot: FBExactPhotoReferenceSnapshot) throws -> NSDictionary {
    guard (1...9).contains(snapshot.assets.count),
          snapshot.totalCount >= snapshot.assets.count
    else {
      throw FBPhotoReferenceError.insufficientAssets
    }

    var identifiers = Set<String>()
    var aggregateByteCount = 0
    var assets: [NSDictionary] = []
    assets.reserveCapacity(snapshot.assets.count)

    for referenceAsset in snapshot.assets {
      let asset = referenceAsset.asset
      let identifier = asset.localIdentifier
      guard !identifier.isEmpty, identifiers.insert(identifier).inserted else {
        throw FBPhotoReferenceError.insufficientAssets
      }

      let mediaType = mediaTypeString(asset.mediaType)
      guard mediaType == "image" || mediaType == "video" else {
        throw FBPhotoReferenceError.unsupportedMediaType
      }

      let preview = referenceAsset.preview
      guard preview.pixelWidth > 0,
            preview.pixelHeight > 0,
            max(preview.pixelWidth, preview.pixelHeight) <= 192
      else {
        throw FBPhotoReferenceError.previewUnavailable
      }
      guard !preview.jpegData.isEmpty, preview.jpegData.count <= 7_168 else {
        throw FBPhotoReferenceError.previewTooLarge
      }
      let (nextAggregate, overflow) = aggregateByteCount.addingReportingOverflow(preview.jpegData.count)
      guard !overflow, nextAggregate <= 64_512 else {
        throw FBPhotoReferenceError.aggregateTooLarge
      }
      aggregateByteCount = nextAggregate

      let jpegBase64 = preview.jpegData.base64EncodedString(options: [])
      guard let decodedJPEG = Data(base64Encoded: jpegBase64, options: []), decodedJPEG == preview.jpegData else {
        throw FBPhotoReferenceError.previewUnavailable
      }

      let reference: NSDictionary = [
        "mimeType": "image/jpeg",
        "jpegBase64": jpegBase64,
        "byteCount": preview.jpegData.count,
        "pixelWidth": preview.pixelWidth,
        "pixelHeight": preview.pixelHeight,
      ]
      let assetValue = NSMutableDictionary(dictionary: listItem(asset: asset))
      assetValue["reference"] = reference
      assets.append(assetValue)
    }

    let value: NSDictionary = [
      "referenceMode": "ordered_jpeg_v1",
      "assets": assets,
      "snapshot": snapshotValue(
        libraryInstanceId: snapshot.libraryInstanceId,
        changeSequence: snapshot.changeSequence,
        totalCount: snapshot.totalCount
      ),
    ]
    let envelope: NSDictionary = [
      "sessionId": "00000000-0000-0000-0000-000000000000",
      "value": value,
    ]
    guard let serialized = try? JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted]),
          serialized.count <= 98_304
    else {
      throw FBPhotoReferenceError.responseTooLarge
    }
    return value
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
