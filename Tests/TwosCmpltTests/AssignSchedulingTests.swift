import XCTest
import SharedTypes
@testable import TwosCmplt

// Tests for Phase 5: Kahn's-order scheduling for Verilog continuous
// assigns (see CircDef.md). Gate/instance scheduling already used Kahn's
// algorithm; continuous assigns previously ran unconditionally, in
// declaration order, on every timestep (runAllAssignBlcks). Now each
// assign gets a .assgnBlk CmpRef wired into the same dependency graph.
final class AssignSchedulingTests: XCTestCase {

    private func emptyCircDef() -> CircDef {
        CircDef(module: "Test", kind: "test", params: [], io_ports: [], decls: [], behav_blcks: [])
    }

    // referencedNodeNames must walk every Expr case that can nest further
    // ExprIds, not just the top-level one.
    func testReferencedNodeNamesWalksNestedExpressions() {
        var circDef = emptyCircDef()
        // (A + B[3:0]) — a binary op over a plain node and a select.
        let aId = circDef.internExpr(.node("A"))
        let msbId = circDef.internExpr(.int(3))
        let lsbId = circDef.internExpr(.int(0))
        let selectId = circDef.internExpr(.select(name: "B", args: [msbId, lsbId]))
        let sumId = circDef.internExpr(.binary(op: .plus, args: [aId, selectId]))

        let names = referencedNodeNames(sumId, in: circDef)
        XCTAssertEqual(names, ["A", "B"])
    }

    // lvalueBaseNames must decompose a .concat target into every node it
    // writes, unlike lvalueBaseName which collapses it to a placeholder.
    func testLvalueBaseNamesDecomposesConcat() {
        let lv = LValueAST.concat([.net(name: "A"), .bitSelect(name: "B", index: 2)])
        XCTAssertEqual(lvalueBaseNames(lv), ["A", "B"])
        XCTAssertEqual(lvalueBaseNames(.net(name: "X")), ["X"])
    }

    // Real-world confirmation: MULT_25P125.yml (Resources/CircuitLib) has
    // three continuous assigns; "OUT" reads "sum", which the first assign
    // writes. Kahn's-algorithm ordering must place the "sum"-writer before
    // the "OUT"-writer.
    func testRealCircuitAssignsScheduledInDependencyOrder() throws {
        guard let circuit = genCirc("MULT_25P125") else {
            XCTFail("Failed to load MULT_25P125 circuit via genCirc")
            return
        }

        guard let sumIdx = circuit.nodeLU["sum"], let outIdx = circuit.nodeLU["OUT"] else {
            XCTFail("Expected nodes not found")
            return
        }

        // The assign block driving "sum" and the one driving "OUT" must
        // both exist and be scheduled with "sum" first.
        guard let sumWriterIdx = circuit.assgnBlkWrites.firstIndex(where: { $0.contains(sumIdx) }),
              let outWriterIdx = circuit.assgnBlkWrites.firstIndex(where: { $0.contains(outIdx) }) else {
            XCTFail("Expected assgnBlkWrites entries for sum/OUT not found")
            return
        }
        XCTAssertTrue(circuit.assgnBlkReads[outWriterIdx].contains(sumIdx),
                      "the OUT-writing assign must be recorded as reading sum")

        let sumPos = circuit.evalOrder.firstIndex(of: CmpRef(kind: .assgnBlk, index: sumWriterIdx))
        let outPos = circuit.evalOrder.firstIndex(of: CmpRef(kind: .assgnBlk, index: outWriterIdx))
        guard let sumPos, let outPos else {
            XCTFail("Expected .assgnBlk CmpRefs not found in evalOrder")
            return
        }
        XCTAssertLessThan(sumPos, outPos, "sum must be computed before OUT, which depends on it")
    }
}
