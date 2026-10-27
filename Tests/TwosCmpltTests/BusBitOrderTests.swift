import XCTest
@testable import TwosCmplt

// Children write their bits of a bus in evaluation order, not time order. In
// TST_CLA4, CLA2_1's bit 0 change due at 10532 ps was written before bit 1's
// due at 10504; merging bit 1 into the latest value recorded S = 2 at 10504
// (it was 3) and left S = 0 recorded at 10532 (it was 2).
final class BusBitOrderTests: XCTestCase {

    func testEarlierBitWriteIsMergedAtItsOwnTime() throws {
        guard let circ = genCirc("CLA2"), let s = circ.nodeLU["S"] else {
            return XCTFail("Failed to load CLA2 or its node S")
        }
        Glbls.nodeChngs = []
        Glbls.allChngs = []
        circ.setNodeBit("S", bitIndex: 0, bitVal: 1, tm: 50)    // S = 1
        circ.setNodeBit("S", bitIndex: 0, bitVal: 0, tm: 132)   // evaluated first
        circ.setNodeBit("S", bitIndex: 1, bitVal: 1, tm: 104)   // due earlier

        XCTAssertEqual(circ.nodes[s].value(at: 60), 1)
        XCTAssertEqual(circ.nodes[s].value(at: 104), 3)
        XCTAssertEqual(circ.nodes[s].value(at: 132), 2)
        XCTAssertEqual(circ.nodes[s].node.value, 2)

        let recorded = Glbls.nodeChngs.filter { $0.nodeIndx == s }
            .sorted { $0.updTm < $1.updTm }.map { [$0.updTm, $0.value] }
        XCTAssertEqual(recorded, [[50, 1], [104, 3], [132, 2]])
    }

    func testInOrderBitWritesAreUnchanged() throws {
        guard let circ = genCirc("CLA2"), let s = circ.nodeLU["S"] else {
            return XCTFail("Failed to load CLA2 or its node S")
        }
        Glbls.nodeChngs = []
        Glbls.allChngs = []
        circ.setNodeBit("S", bitIndex: 0, bitVal: 1, tm: 50)
        circ.setNodeBit("S", bitIndex: 1, bitVal: 1, tm: 104)
        circ.setNodeBit("S", bitIndex: 0, bitVal: 0, tm: 132)
        let recorded = Glbls.nodeChngs.filter { $0.nodeIndx == s }.map { [$0.updTm, $0.value] }
        XCTAssertEqual(recorded, [[50, 1], [104, 3], [132, 2]])
    }
}
