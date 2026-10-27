import XCTest
@testable import TwosCmplt

// A spec written by Python can hold PER: 100.0 (a float) where Swift expects
// an Int; SimRun stopped with "Constants must decode from either [String: Int]
// or [Constant]" (TST_NAB_C). A whole number with a decimal point is accepted;
// a fraction is still refused.
final class ConstantsDecodingTests: XCTestCase {

    private func decode(_ yaml: String) throws -> Constants {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("constants_decoding_\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try rdYAML(at: url.path)
    }

    func testIntegerMapping() throws {
        XCTAssertEqual(try decode("PER: 100\n")["PER"], 100)
    }

    func testWholeFloatMapping() throws {
        let c = try decode("PER: 100.0\nN: 4\n")
        XCTAssertEqual(c["PER"], 100)
        XCTAssertEqual(c["N"], 4)
    }

    func testFractionalFloatMappingIsRefused() {
        XCTAssertThrowsError(try decode("PER: 100.5\n"))
    }

    func testListFormWithWholeFloat() throws {
        XCTAssertEqual(try decode("- [PER, 1000.0]\n")["PER"], 1000)
    }
}
