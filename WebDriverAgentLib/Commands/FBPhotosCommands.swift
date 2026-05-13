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
#endif

@objc(FBPhotosCommands)
final class FBPhotosCommands: NSObject {
  typealias Completion = (NSDictionary?, Error?) -> Void

  @objc(importWithArguments:completion:)
  static func `import`(arguments: NSDictionary, completion: @escaping Completion) {
    #if os(iOS)
    guard let item = importItem(from: arguments) else {
      completion(nil, FBPhotosCommandError.invalidData)
      return
    }
    importItem(item, completion: completion)
    #else
    completion(nil, NSError(domain: "FBPhotosCommands", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos endpoints are only supported on iOS"]))
    #endif
  }

  @objc(importBatchWithArguments:completion:)
  static func importBatch(arguments: NSDictionary, completion: @escaping Completion) {
    #if os(iOS)
    guard let rawItems = arguments["items"] as? [NSDictionary] else {
      completion(nil, FBPhotosCommandError.invalidItems)
      return
    }
    do {
      let items = try rawItems.map { rawItem -> FBPhotoImportItem in
        guard let item = importItem(from: rawItem) else {
          throw FBPhotosCommandError.invalidData
        }
        return item
      }
      importItems(items, completion: completion)
    } catch {
      completion(nil, error)
    }
    #else
    completion(nil, NSError(domain: "FBPhotosCommands", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos endpoints are only supported on iOS"]))
    #endif
  }

  @objc(clearWithArguments:completion:)
  static func clear(arguments: NSDictionary, completion: @escaping Completion) {
    #if os(iOS)
    let startedAt = Date()
    guard hasFullAuthorization() else {
      completion(nil, FBPhotosCommandError.permissionDenied)
      return
    }

    do {
      let assets = PHAsset.fetchAssets(with: nil)
      let deletedCount = assets.count
      try PHPhotoLibrary.shared().performChangesAndWait {
        PHAssetChangeRequest.deleteAssets(assets)
      }
      completion([
        "deletedCount": deletedCount,
        "durationMs": durationMs(since: startedAt),
      ], nil)
    } catch {
      completion(nil, error)
    }
    #else
    completion(nil, NSError(domain: "FBPhotosCommands", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos endpoints are only supported on iOS"]))
    #endif
  }

  @objc(listWithUrl:completion:)
  static func list(url: URL, completion: @escaping Completion) {
    #if os(iOS)
    let limit = parsedLimit(from: url)
    guard hasReadableAuthorization() else {
      completion(nil, FBPhotosCommandError.permissionDenied)
      return
    }

    let options = PHFetchOptions()
    options.fetchLimit = limit
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    let assets = PHAsset.fetchAssets(with: options)
    var results: [NSDictionary] = []
    results.reserveCapacity(min(limit, assets.count))
    assets.enumerateObjects { asset, _, _ in
      results.append(FBPhotoResponseFactory.listItem(asset: asset))
    }
    completion(["assets": results], nil)
    #else
    completion(nil, NSError(domain: "FBPhotosCommands", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos endpoints are only supported on iOS"]))
    #endif
  }
}

#if os(iOS)
private extension FBPhotosCommands {
  static func importItem(from arguments: NSDictionary) -> FBPhotoImportItem? {
    guard
      let base64 = arguments["data"] as? String,
      let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters])
    else {
      return nil
    }
    guard let rawMediaType = arguments["mediaType"] as? String,
          let mediaType = FBPhotoMediaType(rawString: rawMediaType) else {
      return nil
    }
    let uti = arguments["uti"] as? String
    return FBPhotoImportItem(data: data, byteCount: data.count, mediaType: mediaType, uti: uti)
  }

  static func importItem(_ item: FBPhotoImportItem, completion: @escaping Completion) {
    importItems([item]) { result, error in
      if let error = error {
        completion(nil, error)
        return
      }
      guard let results = result?["results"] as? [NSDictionary], let firstResult = results.first else {
        completion(nil, FBPhotosCommandError.assetCreationFailed)
        return
      }
      completion(firstResult, nil)
    }
  }

  static func importItems(_ items: [FBPhotoImportItem], completion: @escaping Completion) {
    let startedAt = Date()
    guard hasReadableAuthorization() else {
      completion(nil, FBPhotosCommandError.permissionDenied)
      return
    }

    // Write each item to a temp file with extension matching mediaType. iOS
    // PhotoKit's addResource(with:data:options:) returns PHPhotosErrorDomain
    // 3300 for video resources regardless of uniformTypeIdentifier; the
    // fileURL form is the documented stable path. See Apple Dev Forums
    // thread 708318 — chronic since iOS 15. options.shouldMoveFile=false
    // keeps the file in place so we own cleanup in defer.
    let tempURLs: [URL] = items.map { item in
      let ext = Self.fileExtension(for: item.mediaType)
      return URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    defer {
      for url in tempURLs {
        try? FileManager.default.removeItem(at: url)
      }
    }

    do {
      for (item, url) in zip(items, tempURLs) {
        try item.data.write(to: url)
      }
    } catch {
      completion(nil, error)
      return
    }

    do {
      var identifiers: [String] = []
      try PHPhotoLibrary.shared().performChangesAndWait {
        identifiers = zip(items, tempURLs).compactMap { (item, tempURL) -> String? in
          let request = PHAssetCreationRequest.forAsset()
          let options = PHAssetResourceCreationOptions()
          options.uniformTypeIdentifier = item.uti ?? Self.defaultUti(for: item.mediaType)
          options.shouldMoveFile = false
          request.addResource(with: item.mediaType.assetResourceType, fileURL: tempURL, options: options)
          return request.placeholderForCreatedAsset?.localIdentifier
        }
      }
      guard identifiers.count == items.count else {
        completion(nil, FBPhotosCommandError.assetCreationFailed)
        return
      }
      let totalDurationMs = durationMs(since: startedAt)
      let perItemDurationMs = items.isEmpty ? 0 : totalDurationMs / items.count
      let results = identifiers.map { identifier in
        FBPhotoResponseFactory.importResult(assetIdentifier: identifier, durationMs: perItemDurationMs)
      }
      completion([
        "results": results,
        "totalDurationMs": totalDurationMs,
      ], nil)
    } catch {
      completion(nil, error)
    }
  }

  static func hasReadableAuthorization() -> Bool {
    return FBPhotosPermissionHelper.hasReadWriteAuthorization(allowLimited: true)
  }

  static func hasFullAuthorization() -> Bool {
    return FBPhotosPermissionHelper.hasFullReadWriteAuthorization()
  }

  static func parsedLimit(from url: URL) -> Int {
    let defaultLimit = 100
    let maxLimit = 1000
    guard
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let rawLimit = components.queryItems?.first(where: { $0.name == "limit" })?.value,
      let requestedLimit = Int(rawLimit)
    else {
      return defaultLimit
    }
    return min(max(requestedLimit, 0), maxLimit)
  }

  static func durationMs(since startedAt: Date) -> Int {
    return Int(Date().timeIntervalSince(startedAt) * 1000)
  }

  static func defaultUti(for mediaType: FBPhotoMediaType) -> String {
    switch mediaType {
    case .image: return "public.jpeg"
    case .video: return "public.mpeg-4"
    }
  }

  static func fileExtension(for mediaType: FBPhotoMediaType) -> String {
    switch mediaType {
    case .image: return "jpg"
    case .video: return "mp4"
    }
  }
}
#endif
