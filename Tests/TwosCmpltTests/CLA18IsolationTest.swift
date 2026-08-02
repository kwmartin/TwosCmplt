import XCTest
import SharedTypes
@testable import TwosCmplt

// Regression test (Phase 6): TST_ACCUM3's RL_ never updated because
// CircDef.swift's output-port wiring silently collapsed multi-bit slice
// connections (e.g. "S[3:2]") to a whole-node overwrite with no
// bit-shift/mask (see PortDef.extlBitRange / Circuit.setNodeBits). CLA18's
// internal carry-lookahead hierarchy (CLA18 -> CLA8/CLA10 -> CLA4 -> CLA2)
// has sibling instances each driving a different slice of the same wider
// "S" bus at every level, so each level's S stayed stuck at whichever
// sibling happened to evaluate last (usually the all-zero one) instead of
// the correctly combined sum. This test isolates CLA18 directly (bypassing
// TST_ACCUM3/M1M_QDACCUM5/KM_REGS18 entirely) to pin down and guard
// against exactly that bug: given A=16384 (FRQ[33:16], a nonzero
// constant), B=0, CI=0, a correct 18-bit adder must produce S=16384.
final class CLA18IsolationTest: XCTestCase {
    func testCLA18AddsNonzeroA() throws {
        guard let circuit = genCirc("CLA18") else {
            XCTFail("Failed to load CLA18 circuit via genCirc")
            return
        }
        circuit.name = "CLA18"
        circuit.indexs = [0]

        circuit.setNode("VDD", val: 1, tm: 0)
        circuit.setNode("VSS", val: 0, tm: 0)
        circuit.setNode("A", val: 16384, tm: 0)
        circuit.setNode("B", val: 0, tm: 0)
        circuit.setNode("CI", val: 0, tm: 0)

        circuit.eval(async: true, tm: 0)
        circuit.eval(async: true, tm: 100)

        guard let sIdx = circuit.nodeLU["S"] else {
            XCTFail("S node not found")
            return
        }
        let sVal = circuit.nodes[sIdx].node.value
        print("CLA18 isolated test: A=16384 B=0 CI=0 -> S=\(sVal) (expected 16384)")
        XCTAssertEqual(sVal, 16384,
                       "CLA18 should compute S = A+B+CI = 16384+0+0 = 16384")
    }
}
