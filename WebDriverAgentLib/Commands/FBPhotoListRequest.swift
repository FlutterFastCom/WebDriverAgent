/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

enum FBPhotoListResponseMode: Equatable {
  case legacy
  case exact
}

struct FBPhotoListRequest {
  let mode: FBPhotoListResponseMode
  let limit: Int

  static func parse(url: URL) throws -> FBPhotoListRequest {
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let snapshotItems = queryItems.filter { $0.name == "includeSnapshot" }
    let mode = try responseMode(from: snapshotItems)
    let limitItems = queryItems.filter { $0.name == "limit" }

    switch mode {
    case .legacy:
      return FBPhotoListRequest(mode: mode, limit: legacyLimit(from: limitItems.first?.value))
    case .exact:
      return FBPhotoListRequest(mode: mode, limit: try exactLimit(from: limitItems))
    }
  }

  private static func responseMode(from items: [URLQueryItem]) throws -> FBPhotoListResponseMode {
    guard items.count <= 1 else {
      throw FBPhotoListRequestError.invalidIncludeSnapshot
    }
    guard let item = items.first else {
      return .legacy
    }
    switch item.value {
    case "false": return .legacy
    case "true": return .exact
    default: throw FBPhotoListRequestError.invalidIncludeSnapshot
    }
  }

  private static func legacyLimit(from rawValue: String?) -> Int {
    guard let rawValue, let value = Int(rawValue) else {
      return 100
    }
    return min(max(value, 0), 1_000)
  }

  private static func exactLimit(from items: [URLQueryItem]) throws -> Int {
    guard !items.isEmpty else {
      throw FBPhotoListRequestError.missingExactLimit
    }
    guard items.count == 1 else {
      throw FBPhotoListRequestError.duplicateLimit
    }
    guard let rawValue = items[0].value else {
      throw FBPhotoListRequestError.missingExactLimit
    }
    if rawValue == "0" {
      throw FBPhotoListRequestError.exactLimitOutOfRange
    }
    guard isCanonicalPositiveDecimal(rawValue) else {
      throw FBPhotoListRequestError.invalidExactLimit
    }
    guard let value = Int(rawValue), value <= 20 else {
      throw FBPhotoListRequestError.exactLimitOutOfRange
    }
    return value
  }

  private static func isCanonicalPositiveDecimal(_ value: String) -> Bool {
    guard let first = value.unicodeScalars.first, first.value >= 49, first.value <= 57 else {
      return false
    }
    return value.unicodeScalars.dropFirst().allSatisfy { scalar in
      scalar.value >= 48 && scalar.value <= 57
    }
  }
}

enum FBPhotoListRequestError: Error, CustomNSError, LocalizedError {
  case missingExactLimit
  case duplicateLimit
  case invalidExactLimit
  case exactLimitOutOfRange
  case invalidIncludeSnapshot

  static var errorDomain: String {
    return "FBPhotoListRequestError"
  }

  var errorCode: Int {
    switch self {
    case .missingExactLimit: return 1
    case .duplicateLimit: return 2
    case .invalidExactLimit: return 3
    case .exactLimitOutOfRange: return 4
    case .invalidIncludeSnapshot: return 5
    }
  }

  var errorDescription: String? {
    switch self {
    case .missingExactLimit: return "missing_exact_limit"
    case .duplicateLimit: return "duplicate_limit"
    case .invalidExactLimit: return "invalid_exact_limit"
    case .exactLimitOutOfRange: return "exact_limit_out_of_range"
    case .invalidIncludeSnapshot: return "invalid_include_snapshot"
    }
  }

  var errorUserInfo: [String: Any] {
    return [NSLocalizedDescriptionKey: errorDescription ?? "invalid_photo_list_request"]
  }
}
