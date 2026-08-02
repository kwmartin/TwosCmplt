import XCTest
import SharedTypes
@testable import TwosCmplt

// Regression check for Phase 5 (Kahn's-order scheduling for continuous
// assigns, see CircDef.md): TST_ACCUM3 (module TST_ACCUM3, instantiating
// M1M_QDACCUM5, which has a real continuous assign — see CircDef.md's
// Part 1) is the one real circuit in the library confirmed to actually
// exercise .assgnBlk scheduling end-to-end.
//
// Updated for Phase 6: the original expected values here (value=0x30000,
// updTm=12) described a genuine bug, not correct behavior — RL_ (the
// accumulator register) never latched because CircDef.swift's output-port
// wiring silently collapsed multi-bit slice connections (e.g. "S[3:2]") to
// a whole-node overwrite with no bit-shift/mask, so sibling instances
// driving different slices of the same bus (e.g. CLA2_0/CLA2_1 each
// driving half of CLA4's own S, all the way up through CLA8/CLA10/CLA18)
// clobbered each other — see CircDef.md and PortDef.extlBitRange /
// Circuit.setNodeBits. After the fix, QD_ (derived combinationally from
// RL_) genuinely updates throughout the run instead of freezing after
// t=12. It still ends at value 0x30000 at t=128011 (finish time) — this
// is a coincidence of this spec's parameters, not evidence the old bug is
// still present: FRQ=0x40000000 increments RL_ by FRQ[33:16]=16384 each
// clock, and 128 clocks * 16384 = 2^21, an exact multiple of 2^18 (RL_'s
// width), so RL_ wraps back to exactly 0 (and QD_ back to 0x30000) right
// at the end of this particular 128-period run.
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
        guard let rlIdx = circuit.nodeLU["RL_"] else {
            XCTFail("RL_ node not found")
            return
        }
        let qd = circuit.nodes[qdIdx]
        let rl = circuit.nodes[rlIdx]

        // The actual regression this test now guards: RL_ must genuinely
        // latch during the run, not stay frozen at its reset value.
        XCTAssertGreaterThan(rl.updTm, 0,
                       "RL_ never updated — the output-port bit-range wiring bug (Phase 6) may have regressed")
        XCTAssertEqual(qd.node.value, 0x30000,
                       "QD_'s final value changed — see comment above on why 0x30000 is still expected here")
        XCTAssertEqual(qd.updTm, 128011,
                       "QD_'s final update time changed — investigate before assuming this is fine")
    }
}
