/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import WebDriverAgentLib

final class FBPhotoSnapshotContinuityTests: XCTestCase {
  func testBaselineAndZeroChangesDoNotAdvanceSequence() {
    var state = FBPhotoSnapshotState<String>()

    XCTAssertEqual(state.reconcile(currentToken: "a", changeTokens: []), .baselined)
    XCTAssertEqual(state.reconcile(currentToken: "a", changeTokens: []), .unchanged)
    XCTAssertEqual(state.changeSequence, 0)
    XCTAssertEqual(state.token, "a")
  }

  func testEveryPersistentChangeAdvancesSequence() {
    var state = FBPhotoSnapshotState<String>(token: "a")

    XCTAssertEqual(
      state.reconcile(currentToken: "d", changeTokens: ["b", "c", "d"]),
      .advanced(3)
    )
    XCTAssertEqual(state.changeSequence, 3)
    XCTAssertEqual(state.token, "d")
  }

  func testTransientInsertDeleteAdvancesTwiceEvenWhenFinalAssetsCouldMatch() {
    var state = FBPhotoSnapshotState<String>(token: "before")

    XCTAssertEqual(
      state.reconcile(currentToken: "after-delete", changeTokens: ["after-insert", "after-delete"]),
      .advanced(2)
    )
    XCTAssertEqual(state.changeSequence, 2)
  }

  func testUnbridgeableOrIncompleteHistoryRotatesInstance() {
    var unbridgeable = FBPhotoSnapshotState<String>(token: "old")
    let unbridgeableInstance = unbridgeable.libraryInstanceId
    XCTAssertEqual(unbridgeable.reconcile(currentToken: "current", changeTokens: nil), .rotated)
    XCTAssertNotEqual(unbridgeable.libraryInstanceId, unbridgeableInstance)
    XCTAssertEqual(unbridgeable.changeSequence, 0)
    XCTAssertEqual(unbridgeable.token, "current")

    var incomplete = FBPhotoSnapshotState<String>(token: "old")
    let incompleteInstance = incomplete.libraryInstanceId
    XCTAssertEqual(incomplete.reconcile(currentToken: "current", changeTokens: ["intermediate"]), .rotated)
    XCTAssertNotEqual(incomplete.libraryInstanceId, incompleteInstance)
    XCTAssertEqual(incomplete.token, "current")
  }

  func testAuthorizationLossAndRecoveryEachRotate() {
    var state = FBPhotoSnapshotState<String>(token: "a")
    let initialInstance = state.libraryInstanceId

    XCTAssertFalse(state.noteAuthorization(readable: true))
    XCTAssertTrue(state.noteAuthorization(readable: false))
    let lossInstance = state.libraryInstanceId
    XCTAssertNotEqual(lossInstance, initialInstance)
    XCTAssertNil(state.token)

    XCTAssertTrue(state.noteAuthorization(readable: true))
    XCTAssertNotEqual(state.libraryInstanceId, lossInstance)
    XCTAssertNil(state.token)
  }

  func testOverflowRotatesInsteadOfWrapping() {
    var state = FBPhotoSnapshotState<String>(changeSequence: UInt64.max, token: "old")
    let oldInstance = state.libraryInstanceId

    XCTAssertEqual(state.reconcile(currentToken: "current", changeTokens: ["current"]), .rotated)
    XCTAssertNotEqual(state.libraryInstanceId, oldInstance)
    XCTAssertEqual(state.changeSequence, 0)
    XCTAssertEqual(state.token, "current")
  }

  func testStableCutSucceedsImmediatelyOrAfterRetry() throws {
    let immediate = [FBPhotoStableCutSample(reconciledToken: "a", postFetchToken: "a")]
    XCTAssertEqual(try FBPhotoStableCutGate.firstStableAttempt(in: immediate), 1)

    let retry = [
      FBPhotoStableCutSample(reconciledToken: "a", postFetchToken: "b"),
      FBPhotoStableCutSample(reconciledToken: "c", postFetchToken: "c"),
    ]
    XCTAssertEqual(try FBPhotoStableCutGate.firstStableAttempt(in: retry), 2)
  }

  func testFourUnstableAttemptsReturnBusyWithoutAdmittingFifthSample() {
    let samples = [
      FBPhotoStableCutSample(reconciledToken: "a", postFetchToken: "b"),
      FBPhotoStableCutSample(reconciledToken: "b", postFetchToken: "c"),
      FBPhotoStableCutSample(reconciledToken: "c", postFetchToken: "d"),
      FBPhotoStableCutSample(reconciledToken: "d", postFetchToken: "e"),
      FBPhotoStableCutSample(reconciledToken: "f", postFetchToken: "f"),
    ]

    XCTAssertThrowsError(try FBPhotoStableCutGate.firstStableAttempt(in: samples)) { error in
      guard case FBPhotoStableCutGateError.busy = error else {
        XCTFail("Expected busy, got \(error)")
        return
      }
    }
  }
}
