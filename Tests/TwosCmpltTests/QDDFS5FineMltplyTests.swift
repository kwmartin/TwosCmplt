import XCTest
import SharedTypes
@testable import TwosCmplt

// Diagnostic test reproducing a ~64-day-old debug note: FINE[7:0] inside
// Top.COS_LU5.fine_mltply.OUT was observed "identically 0" during early
// simulation. QD_DDFS5 is kind: verilog, so it must be loaded via genCirc
// (not Circuit.make, which is native-format only).
//
// Investigation (see CircDef.md / the plan file) found this is NOT specific
// to fine_mltply's port wiring (which is fine) — COS_LU5 and SIN_LU5 (both
// instances of module Sine5, QD_DDFS5's two mirrored fine-correction
// pipelines) never produce ANY output at all: their OUT/ROM_ ports, and
// everything downstream that depends on them (including fine_mltply, which
// consumes COS_LU5's own "COS" input port, itself fed from SIN_LU5's ROM_
// output via QD_DDFS5's RMSN node), stay stuck at their initial value 0 for
// the entire 64-period run. Some internal state does update (e.g. COS_LU5's
// own R3_ register reaches 0xff), and the phase accumulator (ACCUM) does
// cycle through real values, so the defect is somewhere inside the shared
// Sine5 module's internal pipeline (ADDR2/R0/CMPL0/ROM0/R5/CMPL1/ADDR3/R6),
// not in scheduling (QD_DDFS5's and COS_LU5's own evalOrder/cmpRefs counts
// match exactly — Kahn's algorithm completes cleanly at both levels) and not
// in fine_mltply's instance-port wiring specifically.
final class QDDFS5FineMltplyTests: XCTestCase {

    func testFineMltplyOutputTimeline() throws {
        guard let circuit = genCirc("QD_DDFS5") else {
            XCTFail("Failed to load QD_DDFS5 circuit via genCirc")
            return
        }
        circuit.name = "QD_DDFS5"
        Glbls.topCircuit = circuit

        let (per, finishTm, tmSpcs) = loadSpecs("QD_DDFS5")
        _ = simCircuit(circuit, per: per, finishTm: finishTm, tmSpcs: tmSpcs)

        guard let cosLU5 = circuit.cCircs.first(where: { $0.name == "COS_LU5" }) else {
            XCTFail("COS_LU5 sub-circuit instance not found under QD_DDFS5")
            return
        }
        guard let fineIdx = cosLU5.nodeLU["FINE"] else {
            XCTFail("FINE node not found in COS_LU5")
            return
        }

        // Corroborating context: the wider pipeline is also stuck, not just FINE.
        for nm in ["RMSN", "RMCS", "COS", "SINE"] {
            if let idx = circuit.nodeLU[nm] {
                let nd = circuit.nodes[idx]
                print("QD_DDFS5.\(nm): value=0x\(String(nd.node.value, radix: 16)) updTm=\(nd.updTm)")
            }
        }

        // Direct, path-assumption-free check: read FINE's final state straight
        // off the node table, independent of whatever qualified-name string
        // saveChng/makeNm actually produced for Glbls.allChngs.
        let fineNode = cosLU5.nodes[fineIdx]
        print("FINE final state: value=0x\(String(fineNode.node.value, radix: 16)) updTm=\(fineNode.updTm)")

        // Minimal, defensible invariant, based on the direct node read: FINE
        // must not be stuck at its initial value (updTm == 0, i.e. never
        // written by setNode) for the *entire* run — this is the literal
        // symptom originally reported. Whether the specific timing/values
        // look wrong beyond that is a judgment call for a human familiar
        // with the DDFS pipeline's expected warm-up latency.
        XCTAssertGreaterThan(fineNode.updTm, 0,
                       "FINE was never updated during the whole \(finishTm)-unit run — matches the reported 'stuck at 0' bug")
    }
}
