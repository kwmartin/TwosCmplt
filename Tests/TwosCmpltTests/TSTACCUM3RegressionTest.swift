import XCTest
import SharedTypes
@testable import TwosCmplt

// Regression check for Phase 5 (Kahn's-order scheduling for continuous
// assigns, see CircDef.md): TST_ACCUM3 (module TST_ACCUM3, instantiating
// M1M_QDACCUM5, which has a real continuous assign — see CircDef.md's
// Part 1) is the one real circuit in the library confirmed to actually
// exercise .assgnBlk scheduling end-to-end. Values below were verified
// identical before and after Phase 5 by temporarily stashing the
// scheduling change and re-running this exact test.
final class TSTACCUM3RegressionTest: XCTestCase {
    func testTSTACCUM3LoadsAndRuns() throws {
        guard let circuit = genCirc("TST_ACCUM3") else {
            XCTFail("Failed to load TST_ACCUM3 circuit via genCirc")
            return
        }
        circuit.name = "TST_ACCUM3"
        Glbls.topCircuit = circuit

        let (per, finishTm, tmSpcs) = loadSpecs("TST_ACCUM3")
        _ = simCircuit(circuit, per: per, finishTm: finishTm, tmSpcs: tmSpcs)

        guard let qdIdx = circuit.nodeLU["QD_"] else {
            XCTFail("QD_ node not found")
            return
        }
        let qd = circuit.nodes[qdIdx]
        XCTAssertEqual(qd.node.value, 0x30000,
                       "QD_'s value changed — Kahn's-order assign scheduling may have altered behavior")
        XCTAssertEqual(qd.updTm, 12,
                       "QD_'s update time changed — Kahn's-order assign scheduling may have altered timing")
    }
}
