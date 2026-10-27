import XCTest
@testable import TwosCmplt

// A one-statement block with no begin/end (`always @(D or STATE)
// ENBL = (D != STATE);`, the gated flip-flops' models) reaches CircuitLib
// with `stmnts` as the statement itself, not a one-item list. Decoding it
// crashed SimRun ("Expected to decode Sequence but found Node instead",
// behav_blcks -> Index 3 -> stmnts; DG_DER_3X2 and the other gated twins).
final class StmntDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ yaml: String, as type: T.Type) throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stmnt_decoding_\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try rdYAML(at: url.path)
    }

    private let stmnt = """
          kind: blckst
          lvalue: {kind: ident, name: ENBL}
          rvalue: {kind: ident, name: D}
        """

    func testAlwaysBlockWithOneStatementNotInAList() throws {
        let blk = try decode("stmnts:\n" + stmnt, as: AlwaysBlckYAML.self)
        XCTAssertEqual(blk.stmnts.count, 1)
    }

    func testAlwaysBlockWithAListIsUnchanged() throws {
        let list = "stmnts:\n  - kind: blckst\n    lvalue: {kind: ident, name: ENBL}\n"
            + "    rvalue: {kind: ident, name: D}\n"
            + "  - kind: blckst\n    lvalue: {kind: ident, name: CLKB}\n"
            + "    rvalue: {kind: ident, name: CLK}\n"
        let blk = try decode(list, as: AlwaysBlckYAML.self)
        XCTAssertEqual(blk.stmnts.count, 2)
    }

    func testInitialBlockWithOneStatementNotInAList() throws {
        let blk = try decode("stmnts:\n" + stmnt, as: InitBlckYAML.self)
        XCTAssertEqual(blk.stmnts.count, 1)
    }

    // An error inside a list is still reported, not retried as one statement.
    func testBadStatementInsideAListStillFails() {
        let bad = "stmnts:\n  - kind: blckst\n    lvalue: 7\n"
        XCTAssertThrowsError(try decode(bad, as: AlwaysBlckYAML.self))
    }
}
