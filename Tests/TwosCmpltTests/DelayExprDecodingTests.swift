import XCTest
@testable import TwosCmplt

// The latches' `STR <= #(`L2_C2Q*`DLY_MLTPLY) D;` has a delay that depends on
// D (L2_C2Q is D ? 13.2 : 8.1). verilogParse writes it as an expression under
// delay.delay, and decoding it as a number stopped SimRun ("Expected to decode
// Scalar but found Mapping", DG_LTCHR_4X1 and the other latches).
final class DelayExprDecodingTests: XCTestCase {

    private func decode(_ yaml: String) throws -> NoblckStmntYAML {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("delay_expr_\(UUID().uuidString).yml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try rdYAML(at: url.path)
    }

    private let head = """
        lvalue: {kind: ident, name: STR}
        rvalue: {kind: ident, name: D}

        """

    func testNumberDelay() throws {
        let s = try decode(head + "delay: {kind: float, delay: 8.1}\n")
        guard case .float(let d)? = s.delay else { return XCTFail("\(String(describing: s.delay))") }
        XCTAssertEqual(d, 8.1)
    }

    func testConstantExpressionDelayIsANumber() throws {
        let s = try decode(head + """
            delay: {kind: float, delay: {kind: bexpr, oper: 'Times:',
                    args: [{kind: float, value: 8.1}, {kind: float, value: 2.0}]}}

            """)
        guard case .float(let d)? = s.delay else { return XCTFail("\(String(describing: s.delay))") }
        XCTAssertEqual(d, 16.2, accuracy: 1e-9)
    }

    func testSignalDependentDelayIsAnExpression() throws {
        let s = try decode(head + """
            delay: {kind: float, delay: {kind: bexpr, oper: 'Times:', args: [
                {kind: cndexpr, args: [{kind: ident, name: D}, {kind: float, value: 13.2},
                                       {kind: float, value: 8.1}]},
                {kind: float, value: 1.0}]}}

            """)
        guard case .expr? = s.delay else { return XCTFail("\(String(describing: s.delay))") }
    }
}
