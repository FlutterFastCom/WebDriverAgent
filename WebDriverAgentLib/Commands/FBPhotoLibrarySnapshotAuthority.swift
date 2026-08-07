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

struct FBExactPhotoSnapshot {
  let assets: [PHAsset]
  let libraryInstanceId: UUID
  let changeSequence: UInt64
  let totalCount: Int
}

enum FBPhotoSnapshotAuthorityError: LocalizedError {
  case persistentChangeHistoryUnavailable
  case historyReconciliationFailed
  case photoLibraryBusy

  var errorDescription: String? {
    switch self {
    case .persistentChangeHistoryUnavailable: return "persistent_change_history_unavailable"
    case .historyReconciliationFailed: return "history_reconciliation_failed"
    case .photoLibraryBusy: return "photo_library_busy"
    }
  }
}

enum FBPhotoSnapshotReconcileOutcome: Equatable {
  case baselined
  case unchanged
  case advanced(Int)
  case rotated
}

struct FBPhotoSnapshotState<Token: Equatable> {
  private(set) var libraryInstanceId: UUID
  private(set) var changeSequence: UInt64
  private(set) var token: Token?
  private(set) var authorizationReadable: Bool?

  init(
    libraryInstanceId: UUID = UUID(),
    changeSequence: UInt64 = 0,
    token: Token? = nil,
    authorizationReadable: Bool? = nil
  ) {
    self.libraryInstanceId = libraryInstanceId
    self.changeSequence = changeSequence
    self.token = token
    self.authorizationReadable = authorizationReadable
  }

  mutating func noteAuthorization(readable: Bool) -> Bool {
    defer { authorizationReadable = readable }
    guard let prior = authorizationReadable, prior != readable else {
      return false
    }
    rotate(baseline: nil)
    return true
  }

  mutating func rotate(baseline: Token?) {
    libraryInstanceId = UUID()
    changeSequence = 0
    token = baseline
  }

  mutating func reconcile(currentToken: Token, changeTokens: [Token]?) -> FBPhotoSnapshotReconcileOutcome {
    guard let priorToken = token else {
      token = currentToken
      return .baselined
    }
    guard priorToken != currentToken else {
      return .unchanged
    }
    guard let changeTokens else {
      rotate(baseline: currentToken)
      return .rotated
    }

    for changeToken in changeTokens {
      let (nextSequence, overflow) = changeSequence.addingReportingOverflow(1)
      if overflow {
        rotate(baseline: currentToken)
        return .rotated
      }
      changeSequence = nextSequence
      token = changeToken
    }

    guard token == currentToken else {
      rotate(baseline: currentToken)
      return .rotated
    }
    return .advanced(changeTokens.count)
  }
}

struct FBPhotoStableCutSample<Token: Equatable> {
  let reconciledToken: Token
  let postFetchToken: Token
}

enum FBPhotoStableCutGateError: Error {
  case busy
}

enum FBPhotoStableCutGate<Token: Equatable> {
  static var maximumAttempts: Int {
    return 4
  }

  static func isStable(reconciledToken: Token, postFetchToken: Token) -> Bool {
    return reconciledToken == postFetchToken
  }

  static func firstStableAttempt(in samples: [FBPhotoStableCutSample<Token>]) throws -> Int {
    for (offset, sample) in samples.prefix(maximumAttempts).enumerated() {
      if isStable(reconciledToken: sample.reconciledToken, postFetchToken: sample.postFetchToken) {
        return offset + 1
      }
    }
    throw FBPhotoStableCutGateError.busy
  }
}

@available(iOS 16, *)
private struct FBPhotoPersistentToken: Equatable {
  let rawValue: PHPersistentChangeToken

  static func == (lhs: FBPhotoPersistentToken, rhs: FBPhotoPersistentToken) -> Bool {
    return lhs.rawValue.isEqual(rhs.rawValue)
  }
}

@available(iOS 16, *)
final class FBPhotoLibrarySnapshotAuthority: NSObject, PHPhotoLibraryChangeObserver {
  static let shared = FBPhotoLibrarySnapshotAuthority()

  private let photoLibrary = PHPhotoLibrary.shared()
  private let queue = DispatchQueue(label: "com.facebook.WebDriverAgent.photo-snapshot-authority")
  private let queueKey = DispatchSpecificKey<UInt8>()
  private var state = FBPhotoSnapshotState<FBPhotoPersistentToken>()
  private var isRegistered = false
  private var hasRegisteredBefore = false

  private override init() {
    super.init()
    queue.setSpecific(key: queueKey, value: 1)
  }

  deinit {
    if isRegistered {
      photoLibrary.unregisterChangeObserver(self)
    }
  }

  func read(limit: Int) throws -> FBExactPhotoSnapshot {
    return try syncOnAuthorityQueue {
      let authorizationRotated = state.noteAuthorization(readable: FBPhotosPermissionHelper.hasReadWriteAuthorization(allowLimited: true))
      guard state.authorizationReadable == true else {
        unregisterObserverIfNeeded()
        throw FBPhotosCommandError.permissionDenied
      }
      registerObserverIfNeeded(alreadyRotated: authorizationRotated)
      return try readStableSnapshot(limit: limit)
    }
  }

  func noteAuthorizationUnavailable() {
    syncOnAuthorityQueue {
      _ = state.noteAuthorization(readable: false)
      unregisterObserverIfNeeded()
    }
  }

  func photoLibraryDidChange(_ changeInstance: PHChange) {
    queue.async { [weak self] in
      self?.reconcileAfterObserverWake()
    }
  }

  private func syncOnAuthorityQueue<T>(_ work: () throws -> T) rethrows -> T {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      return try work()
    }
    return try queue.sync(execute: work)
  }

  private func registerObserverIfNeeded(alreadyRotated: Bool) {
    guard !isRegistered else {
      return
    }
    if hasRegisteredBefore && !alreadyRotated {
      state.rotate(baseline: nil)
    }
    photoLibrary.register(self)
    isRegistered = true
    hasRegisteredBefore = true
  }

  private func unregisterObserverIfNeeded() {
    guard isRegistered else {
      return
    }
    photoLibrary.unregisterChangeObserver(self)
    isRegistered = false
  }

  @available(iOS 16, *)
  private func readStableSnapshot(limit: Int) throws -> FBExactPhotoSnapshot {
    for attempt in 1...FBPhotoStableCutGate<FBPhotoPersistentToken>.maximumAttempts {
      let reconciledToken = FBPhotoPersistentToken(rawValue: photoLibrary.currentChangeToken)
      let outcome = try reconcile(to: reconciledToken)
      let fetchResult = PHAsset.fetchAssets(with: nil)
      let postFetchToken = FBPhotoPersistentToken(rawValue: photoLibrary.currentChangeToken)

      guard FBPhotoStableCutGate.isStable(reconciledToken: reconciledToken, postFetchToken: postFetchToken),
            state.token == postFetchToken else {
        NSLog("photo.snapshot retry attempt=%d failure=unstable_cut", attempt)
        continue
      }

      let assets = newestAssets(from: fetchResult, limit: limit)
      logReconcile(outcome, returnedCount: assets.count)
      return FBExactPhotoSnapshot(
        assets: assets,
        libraryInstanceId: state.libraryInstanceId,
        changeSequence: state.changeSequence,
        totalCount: fetchResult.count
      )
    }
    throw FBPhotoSnapshotAuthorityError.photoLibraryBusy
  }

  @available(iOS 16, *)
  private func reconcile(to currentToken: FBPhotoPersistentToken) throws -> FBPhotoSnapshotReconcileOutcome {
    guard let priorToken = state.token, priorToken != currentToken else {
      return state.reconcile(currentToken: currentToken, changeTokens: [])
    }

    do {
      let changes = try photoLibrary.fetchPersistentChanges(since: priorToken.rawValue)
      let changeTokens = changes.map { FBPhotoPersistentToken(rawValue: $0.changeToken) }
      return state.reconcile(currentToken: currentToken, changeTokens: changeTokens)
    } catch {
      guard isContinuityLoss(error) else {
        throw FBPhotoSnapshotAuthorityError.historyReconciliationFailed
      }
      return state.reconcile(currentToken: currentToken, changeTokens: nil)
    }
  }

  private func newestAssets(from fetchResult: PHFetchResult<PHAsset>, limit: Int) -> [PHAsset] {
    let resultCount = min(limit, fetchResult.count)
    var assets: [PHAsset] = []
    assets.reserveCapacity(resultCount)
    for offset in 0..<resultCount {
      assets.append(fetchResult.object(at: fetchResult.count - 1 - offset))
    }
    return assets
  }

  private func reconcileAfterObserverWake() {
    guard isRegistered else {
      return
    }
    let readable = FBPhotosPermissionHelper.hasReadWriteAuthorization(allowLimited: true)
    let rotated = state.noteAuthorization(readable: readable)
    guard readable else {
      unregisterObserverIfNeeded()
      NSLog("photo.snapshot observer failure=authorization_lost rotated=%d", rotated ? 1 : 0)
      return
    }
    do {
      let token = FBPhotoPersistentToken(rawValue: photoLibrary.currentChangeToken)
      let outcome = try reconcile(to: token)
      logReconcile(outcome, returnedCount: nil)
    } catch {
      NSLog("photo.snapshot observer failure=history_reconciliation_failed")
    }
  }

  private func isContinuityLoss(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == PHPhotosErrorDomain else {
      return false
    }
    return nsError.code == PHPhotosError.persistentChangeTokenExpired.rawValue
      || nsError.code == PHPhotosError.persistentChangeDetailsUnavailable.rawValue
  }

  private func logReconcile(_ outcome: FBPhotoSnapshotReconcileOutcome, returnedCount: Int?) {
    let count: Int
    switch outcome {
    case .advanced(let value): count = value
    default: count = 0
    }
    let instancePrefix = String(state.libraryInstanceId.uuidString.prefix(8))
    NSLog(
      "photo.snapshot outcome=%@ changes=%d sequence=%llu instance=%@ returned=%@",
      String(describing: outcome),
      count,
      state.changeSequence,
      instancePrefix,
      returnedCount.map(String.init) ?? "-"
    )
  }
}
#endif
