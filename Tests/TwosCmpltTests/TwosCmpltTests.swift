// import Testing
// @testable import TwosCmplt

// @Test
// func testInit() async throws {
//     // Write your test here and use APIs like `#expect(...)` to check expected conditions.
//     let tc = TwoCmplt(value: 123)
//     #expect(tc.value == 123)
// }

import XCTest
import TwosCmplt

// filepath: Tests/TwosCmpltPackageTests/TwosCmpltPackageTests.swift
final class TwosCmpltPackageTests: XCTestCase {
    func testInit() {
        let tc = TwoCmplt(value: 123)
        XCTAssertEqual(tc.value,
         123)
    }
}