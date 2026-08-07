/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import WebDriverAgentLib

final class FBPhotoListRequestTests: XCTestCase {
  func testLegacyDefaultsAndClampsUsingFirstLimitOnly() throws {
    assertRequest("", mode: .legacy, limit: 100)
    assertRequest("?limit=x", mode: .legacy, limit: 100)
    assertRequest("?limit", mode: .legacy, limit: 100)
    assertRequest("?limit=-3", mode: .legacy, limit: 0)
    assertRequest("?limit=2001", mode: .legacy, limit: 1_000)
    assertRequest("?limit=3&limit=4", mode: .legacy, limit: 3)
    assertRequest("?other=9&limit=6", mode: .legacy, limit: 6)
    assertRequest("?limit=7&includeSnapshot=false", mode: .legacy, limit: 7)
  }

  func testExactAcceptsOnlyCanonicalBoundedDecimalLimit() throws {
    assertRequest("?includeSnapshot=true&limit=1", mode: .exact, limit: 1)
    assertRequest("?limit=20&other=ignored&includeSnapshot=%74rue", mode: .exact, limit: 20)

    assertError("?includeSnapshot=true", .missingExactLimit)
    assertError("?includeSnapshot=true&limit", .missingExactLimit)
    assertError("?includeSnapshot=true&limit=3&limit=4", .duplicateLimit)
    assertError("?includeSnapshot=true&limit=0", .exactLimitOutOfRange)
    assertError("?includeSnapshot=true&limit=21", .exactLimitOutOfRange)
    assertError("?includeSnapshot=true&limit=999999999999999999999", .exactLimitOutOfRange)
    assertError("?includeSnapshot=true&limit=03", .invalidExactLimit)
    assertError("?includeSnapshot=true&limit=-3", .invalidExactLimit)
    assertError("?includeSnapshot=true&limit=%2B3", .invalidExactLimit)
    assertError("?includeSnapshot=true&limit=+3", .invalidExactLimit)
    assertError("?includeSnapshot=true&limit=%203", .invalidExactLimit)
    assertError("?includeSnapshot=true&limit=3.0", .invalidExactLimit)
    assertError("?includeSnapshot=true&limit=%D9%A3", .invalidExactLimit)
  }

  func testSnapshotFlagRejectsDuplicatesMissingValuesAndNonCanonicalText() throws {
    assertError("?includeSnapshot", .invalidIncludeSnapshot)
    assertError("?includeSnapshot=TRUE&limit=3", .invalidIncludeSnapshot)
    assertError("?includeSnapshot=false&includeSnapshot=false", .invalidIncludeSnapshot)
    assertError("?includeSnapshot=false&includeSnapshot=true&limit=3", .invalidIncludeSnapshot)
  }

  private func assertRequest(
    _ query: String,
    mode: FBPhotoListResponseMode,
    limit: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    do {
      let request = try FBPhotoListRequest.parse(url: url(query))
      XCTAssertEqual(request.mode, mode, file: file, line: line)
      XCTAssertEqual(request.limit, limit, file: file, line: line)
    } catch {
      XCTFail("Unexpected parser error: \(error)", file: file, line: line)
    }
  }

  private func assertError(
    _ query: String,
    _ expected: FBPhotoListRequestError,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try FBPhotoListRequest.parse(url: url(query)), file: file, line: line) { error in
      let actual = error as NSError
      XCTAssertEqual(actual.domain, FBPhotoListRequestError.errorDomain, file: file, line: line)
      XCTAssertEqual(actual.code, expected.errorCode, file: file, line: line)
      XCTAssertEqual(actual.localizedDescription, expected.errorDescription, file: file, line: line)
    }
  }

  private func url(_ query: String) -> URL {
    return URL(string: "http://localhost/wda/photos/list\(query)")!
  }
}
