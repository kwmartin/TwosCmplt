import XCTest
import SharedTypes
@testable import TwosCmplt

// Regression tests for the slice/concat parsing fixes documented in
// Sources/TwosCmplt/TwosCmplt.docc/CircDef.md.
final class SliceConcatRefactorTests: XCTestCase {

    private func emptyCircDef() -> CircDef {
        CircDef(module: "Test", kind: "test", params: [], io_ports: [], decls: [], behav_blcks: [])
    }

    // AssgnAST/SingleConcatAST were field-identical; SingleConcatAST was removed
    // and ConcatStmntAST.concats now holds [AssgnAST] directly.
    func testConcatStmntASTSharesAssgnASTType() {
        var circDef = emptyCircDef()
        let exprId = circDef.internExpr(.int(7))

        let scalarAssgn = AssgnAST(lvalue: .net(name: "a"), rvalue: exprId, delay: 0)
        let concatPart = AssgnAST(lvalue: .bitSelect(name: "b", index: 2), rvalue: exprId, delay: 0)

        let body = AssgnBody(assgns: [scalarAssgn])
        let concatStmt = ConcatStmntAST(node: "b", concats: [concatPart])

        XCTAssertEqual(body.assgns.count, 1)
        XCTAssertEqual(concatStmt.concats.count, 1)
        XCTAssertEqual(concatStmt.concats[0].lwidth, 1)
    }

    // genAssignStmt used to only handle a plain net lvalue and silently emit
    // nothing for a bit-select target. It now routes through the same generic
    // .assgn opcode / setLeftNet path continuous assigns already use.
    func testGenAssignStmtHandlesBitSelectLvalue() {
        var circDef = emptyCircDef()
        let exprId = circDef.internExpr(.int(1))
        let ast = AssgnAST(lvalue: .bitSelect(name: "Q", index: 2), rvalue: exprId, delay: 0)

        let circuit = Circuit(iPrts: [], oPrts: [],
                               nodes: [Nod(name: "Q", value: TwoCmplt(0, nbits: 4))],
                               nodeLU: ["Q": 0])
        circuit.module = "Test"

        var ctx = Context(circDef: circDef)
        ctx.circ = circuit

        genAssignStmt(ast, ctx: &ctx)
        XCTAssertFalse(ctx.code.isEmpty, "genAssignStmt must emit code for a bit-select lvalue")

        TwosCmplt.run(ctx: &ctx)

        XCTAssertEqual(circuit.nodes[0].node.value, 0b0100, "bit 2 of Q should now be set")
    }

    // evalExpr's .select case used to round-trip through a syscall("select_...")
    // that doesn't exist, silently returning -1. It now calls ctx.getSelect
    // directly, matching the bytecode/VM path used by continuous assigns.
    func testTreeWalkSelectMatchesVMPath() {
        var circDef = emptyCircDef()
        let msbId = circDef.internExpr(.int(3))
        let lsbId = circDef.internExpr(.int(1))
        let selectId = circDef.internExpr(.select(name: "Q", args: [msbId, lsbId]))

        let circuit = Circuit(iPrts: [], oPrts: [],
                               nodes: [Nod(name: "Q", value: TwoCmplt(0b1011, nbits: 4))],
                               nodeLU: ["Q": 0])
        circuit.module = "Test"

        var ctx = Context(circDef: circDef)
        ctx.circ = circuit

        // Tree-walking interpreter path (used inside if/while/case statement bodies).
        let treeWalkResult = evalExpr(selectId, ctx: &ctx)
        XCTAssertNotEqual(treeWalkResult.asInt, -1, "select must no longer silently return -1")
        XCTAssertEqual(treeWalkResult.asInt, 0b101, "Q[3:1] of 0b1011 should be 0b101")

        // Bytecode/VM path (used by continuous assigns and blckst/noblckst).
        let selectExpr = circDef.getExpr(selectId)
        ctx.code = []
        genExpr(selectExpr, ctx: &ctx)
        TwosCmplt.run(ctx: &ctx)
        let vmResult = ctx.pop()

        XCTAssertEqual(treeWalkResult.asInt, vmResult.asInt,
                       "tree-walk and VM evaluation of the same select must agree")
    }

    // genConcatStmt used to call genExpr (which only appends bytecode to
    // ctx.code, never pushes a runtime Value) and then immediately ctx.pop()
    // from the *runtime* stack, which is empty at codegen time. It now emits
    // a .assgn opcode per part instead, mirroring genAssgnStmtCode/the fixed
    // genAssignStmt.
    func testGenConcatStmtWritesAllParts() {
        var circDef = emptyCircDef()
        let bit0Id = circDef.internExpr(.int(1))
        let bit1Id = circDef.internExpr(.int(1))
        let ast = ConcatStmntAST(node: "Q", concats: [
            AssgnAST(lvalue: .bitSelect(name: "Q", index: 0), rvalue: bit0Id, delay: 0),
            AssgnAST(lvalue: .bitSelect(name: "Q", index: 1), rvalue: bit1Id, delay: 0),
        ])

        let circuit = Circuit(iPrts: [], oPrts: [],
                               nodes: [Nod(name: "Q", value: TwoCmplt(0, nbits: 4))],
                               nodeLU: ["Q": 0])
        circuit.module = "Test"

        var ctx = Context(circDef: circDef)
        ctx.circ = circuit

        genConcatStmt(ast, ctx: &ctx)
        XCTAssertFalse(ctx.code.isEmpty, "genConcatStmt must emit code for each part")

        TwosCmplt.run(ctx: &ctx)

        XCTAssertEqual(circuit.nodes[0].node.value, 0b0011, "both bit 0 and bit 1 of Q should now be set")
    }

    // Regression check that deleting the dead busConcat()/Buss/BussArray code
    // and the vestigial Join*/Concat*.yml LogicLib files didn't change the
    // behavior of the .join gate kind, which never depended on any of them.
    func testCNTR3JoinGateReflectsConcatenatedBits() throws {
        guard let circuit = Circuit.make("CNTR3") else {
            XCTFail("Failed to load CNTR3 circuit")
            return
        }
        circuit.name = "TestCNTR3"
        Glbls.topCircuit = circuit

        let (per, finishTm, tmSpcs) = loadSpecs("CNTR3")
        _ = simCircuit(circuit, per: per, finishTm: finishTm, tmSpcs: tmSpcs)

        guard let q0Idx = circuit.nodeLU["Q0"],
              let q1Idx = circuit.nodeLU["Q1"],
              let q2Idx = circuit.nodeLU["Q2"],
              let outIdx = circuit.nodeLU["OUT"] else {
            XCTFail("Expected CNTR3 nodes not found")
            return
        }

        let q0 = circuit.nodes[q0Idx].node.value
        let q1 = circuit.nodes[q1Idx].node.value
        let q2 = circuit.nodes[q2Idx].node.value
        let out = circuit.nodes[outIdx].node.value

        XCTAssertEqual(out, (q2 << 2) | (q1 << 1) | q0,
                       "OUT (driven by the join/concat gate) must equal {Q2,Q1,Q0}")
    }

    // addSeg previously never set the produced slice node's nodeDrvr, nor
    // added the .seg gate to its source node's nodeSinks (nothing reading the
    // slice had a recorded dependency on the gate that drives it), nor
    // registered the new node's name in circuit.nodeLU (so Gate.eval()'s
    // name-based setNode call could never find and update it). All three are
    // now fixed, and the node is correctly tagged .slice.
    func testAddSegTagsSliceAndWiresScheduling() {
        let circuit = Circuit(iPrts: [], oPrts: [],
                               nodes: [Nod(name: "SRC", value: TwoCmplt(0, nbits: 4))],
                               nodeLU: ["SRC": 0])
        circuit.module = "Test"

        let sliceIdx = addSeg(name: "SRC", seg: (3, 1), circuit: circuit)

        XCTAssertEqual(circuit.nodes[sliceIdx].kind, .slice)
        XCTAssertEqual(circuit.nodes[sliceIdx].node.nbits, 3)
        XCTAssertEqual(circuit.aCircs.count, 1, "exactly one .seg gate should have been created")

        let gateIdx = circuit.aCircs.count - 1
        XCTAssertEqual(circuit.nodes[sliceIdx].nodeDrvr, CmpRef(kind: .aCirc, index: gateIdx),
                       "the slice node must record the .seg gate as its driver")
        XCTAssertTrue(circuit.nodes[0].nodeSinks.contains(CmpRef(kind: .aCirc, index: gateIdx)),
                      "the source node must record the .seg gate as a sink")
        XCTAssertEqual(circuit.nodeLU[circuit.nodes[sliceIdx].name], sliceIdx,
                       "the slice node's name must be registered in nodeLU")
    }

    // Gate.eval()'s .seg case previously ignored the stored (msb, lsb) range
    // entirely and just bit-reversed the *whole* source node. Verified here
    // with a genuine partial, asymmetric slice (not the full source width,
    // which the earlier bug could accidentally get "right" by symmetry).
    func testSegGateExtractsCorrectSliceNotReversed() {
        let circuit = Circuit(iPrts: [], oPrts: [],
                               nodes: [Nod(name: "SRC", value: TwoCmplt(0b10110010, nbits: 8))],
                               nodeLU: ["SRC": 0])
        circuit.module = "Test"

        let sliceIdx = addSeg(name: "SRC", seg: (5, 2), circuit: circuit) // bits [5:2] of 0b10110010

        circuit.aCircs[0].eval(tm: 0)

        XCTAssertEqual(circuit.nodes[sliceIdx].node.value, 0b1100,
                       "SRC[5:2] of 0b10110010 should be 0b1100, not a bit-reversal")
    }

    // Option B: a port fed by exactly one segment wires that slice directly,
    // with no concat/join gate inserted.
    func testSegmentedSingleSegmentWiresDirectNoGate() {
        let circuit = Circuit(iPrts: [], oPrts: [],
                               nodes: [Nod(name: "A", value: TwoCmplt(0, nbits: 4))],
                               nodeLU: ["A": 0])
        circuit.module = "Test"

        let port = Port.segmented(port: "p", segments: [Sgmnt(node: "A", width: (3, 0))])
        let result = inPort2Indxs(port: port, circuit: circuit)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(circuit.aCircs.count, 1, "only the .seg gate — no join gate for a single segment")
        XCTAssertEqual(circuit.nodes[result[0]].kind, .slice)
    }

    // Option B: a port fed by two or more segments gets a real .join gate
    // concatenating them into one combined, .simple-kind node.
    func testSegmentedMultiSegmentInsertsJoinGate() {
        let circuit = Circuit(iPrts: [], oPrts: [],
                               nodes: [Nod(name: "A", value: TwoCmplt(0b1010, nbits: 4)),
                                       Nod(name: "B", value: TwoCmplt(0b11, nbits: 2))],
                               nodeLU: ["A": 0, "B": 1])
        circuit.module = "Test"

        let port = Port.segmented(port: "p", segments: [
            Sgmnt(node: "A", width: (3, 0)),
            Sgmnt(node: "B", width: (1, 0)),
        ])
        let result = inPort2Indxs(port: port, circuit: circuit)

        XCTAssertEqual(result.count, 1, "≥2 segments must combine into a single index")
        XCTAssertEqual(circuit.aCircs.count, 3, "2 .seg gates + 1 .join gate")

        let joinIdx = result[0]
        XCTAssertEqual(circuit.nodes[joinIdx].kind, .simple)
        XCTAssertEqual(circuit.nodes[joinIdx].node.nbits, 6, "sum of segment widths (4 + 2)")

        // Evaluate the two .seg gates then the .join gate, in dependency order,
        // and confirm the combined value is the correct concatenation.
        for i in circuit.aCircs.indices {
            circuit.aCircs[i].eval(tm: 0)
        }
        XCTAssertEqual(circuit.nodes[joinIdx].node.value, (0b1010 << 2) | 0b11,
                       "join gate output must equal {A[3:0], B[1:0]}")
    }

    // Regression check: the only three native (kind: subcirc) circuits in the
    // library still load successfully after the addSeg/inPort2Indxs changes.
    func testNativeFormatCircuitsStillLoad() {
        XCTAssertNotNil(Circuit.make("CNTR3"))
        XCTAssertNotNil(Circuit.make("CNTR4"))
        XCTAssertNotNil(Circuit.make("JKFF"))
    }
}
