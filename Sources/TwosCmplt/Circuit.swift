import Foundation
import Yams
import SharedTypes

extension Dictionary {
    func get(_ key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        return self[key] ?? defaultValue()
    }
}

enum CircuitError: Error {
    case missingCircs
    case notAnArray
}

extension Dictionary where Key == String, Value == Int {
    func lu(for name: String) -> Int {
        guard let idx = self[name] else {
            preconditionFailure("Missing node '\(name)' in nodeLU")
        }
        return idx
    }
}

/*
public enum BinOp: Codable {
    case arith(BinArithOp)
    case logic(BinLgcOp)
}

public enum UnryOp: String, Codable {
    case plus = "+"
    case minus = "-"
    case lgcnot = "!"
    case not = "~"
    case and = "&"
    case nand = "~&"
    case or = "|"
    case nor = "~|"
    case xor = "^"
    case xnor = "~^"
}

public enum Opr: Codable {
    case bin(BinOp)
    case unary(UnryOp)
    case cmpr(CmprOpr)
}

public indirect enum Expr: Codable {
    case int(Int)
    case real(Double)
    case node(String)
    case binary(lhs: Expr, op: BinOp, rhs: Expr)
    case unary(op: UnryOp, rhs: Expr)
}

public indirect enum CmprExpr: Codable {
    case node(String)
    case binary(lhs: Expr, op: BinOp, rhs: Expr)
    case unary(op: UnryOp, rhs: Expr)
}

public enum StmntEnum : Codable {
    case dost(DoStmnt)
    case whlst(WhlStmnt)
    case assgnst(AssgnStmnt)
    case concatst(ConcatStmnt)
    case spcfyst(SpcfyStmnt)
    case blckst(BlckStmnt)
    case noblckst(NonblckStmnt)
}

public struct Statement : Codable {
    public let stmnt: StmntEnum
}

*/

/*
public enum StmntEnum : Codable {
    case dost(DoStmnt)
    case whlst(WhlStmnt)
    case assgnst(AssgnStmnt)
    case concatst(ConcatStmnt)
    case spcfyst(SpcfyStmnt)
    case blckst(BlckStmnt)
    case noblckst(NonblckStmnt)
}

public struct Statement : Codable {
    public let stmnt: StmntEnum
}

public struct Block : Codable {
    public let stmnts: [Statement]
}
*/

struct AppConfig: Codable {
    struct Project: Codable {
        let name: String
        let buildDir: String
        let docsDir: String
    }

    struct Paths: Codable {
        let sources: String
        let scripts: String
        let artifacts: String
    }

    let project: Project
    let paths: Paths
}

public enum Kind: String, Sendable, Hashable {
    case inv, buf, and, nand, or, nor, exor, exnor, a_bc, ab_ac, ab_ac_bc, jkq, diclq,
        faddr, haddr, reg, seg, join, custom
}

public enum RegTyp: Int, Sendable, Hashable {
    case dpf=0, dpr=1, dnf=2, dnr=3, d0pf=4, d0pr=5, d0nf=6, d0nr=7
}

public enum SEdge {
    case rise
    case fall
}

public struct Sens {
    public let port: String
    public let edge: SEdge
}

public struct SensWatch: Hashable {
    public let node: Int
    public var value: Int
    public let edge: Edge
    public let alwysIndx: Int
}

public struct Delay {
    public let fixed: Int
    public let outcap: Int
}

public enum ParmEnum: Equatable {
    case int(Int)
    case real(Double)
    case str(String)
}

public struct Parm: Equatable {
    public let name: String
    public let value: ParmEnum

    public init(name: String, value: ParmEnum) {
        self.name = name
        self.value = value
    }
}

public struct ClockSpc {
    public let name: String
    public let initial: Int
    public let period: Int
    public let delay: Int
}

public struct TimeSpc {
    public let tm: Int
    public let vls: [(String, Int)]
}

public enum Signed {
    case unsgnd(Bool)
    case sgnd(Bool)
}

public enum BusElem {
    case bus(String)
    case bit((String, Int))
    case slc((String, Int, Int))
}

public typealias BusArray = [BusElem]

public typealias StrArray = [String]

public enum Buss {
    case int(bit: Int)
    case uint(uint: (Int, Int))
    case twoCmplt(node: TwoCmplt)
    case twoBit(bit: (TwoCmplt, Int))
    case twoSlice(slice: (TwoCmplt, Int, Int))
}

public typealias BussArray = [Buss]

public struct Sgmnt: Decodable {
    let node: String
    let width: (Int, Int)

    private enum CodingKeys: String, CodingKey {
        case node
        case width
    }

    // Memberwise init for your own use
    public init(node: String, width: (Int, Int)) {
        self.node = node
        self.width = width
    }

    // Decodable init for YAML
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let node = try c.decode(String.self, forKey: .node)

        var arr = try c.nestedUnkeyedContainer(forKey: .width)
        let first  = try arr.decode(Int.self)
        let second = try arr.decode(Int.self)

        self.init(node: node, width: (first, second))
    }
}

public enum BusEnum {
    case node(NodeRef)
    case segmented(segments: [Sgmnt])
}

public enum NodeRef {
    case name(String)
    case supply(Int)
}

/*
public struct Port {
    let port: String
    let penum: BusEnum
}
*/

// A PortDef is only appropriate for a Circuit port as it's heavyweight
public struct PortDef: Decodable {
    public var port: String
    public var node: String
    public var nbits: Int
    public var intlIndx: Int
    public var extlIndx: Int
    public var sgmnts: [Sgmnt]?
    // Non-nil when this output port drives a single bit of the parent's multi-bit node.
    // Propagation must merge only this bit rather than overwrite the whole node.
    public var extlBitIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case port
        case node
        case nbits
        case sgmnts
        // no keys for intlIndx / extlIndx / extlBitIndex → they stay internal
    }

    public init(
        port: String,
        node: String,
        nbits: Int = 1,
        intlIndx: Int = 1_000_000,
        extlIndx: Int = 1_000_000,
        sgmnts: [Sgmnt]? = nil,
        extlBitIndex: Int? = nil
    ) {
        self.port = port
        self.node = node
        self.nbits = nbits
        self.intlIndx = intlIndx
        self.extlIndx = extlIndx
        self.sgmnts = sgmnts
        self.extlBitIndex = extlBitIndex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let port   = try c.decode(String.self, forKey: .port)
        let node   = try c.decode(String.self, forKey: .node)
        let nbits  = try c.decodeIfPresent(Int.self, forKey: .nbits) ?? 1
        let sgmnts = try c.decodeIfPresent([Sgmnt].self, forKey: .sgmnts)

        // internal indices are *not* decoded from YAML
        self.port = port
        self.node = node
        self.nbits = nbits
        self.sgmnts = sgmnts
        self.intlIndx = 1_000_000
        self.extlIndx = 1_000_000
        self.extlBitIndex = nil
    }
}

public struct NodeDef {
    public let name: String
    public let nbits: Int
    public var capac: Int = 2

    public init(name: String, nbits: Int) {
        self.name = name
        self.nbits = nbits
    }
}

public enum NodeEnum {
    case name(String)
    case def(NodeDef)
}

public enum Port {
    case node(port: String, node: NodeRef)
    case segmented(port: String, segments: [Sgmnt])
    case arry(StrArray)
    case bus(BusArray)

    public var busCount: Int {

        switch self {
        case let .bus(busArray):
            return busArray.count
        case .node:
            return 1
        default:
            print("Not a .bus port")
            return 0
        }
    }

    public var segments: [Sgmnt] {
        guard case let .segmented(_, segments) = self else {
            preconditionFailure("Expected .segmented port")
        }
        return segments
    }

    public var nodeRef: NodeRef {
        guard case let .node(_, nodeRef) = self else {
            preconditionFailure("Expected .node port")
        }
        return nodeRef
    }

    public var names: [String] {
        guard case let .arry(arr) = self else {
            preconditionFailure("Expected .arry port")
        }
        return arr
    }

    public var segmentedInfo: (port: String, segments: [Sgmnt]) {
        guard case let .segmented(port, segments) = self else {
            preconditionFailure("Expected .segmented port")
        }
        return (port, segments)
    }

    public var nodeInfo: (port: String, node: NodeRef) {
        guard case let .node(port, nodeRef) = self else {
            preconditionFailure("Expected .node port")
        }
        return (port, nodeRef)
    }

}

public enum OutPort {
    case node(String)
    case arry(StrArray)
    case port(port: String, node: String)
}

public struct Param {
    let name: String
    let value: Int
}

public enum CmpType: Sendable {
    case none
    case aCirc
    case sCirc
    case vCirc
    case cCirc
    case iPrt
    case oPrt
}

public struct Cmp {
    let name: String
    let kind: String
    let params: [Param]
    let inPorts: [Port]
    let outPorts: [OutPort]
    let delay: Int
}

public struct CmpRef: Sendable, Hashable {
    let kind: CmpType
    let index: Int
    public private(set) var sync: Bool = false
    static let none = CmpRef(kind: .none, index: 0)
} 

public struct NodeChng {
    public let circIndxs: [Int]
    public let nodeIndx: Int
    public let value: Int
    public let updTm: Int
    public let nbits: Int
    public let capac: Int
}

public struct VCDkey: Hashable, Sendable {
    let circIndxs: [Int]
    let nodeIndx: Int
}

public func makeCmpRefs(_ circ: Circuit) {
    for (i, _) in circ.aCircs.enumerated() {
        let ref = CmpRef(kind: .aCirc, index: i)

        if !circ.cmpRefs.contains(ref) {
            circ.cmpRefs.append(ref)
        }
        circ.refCnts[ref] = 0
    }
    for (i, _) in circ.sCircs.enumerated() {
        let ref = CmpRef(kind: .sCirc, index: i, sync: true)

        if !circ.cmpRefs.contains(ref) {
            circ.cmpRefs.append(ref)
        }
        circ.refCnts[ref] = 0
    }
    for (i, _) in circ.vCircs.enumerated() {
        let ref: CmpRef
        ref = CmpRef(kind: .vCirc, index: i, sync: circ.vCircs[i].sync)

        if !circ.cmpRefs.contains(ref) {
            circ.cmpRefs.append(ref)
        }
    }
    for (i, _) in circ.cCircs.enumerated() {
        let ref: CmpRef
        let sync = circ.cCircs[i].sync
        if circ.kind == "verilog" {
            ref = CmpRef(kind: .vCirc, index: i, sync: sync)
        } else {
            ref = CmpRef(kind: .cCirc, index: i, sync: sync)
        }

        if !circ.cmpRefs.contains(ref) {
            circ.cmpRefs.append(ref)
        }
        circ.refCnts[ref] = 0
    }

    for (i, prt) in circ.oPrts.enumerated() {
        let ref = CmpRef(kind: .oPrt, index: i)
        if !circ.cmpRefs.contains(ref) {
            circ.cmpRefs.append(ref)
            if !circ.nodes[prt.intlIndx].nodeSinks.contains(ref) {
                circ.nodes[prt.intlIndx].nodeSinks.append(ref)
            }
        }
        circ.refCnts[ref] = 0
    }
}


/* getOutRefs returns the nodeSinks from the output nodes driven by ref
 *
 * - Parameter circ: The Circuit containing the CmpRef's
 * - Parameter ref: The CmpRef; return the CmpRef's being driven by ref
 *
 * - Returns: nodeSinks's from node driven by ref
 */
 public func getOutRefs(_ circ: Circuit, _ ref: CmpRef) -> [CmpRef] {
    var outRefs: [CmpRef] = []
    switch ref.kind {
    case .aCirc:
        let acirc = circ.aCircs[ref.index]
        for indx in acirc.outs {
            for rf in circ.nodes[indx].nodeSinks {
                outRefs.append(rf)
            }
        }
    case .sCirc:
        let scirc = circ.sCircs[ref.index]
        for indx in scirc.outs {
            for rf in circ.nodes[indx].nodeSinks {
                outRefs.append(rf)
            }
        }
    case .vCirc:
        let vcirc = circ.cCircs[ref.index]
        for prtDef in vcirc.oPrts {
            for rf in circ.nodes[prtDef.extlIndx].nodeSinks {
                outRefs.append(rf)
            }
        }
    case .cCirc:
        let ccirc = circ.cCircs[ref.index]
        for prtDef in ccirc.oPrts {
            for rf in circ.nodes[prtDef.extlIndx].nodeSinks {
                outRefs.append(rf)
            }
    }
    case .oPrt:
        for prtDef in circ.oPrts {
            if !(circ.parent == nil) {
                outRefs.append(circ.parent!.nodes[prtDef.extlIndx].nodeDrvr)
            }
        }
    default:
        preconditionFailure("Unexpected Failure")
    }
    return outRefs
}

public func sortCmpRefs(_ circ: Circuit) {
    while !circ.sortArry.isEmpty {
        let ref = circ.sortArry.removeFirst()
        // Skip refs already processed (duplicates inserted when multiple predecessors
        // see refCnts[rf]==0 before rf is moved from sortArry to evalOrder).
        if circ.evalOrder.contains(ref) { continue }
        circ.evalOrder.append(ref)
        // get all the CmpRef's being driven by a CmpRef from sortArry
        let refs = getOutRefs(circ, ref)
        for rf in refs{
            if let count = circ.refCnts[rf], count > 0 {
                circ.refCnts[rf] = count - 1
            }
            if circ.refCnts[rf] == 0  && !circ.evalOrder.contains(rf) {
                circ.sortArry.append(rf)
            }
        }
    }
}

public func initializeCmpCnts(_ circ: Circuit) {
    // initialize circ.cmpRefs array so we can later iterate through it
    makeCmpRefs(circ)

    for i in circ.nodes.indices {
        var nd = circ.nodes[i]
        let drvr = nd.nodeDrvr
        if (drvr.kind == .none) || (drvr.kind == .iPrt) || (drvr.kind == .sCirc) || (nd.nodeDrvr.index == -1) {
            continue
        }
        if (drvr.kind == .vCirc || drvr.kind == .cCirc) {
            if circ.isSync(ref: drvr) {
                continue
            }
        }

        if let idx = circ.iPrts.firstIndex(where: { $0.port == nd.name }) {
            circ.iNods.append(idx)
            circ.nodes[i].nodeDrvr = CmpRef(kind: .iPrt, index: i)
            nd = circ.nodes[i]
        }

        for ref in nd.nodeSinks {
            if circ.refCnts[ref] == nil || circ.refCnts[ref] == -1 {
                circ.refCnts[ref, default: 0] = 0
            }
            circ.refCnts[ref]! += 1
        }
    }

    for ref in circ.cmpRefs {
        if circ.refCnts[ref] == 0 {
            circ.sortArry.append(ref)
        }
    }

    // Check for duplicates in cmpRefs or sortArry before sorting
    let cmpRefDups = Dictionary(circ.cmpRefs.map { ($0, 1) }, uniquingKeysWith: +).filter { $0.value > 1 }
    let sortArryDups = Dictionary(circ.sortArry.map { ($0, 1) }, uniquingKeysWith: +).filter { $0.value > 1 }

    sortCmpRefs(circ)
    if circ.evalOrder.count != circ.cmpRefs.count {
        let cCircInfo = circ.cCircs.map { "\($0.module)(sync=\($0.sync))" }.joined(separator: ", ")
        let aCircInfo = circ.aCircs.map { $0.name }.joined(separator: ", ")
        let sCircInfo = circ.sCircs.map { $0.name }.joined(separator: ", ")
        let extraRefs = circ.evalOrder.filter { !circ.cmpRefs.contains($0) }.map { "\($0.kind)[\($0.index)]sync=\($0.sync)" }.joined(separator: ", ")
        let missingRefs = circ.cmpRefs.filter { !circ.evalOrder.contains($0) }.map { "\($0.kind)[\($0.index)]sync=\($0.sync)" }.joined(separator: ", ")
        let evalDupStr = Dictionary(circ.evalOrder.map { ($0, 1) }, uniquingKeysWith: +).filter { $0.value > 1 }.map { "\($0.key.kind)[\($0.key.index)]x\($0.value)" }.joined(separator: ", ")
        let cmpDupStr = cmpRefDups.map { "\($0.key.kind)[\($0.key.index)]x\($0.value)" }.joined(separator: ", ")
        let sortDupStr = sortArryDups.map { "\($0.key.kind)[\($0.key.index)]x\($0.value)" }.joined(separator: ", ")
        let msg = "Evaluation order not determined for '\(circ.module)' evalOrder=\(circ.evalOrder.count) cmpRefs=\(circ.cmpRefs.count)\n  cCircs: [\(cCircInfo)]\n  aCircs: [\(aCircInfo)]\n  sCircs: [\(sCircInfo)]\n  extra in evalOrder: [\(extraRefs)]\n  missing from evalOrder: [\(missingRefs)]\n  evalOrder dups: [\(evalDupStr)]\n  cmpRefs dups: [\(cmpDupStr)]\n  sortArry dups: [\(sortDupStr)]\nmaybe a verilog parameter circuit=sync needs to be added"
        preconditionFailure(msg)
    }
    precondition(circ.evalOrder.count == circ.cmpRefs.count,
        """
        Evaluation order not determined,
        maybe a verilog parameter circuit=sync needs to be added
        """
        )
}

public func getIndxs(_ circ: Circuit) -> [Int] {
    var indxs: [Int] = [circ.index]

    var crc = circ.parent
    var lastCrc: Circuit? = crc ?? nil

    while let cur = crc {
        indxs.append(cur.index)
        lastCrc = cur
        crc = cur.parent
    }

    indxs.reverse()
    circ.head = lastCrc
    return indxs
}

public func setNodeRefs(_ circ: Circuit) {
    for i in circ.nodes.indices {
        circ.nodes[i].nodeDrvr = CmpRef(kind: .none, index: 0)
        circ.nodes[i].nodeSinks = []
    }

    for (aindx, acirc) in circ.aCircs.enumerated() {
        let cmpRef = CmpRef(kind: .aCirc, index: aindx)
        let noneRef = CmpRef(kind: .none, index: 0)
        if !circ.cmpRefs.contains(cmpRef) {
            if circ.cmpRefs.contains(noneRef) {
                circ.cmpRefs = [cmpRef]
            } else {
                circ.cmpRefs.append(cmpRef)
            }
        }
        for idx in acirc.inps {
            if !circ.nodes[idx].nodeSinks.contains(cmpRef) {
                circ.nodes[idx].nodeSinks.append(CmpRef(kind: .aCirc, index: aindx))
            }
        }

        for idx in acirc.outs{
            if circ.nodes[idx].nodeDrvr.kind == .none {
                circ.nodes[idx].nodeDrvr = (CmpRef(kind: .aCirc, index: aindx))
            }
        }
    }

    for (sindx, scirc) in circ.sCircs.enumerated() {
        let cmpRef = CmpRef(kind: .sCirc, index: sindx, sync: true)
        if !circ.cmpRefs.contains(cmpRef) {
            circ.cmpRefs.append(cmpRef)
        }
        for idx in scirc.inps {
            if !circ.nodes[idx].nodeSinks.contains(cmpRef) {
                circ.nodes[idx].nodeSinks.append(CmpRef(kind: .sCirc, index: sindx, sync: true))
            }
        }

        for idx in scirc.outs{
            if circ.nodes[idx].nodeDrvr.kind == .none {
                circ.nodes[idx].nodeDrvr = (CmpRef(kind: .sCirc, index: sindx, sync: true))
            }
        }
    }

    for (vindx, vcirc) in circ.vCircs.enumerated() {
        let cmpRef = CmpRef(kind: .vCirc, index: vindx, sync: true)
        if !circ.cmpRefs.contains(cmpRef) {
            circ.cmpRefs.append(cmpRef)
        }
        for prt in vcirc.iPrts{
            let nd = prt.node
            if nd == "VDD" || nd == "VSS" {
                continue
            } else {
                let idx = circ.nodeLU[nd]!
                if !circ.nodes[idx].nodeSinks.contains(cmpRef) {
                    circ.nodes[idx].nodeSinks.append(CmpRef(kind: .vCirc, index: vindx, sync: true))
                }
            }
        }

        for prt in vcirc.oPrts{
            let nd = prt.node
            let idx = circ.nodeLU[nd]!
            if circ.nodes[idx].nodeDrvr.kind == .none {
                circ.nodes[idx].nodeDrvr = (CmpRef(kind: .vCirc, index: vindx))
            }
        }
    }

    for (cindx, ccirc) in circ.cCircs.enumerated() {
        let ref: CmpRef
        let sync = circ.cCircs[cindx].sync
        if ccirc.kind == "verilog" {
            ref = CmpRef(kind: .vCirc, index: cindx, sync: sync)
        } else {
            ref = CmpRef(kind: .cCirc, index: cindx, sync: sync)
        }

        let cmpRef = ref
        if !circ.cmpRefs.contains(cmpRef) {
            circ.cmpRefs.append(cmpRef)
        }
        for prt in ccirc.iPrts{
            let nd = prt.node
            if nd == "VDD" || nd == "VSS" {
                continue
            }
            guard let idx = circ.nodeLU[baseName(nd)] else { continue }
            if !circ.nodes[idx].nodeSinks.contains(cmpRef) {
                circ.nodes[idx].nodeSinks.append(cmpRef)
            }
        }

        // Set the nodeDrvr for the parent node
        for prt in ccirc.oPrts{
            let nd = prt.node
            if nd == "VDD" || nd == "VSS" {
                continue
            } else {
                let idx = circ.nodeLU[nd]!
                if circ.nodes[idx].nodeDrvr.kind == .none {
                    if ccirc.kind == "verilog" {
                        circ.nodes[idx].nodeDrvr = (CmpRef(kind: .vCirc, index: cindx))
                    } else {
                        circ.nodes[idx].nodeDrvr = (CmpRef(kind: .cCirc, index: cindx))
                    }
                }
            }
        }
    }

    circ.evalOrder.removeAll(keepingCapacity: true)
}

public func saveChng(_ circ: Circuit, indx: Int) {
    var ndStr: String = ""
    let indxs = getIndxs(circ)
    let nd = circ.nodes[indx]
    let ndChng = NodeChng(circIndxs: indxs, nodeIndx: indx, value: nd.node.value,
        updTm: nd.updTm, nbits: nd.node.nbits, capac: nd.capac)
    if !(nd.name == "CLK_") {
        ndStr = makeNm(circ, nodeIndx: indx)
        // print("Time: \(nd.updTm), node: \(ndStr), value: \(nd.node.value)")
        dbg("= Time: \(nd.updTm), node: \(ndStr), value: \(nd.node.value)")
    }
    circ.capacTrns += nd.capac

    Glbls.nodeChngs.append(ndChng)
    Glbls.allChngs.append((ndStr, (nd.updTm, nd.node.value)))
}

public func setOutNd(_ circ: Circuit, indx: Int) {
    let intNd = circ.nodes[circ.oPrts[indx].intlIndx]
    let extlIndx = circ.oPrts[indx].extlIndx
    var extNd = circ.parent!.nodes[circ.oPrts[indx].extlIndx]
    if extNd.node.value != intNd.node.value {
        extNd.node.value = intNd.node.value
        extNd.updTm = intNd.updTm + circ.delay.fixed
        saveChng(circ, indx: extlIndx)
    }
}

// Per-always-block runtime state, per Circuit instance
public struct AlwaysState {
    public var chngWtchs: [SensWatch]?          // nodes edges/changes that trigger eval
    public var noblk: [ScheduledUpdate] = []  // pending non-blocking updates
    public var stack: [Value] = []              // this always-block's private VM stack
    public var blk: [ScheduledUpdate] = []
    public var updTm: Int = -1
}

// Per-init-block runtime state, per Circuit instance
public struct InitState {
    public var noblk: [ScheduledUpdate] = []
    public var stack: [Value] = []
    public var blk: [ScheduledUpdate] = []
    public var updTm: Int = -1
}

public struct AssgnState {
    public var stack: [Value] = []
    public var blk: [ScheduledUpdate] = []
    public var updTm: Int = -1
}

public func genCirc(_ circ_nm: String) -> Circuit? {
    var circDef = Glbls.circDef(for: circ_nm)
    if circDef == nil {
        circDef = makeCircDef(circ_nm)
        if circDef == nil { return nil }
    }
    assert(Glbls.circDef(for: circ_nm) != nil, "Error: making CircDef for \(circ_nm) failed")
    let circ = circDef!.toCircuit()
    return circ
}

public final class Circuit {

    nonisolated(unsafe)
    private static var circuitCache: [String: Circuit] = [:]

    public var module: String = ""
    public var kind: String = ""
    public var name: String = ""
    public var params: [Param] = []
    public var iPrts: [PortDef] = []
    public var oPrts: [PortDef] = []
    public var nodes: [Nod] = []
    public var iNods: [Int] = []
    public var alwaysStates: [AlwaysState] = []   // one per AlwaysBlckAST in CircDef
    public var initStates: [InitState] = []       // one per InitBlckAST in CircDef
    public var assgnStates: [AssgnState] = []   // one per AssgnBlckAST

    var instanceCircDef: CircDef? = nil  // instance-specific CircDef (may have overridden params)
    var aCircs: [Gate] = []
    var sCircs: [Reg] = []
    var vCircs: [Circuit] = []
    var cCircs: [Circuit] = []
    weak var parent: Circuit? = nil
    weak var head: Circuit? = nil
    var cmpRefs: [CmpRef] = []
    var evalOrder: [CmpRef] = []
    var sortArry: [CmpRef] = []
    var refCnts: [CmpRef: Int] = [:]
    public var nodeLU: [String: Int] = ["VSS": 1000000, "VDD": 1000001]
    var snstvLU: [Int: SensWatch] = [:]
    var alwysNoSns: [Int] = []
    var alwysStk: [Int] = []
    var parms: [Parm] = []
    var sens: Sens? = nil // to have simulation of circuit once per clock edge
    var delay: Delay = Delay(fixed: 25, outcap: 10)
    var initialized: Bool = false
    var index: Int = -1
    var indexs: [Int] = []
    var sync: Bool = false
    var capacTrns: Int = 0
    var powerScale: Int = 1024

    public init(circ: Circuit) {
        self.module = circ.module
        self.kind = circ.kind
        self.name = circ.name
        self.nodes = circ.nodes
        self.nodeLU = circ.nodeLU
        self.iPrts = circ.iPrts
        self.oPrts = circ.oPrts
        self.cmpRefs = circ.cmpRefs
        self.aCircs = circ.aCircs
        self.sCircs = circ.sCircs
        self.vCircs = circ.vCircs
        self.cCircs = circ.cCircs
        self.evalOrder = circ.evalOrder
        self.parms = circ.parms
        self.sens = circ.sens
        self.initialized = circ.initialized
    }

    public init(nodes: [Nod], nodeLU: [String:Int], cmpRefs: [CmpRef], evalOrder: [CmpRef]) {
        self.nodes = nodes
        self.nodeLU = nodeLU
        self.cmpRefs = cmpRefs
        self.evalOrder = evalOrder
    }

    // Phase 1: build a minimal circuit from YAML
    static func fromYAML(_ circ_nm: String) -> (Circuit, [String: ArryVal])? {
        guard let ymlStr = try? getCircYmlStr(named: circ_nm),
              let circDct = yamlLoad(ymlStr),
              let nodesVal = circDct["nodes"],
              case let .nodes(nodesArray) = nodesVal
        else { return nil }

        guard let kind = yamlKind(from: ymlStr) else {
            print("Could not determine YAML kind")
            return nil
        }

        if !(kind == "subcircuit" || kind == "subcirc") {
            print("makeCircDef should only called for kind=subcirc and not kind = \(kind)")
            return nil
        }

        var nodeLU: [String: Int] = [:]
        var nodes: [Nod] = []

        for (i, node) in nodesArray.enumerated() {
            switch node {
            case .name(let s):
                nodeLU[s] = i
                nodes.append(Nod(s))
            case .def(let def):
                nodeLU[def.name] = i
                nodes.append(Nod(def.name))
            }
        }

        let circuit = Circuit(nodes: nodes, nodeLU: nodeLU, cmpRefs: [], evalOrder: [])

        guard case let .str(mdl) = circDct["module"] else {
            preconditionFailure("Circuit module must be present")
        }
        circuit.module = mdl

        guard case let .str(typ) = circDct["kind"] else {
            preconditionFailure("Circuit kind must be present")
        }
        circuit.kind = typ

        return (circuit, circDct)
    }

    // Phase 2: mutate the circuit in place
    public func wireFromDict(_ circ_nm: String, circDct: [String: ArryVal]) {
        MakeCircuit(circ_nm, circDct: circDct, circuit: self)
    }

    // Optional factory that does both phases
    public static func make(_ circ_nm: String) -> Circuit? {
        guard let (circuit, circDct) = fromYAML(circ_nm) else { return nil }
        circuit.wireFromDict(circ_nm, circDct: circDct)
        setNodeRefs(circuit)
        if circuit.evalOrder == [] {
            initializeCmpCnts(circuit)
        }

        guard case let .str(typ) = circDct["kind"] else {
            preconditionFailure("Circuit kind must be present")
        }
        circuit.kind = typ

        precondition(!circuit.evalOrder.isEmpty, "Circuit must have a none-empty evalOrder")

        if circuit.parms.contains(Parm(name: "circuit", value: .str("sync"))) {
            circuit.sync = true
        }

        return circuit
    }

    public init(iPrts: [PortDef], oPrts: [PortDef], nodes: [Nod], nodeLU: [String:Int]) {
        self.iPrts = iPrts
        self.oPrts = oPrts
        self.nodes = nodes
        self.nodeLU = nodeLU
    }

    // Main init from yaml file stored in library
    public convenience init?(_ circ_nm: String) {
        // 1) parse YAML → some intermediate representation
        //    (using Yams, etc.)

        guard let ymlStr = try? getCircYmlStr(named: circ_nm) else {
            print("Error: failed to get contents of Yaml file")
            return nil
        }

        guard let circDct = yamlLoad(ymlStr) else {
            print("Failed to load YAML for circuit \(circ_nm), ymlStr: \(ymlStr)")
            return nil
        }

        guard let nodesVal = circDct["nodes"] else {
            print("no nodes entry")
            return nil
        }

        guard case let .nodes(nodesArray) = nodesVal else {
            print("nodes entry is not .nodes")
            return nil
        }

        var nodeLU: [String:Int] = [:]
        var Nodes: [Nod] = []

        for (i, node) in nodesArray.enumerated() {
            switch node {
            case .name(let s):
                // print("plain name: \(s)")
                nodeLU[s] = i
                Nodes.append(Nod(s))

            case .def(let def):
                // print("def name: \(def.name), nbits: \(def.nbits)")
                nodeLU[def.name] = i
                Nodes.append(Nod(def.name))
            }
        }

        let (circuit, cDct) = Circuit.fromYAML(circ_nm)!

        self.init(nodes: circuit.nodes, nodeLU: circuit.nodeLU, cmpRefs: [], evalOrder: [])
        self.module = circuit.module
        self.kind = circuit.kind

        // MakeCircuit is the main function (in CircuitIO) to construct a Circuit from a YamlDct
        MakeCircuit(circ_nm, circDct: cDct, circuit: self)
    }

    // Initializing a circuit using Circuit(named: "Module") first trys to retrieve the Circuit from a cache
    // When the Circuit has already been cached, Yaml lookup is not necessary, sorting evalOrder is not necessary
    public convenience init?(module: String, name: String) {
        if let cached = Circuit.circuitCache[module] {
            self.init(circ: cached)
            self.name = name
            return
        }

        // Build a new Circuit from YAML
        guard let circuit = Circuit.make(module) else {
            return nil
        }
        circuit.name = name

        if circuit.evalOrder == [] {
            initializeCmpCnts(circuit) // already done since we changed to .make(module)
        }

        // Cache the instance
        Circuit.circuitCache[module] = circuit

        // Initialize self as an alias of the cached instance
        /*
        self.init(nodes: circuit.nodes, nodeLU: circuit.nodeLU,
            cmpRefs: circuit.cmpRefs, evalOrder: circuit.evalOrder)
            */
        self.init(circ: circuit)
    }

    func attachBehavior(from circDef: CircDef) {
        let alwaysCount = circDef.alwaysBlcks.count
        self.alwaysStates = Array(
            repeating: AlwaysState(),
            count: alwaysCount
        )

        let initCount = circDef.initBlcks.count
        self.initStates = Array(
            repeating: InitState(),
            count: initCount
        )

        let assgnCount = circDef.assgnBlcks.count
        self.assgnStates = Array(
            repeating: AssgnState(),
            count: assgnCount
        )
    }

    func setNode(_ ndNm: String, val: Int, tm: Int) {
        guard let ndIndx = self.nodeLU[ndNm] else {
            print("⚠️ setNode: node '\(ndNm)' not found in circuit '\(self.module)' — skipping")
            return
        }
        if self.nodes[ndIndx].node.value != val {
            self.nodes[ndIndx].prevValue = self.nodes[ndIndx].node.value
            self.nodes[ndIndx].node.value = val
            self.nodes[ndIndx].updTm = tm
            let wtch = self.snstvLU[ndIndx]
            // stack alwysBlcks for any sense triggers
            if wtch != nil {
                switch wtch!.edge {
                case .posedge:
                    if wtch!.value == 0 && val == 1 {
                        self.alwysStk.append(wtch!.alwysIndx)
                    }
                case .negedge:
                    if wtch!.value == 1 && val == 0 {
                        self.alwysStk.append(wtch!.alwysIndx)
                    }
                case .all:
                    if (wtch!.value^val != 0)  {
                        self.alwysStk.append(wtch!.alwysIndx)
                    }
                case .level:
                    if (wtch!.value^val != 0)  {
                        self.alwysStk.append(wtch!.alwysIndx)
                    }
                }
                self.snstvLU[ndIndx]!.value = val
            }
            saveChng(self, indx: ndIndx)
        }
    }

    // Merge a single bit into a multi-bit node without disturbing other bits.
    // Used when a gate drives only one bit of a wider bus (e.g. b1_15 → QD_[15]).
    func setNodeBit(_ ndNm: String, bitIndex: Int, bitVal: Int, tm: Int) {
        guard let ndIndx = self.nodeLU[ndNm] else {
            preconditionFailure("Node not found: '\(ndNm)' in circuit '\(self.module)'")
        }
        let oldVal = self.nodes[ndIndx].node.value
        let newVal = (oldVal & ~(1 << bitIndex)) | ((bitVal & 1) << bitIndex)
        if oldVal != newVal {
            self.nodes[ndIndx].prevValue = oldVal
            self.nodes[ndIndx].node.value = newVal
            self.nodes[ndIndx].updTm = tm
            let wtch = self.snstvLU[ndIndx]
            if wtch != nil {
                switch wtch!.edge {
                case .posedge:
                    if wtch!.value == 0 && newVal == 1 {
                        self.alwysStk.append(wtch!.alwysIndx)
                    }
                case .negedge:
                    if wtch!.value == 1 && newVal == 0 {
                        self.alwysStk.append(wtch!.alwysIndx)
                    }
                case .all:
                    if (wtch!.value ^ newVal) != 0 {
                        self.alwysStk.append(wtch!.alwysIndx)
                    }
                case .level:
                    if (wtch!.value ^ newVal) != 0 {
                        self.alwysStk.append(wtch!.alwysIndx)
                    }
                }
                self.snstvLU[ndIndx]!.value = newVal
            }
            saveChng(self, indx: ndIndx)
        }
    }

    func eval(async: Bool, tm: Int) {
        // first set all input nodes, and then evaluate Cmps in order
        // set previously at init
        // print("In cCirc evaluation of: \(self.name) at time \(tm)")

        dbg("= \(self.module), name: \(self.name), tm: \(tm)")

        var ctx: Context!
        if self.kind == "verilog" {
            let circDefForCtx = self.instanceCircDef ?? Glbls.circDef(for: self.module)!
            ctx = Context(circDef: circDefForCtx)
        }

        if self.parent != nil {
            for prt in self.iPrts {
                if prt.node == "VDD" {
                    self.setNode(prt.port, val: 1, tm: tm)
                    continue
                }
                if prt.node == "VSS" {
                    self.setNode(prt.port, val: 0, tm: tm)
                    continue
                }
                let extlNd = self.parent!.nodes[prt.extlIndx]
                // If the port connection is a bit-slice (e.g. "FRQ[33:16]"), extract those bits.
                let portVal: Int
                if let bracketRange = prt.node.range(of: "[") {
                    let spec = String(prt.node[bracketRange.upperBound...].dropLast()) // "33:16" or "3"
                    if let colon = spec.firstIndex(of: ":") {
                        let msb = Int(spec[..<colon]) ?? 0
                        let lsb = Int(spec[spec.index(after: colon)...]) ?? 0
                        portVal = extlNd.node.selBits(n1: msb, n2: lsb).value
                    } else {
                        let bit = Int(spec) ?? 0
                        portVal = extlNd.node.selBits(n1: bit, n2: bit).value
                    }
                } else {
                    portVal = extlNd.node.value
                }
                self.setNode(prt.port, val: portVal, tm: extlNd.updTm)
            }
        }

        if self.kind == "verilog" && self.initialized == false {
            for (i, circ) in cCircs.enumerated() {
                let cDef = circ.instanceCircDef ?? Glbls.circDef(for: cCircs[i].module)!
                var vctx = Context(circDef: cDef)
                vctx.circ = cCircs[i]
                // attachBehavior (inside simVrlgInits) must run before setChngWtchs
                // so that alwaysStates is populated when watchers are registered.
                circ.simVrlgInits(ctx: &vctx)
                circ.setChngWtchs(cDef)
            }
            self.simVrlgInits(ctx: &ctx)
            self.setChngWtchs(ctx.circDef)
            self.initialized = true
        }

        // Latest input-arrival time: used in both the initial assign run and the
        // post-always-block re-run so that accumulated upstream delays propagate
        // through the full combinational chain (e.g. CMPL after ADDR, H/F after MLT1).
        let inputTm = (self.kind == "verilog" && !self.sync)
            ? self.iPrts.reduce(tm) { max($0, self.nodes[$1.intlIndx].updTm) }
            : tm

        if self.kind == "verilog" {
            if !self.assgnStates.isEmpty {
                ctx.circ = self
                ctx.simTime = inputTm
                self.runAllAssignBlcks(ctx: &ctx)
            }
        }

        if async == true {
            for cmp in evalOrder {
                switch cmp.kind {
                case .aCirc:
                    // print("In: \(self.name), evaluating aCirc[\(cmp.index)]")
                    dbg("In: \(self.name), evaluating aCirc[\(cmp.index)]")
                    aCircs[cmp.index].eval(tm: tm)
                case .sCirc:
                    // print("In: \(self.name), evaluating sCirc[\(cmp.index)]")
                    sCircs[cmp.index].eval(tm: tm)
                case .vCirc:
                    dbg("In: \(self.name), evaluating vCirc[\(cmp.index)]")
                    let circ = cCircs[cmp.index]
                    ctx.circ = circ
                    circ.eval(async: true, tm: tm)
                    continue
                case .cCirc:
                    // print("In: \(self.name), evaluating cCirc[\(cmp.index)] with name: \(cCircs[cmp.index].name)")
                    dbg("In: \(self.name), evaluating cCirc[\(cmp.index)] with name: \(cCircs[cmp.index].name)")
                    cCircs[cmp.index].eval(async: true, tm: tm)
                default:
                    // print("not .aCirc or .cCirc, skipping")
                    break
                }
            }
        } else {
            for cmp in evalOrder {
                switch cmp.kind {
                case .aCirc:
                    // print("In: \(self.name), not evaluating aCirc[\(cmp.index)]")
                    dbg("In: \(self.name), not evaluating aCirc[\(cmp.index)]")
                    // aCircs[cmp.index].eval(tm: tm)
                case .sCirc:
                    // print("In: \(self.name), evaluating sCirc[\(cmp.index)]")
                    sCircs[cmp.index].eval(tm: tm)
                case .vCirc:
                    // print("In: \(self.name), evaluating vCirc[\(cmp.index)]")
                    dbg("In: \(self.name), evaluating vCirc[\(cmp.index)]")
                    let circ = cCircs[cmp.index]
                    if circ.sync {
                        circ.eval(async: false, tm: tm)
                    } else {
                        circ.eval(async: true, tm: tm)
                    }
                    // circ.simVrlgAlwys(ctx: &ctx)
                    // vCircs[cmp.index].eval(async: false, tm: tm)
                case .cCirc:
                    // print("In: \(self.name), evaluating cCirc[\(cmp.index)] with name: \(cCircs[cmp.index].name)")
                    dbg("In: \(self.name), evaluating cCirc[\(cmp.index)] with name: \(cCircs[cmp.index].name)")
                    cCircs[cmp.index].eval(async: false, tm: tm)
                default:
                    // print("not .sCirc or .vCirc or .cCirc, skipping")
                    break
                }
            }
        }

        if self.kind == "verilog" && !self.alwaysStates.isEmpty {
            for indx in self.alwysNoSns {
                self.alwysStk.append(indx)
            }
            if !self.alwysStk.isEmpty {
                ctx.circ = self
                ctx.simTime = inputTm
                self.simVrlgAlwys(ctx: &ctx)
                self.alwysStk = []
            }

            if !self.assgnStates.isEmpty {
                self.runAllAssignBlcks(ctx: &ctx)
            }

        }

        for cmp in evalOrder {
            switch cmp.kind {
            case .aCirc:
                dbg("In: \(self.name), evaluating aCirc[\(cmp.index)]")
                aCircs[cmp.index].eval(tm: tm)
            default:
                break
            }
        }

        if self.parent != nil {
            for prt in self.oPrts {
                let nd = self.nodes[prt.intlIndx]
                if let bitIdx = prt.extlBitIndex {
                    self.parent!.setNodeBit(prt.node, bitIndex: bitIdx, bitVal: nd.node.value, tm: nd.updTm)
                } else {
                    self.parent!.setNode(prt.node, val: nd.node.value, tm: nd.updTm)
                }
            }
        }
    }

    func resolveCircPort(port: Port, circuit: Circuit) -> PortDef {
        switch port {

        case let .node(pName, nodeRef):

            switch nodeRef {

            case let .name(name):
                let extlIndx = circuit.nodeLU[name]!
                let intlIndx = self.nodeLU[pName]!

                let nbits = circuit.nodes[extlIndx].node.nbits

                let prtDef = PortDef(
                    port: pName,
                    node: name,
                    nbits: nbits,
                    intlIndx: intlIndx,
                    extlIndx: extlIndx,
                    sgmnts: []
                    )

                return prtDef

            case let .supply(val):
                switch val {
                case 0: return PortDef(port: pName, node: "VSS", nbits: 1, intlIndx: 1000000)
                case 1: return PortDef(port: pName, node: "VDD", nbits: 1, intlIndx: 1000001)
                default: preconditionFailure("Invalid supply value: \(val)")
                }
            }

        case let .segmented(pName, segments):
            var sgs: [Sgmnt] = []
            var wdth: (Int, Int)
            for seg in segments {
                wdth = circSeg(name: seg.node, seg: seg.width, circuit: circuit)
                let sg = Sgmnt(node: seg.node, width: wdth)
                sgs.append(sg)
            }
            return PortDef(port: pName, node: "", nbits: 0, extlIndx: -1, sgmnts: sgs)

        default: preconditionFailure("Only .node or .segmented enums allowed fof Circuit Cmps")

        }
    }

    func resolveCircPort(port: OutPort, circuit: Circuit) -> PortDef {
        switch port {

        case let .port(pName, nName):
            let extlIndx = circuit.nodeLU[nName]!
            let intlIndx = self.nodeLU[pName]!
            let nbits = circuit.nodes[extlIndx].node.nbits
            return PortDef(port: pName, node: nName, nbits: nbits, intlIndx: intlIndx, extlIndx: extlIndx)

        default: preconditionFailure("Only .node enum allowed fof Circuit OutPort")

        }
    }
}

extension Circuit {
    // Build from a CircDef YAML (Verilog-derived)
    public static func make(fromSubcircYAML yaml: String) throws -> Circuit {
        // Decode the high-level structure
        var file = try YAMLDecoder().decode(CircDef.self, from: yaml)

        // Build the [String: ArryVal] dict that MakeCircuit expects
        let circDct = file.toCircuitDict()

        // Extract nodes from circDct["nodes"] exactly as fromYAML does
        guard let nodesVal = circDct["nodes"],
              case let .nodes(nodesArray) = nodesVal
        else {
            preconditionFailure("No 'nodes' entry for subcircuit \(file.module)")
        }

        var nodeLU: [String: Int] = [:]
        var nodes: [Nod] = []

        for (i, node) in nodesArray.enumerated() {
            switch node {
            case .name(let s):
                nodeLU[s] = i
                nodes.append(Nod(s))

            case .def(let def):
                nodeLU[def.name] = i
                nodes.append(Nod(def.name))
            }
        }

        // Minimal Circuit with nodes + nodeLU
        let circuit = Circuit(nodes: nodes, nodeLU: nodeLU, cmpRefs: [], evalOrder: [])
        circuit.module = file.module
        circuit.kind   = file.kind

        // Wire in all ports and components
        circuit.wireFromDict(file.module, circDct: circDct)

        // Initialize evalOrder if needed
        if circuit.evalOrder.isEmpty {
            initializeCmpCnts(circuit)
        }
        precondition(!circuit.evalOrder.isEmpty, "Circuit must have a non-empty evalOrder")

        if circuit.parms.contains(Parm(name: "circuit", value: .str("sync"))) {
            circuit.sync = true
        }

        return circuit
    }
}

extension Circuit {
    public func setChngWtchs(_ cirDf: CircDef) {
        if self.alwaysStates.isEmpty {
            return
        }

        for (indx, blk) in cirDf.alwaysBlcks.enumerated() {
            alwaysStates[indx].chngWtchs = []
            let snstvs = blk.snstvs!
            if snstvs.isEmpty {
                self.alwysNoSns.append(indx)
                self.alwysStk.append(indx)
            }
            var st = alwaysStates[indx]
            for sns in snstvs {
                switch sns {
                case .edgePos(let nd_nm):
                    let ndIndx = self.nodeLU[nd_nm]!
                    let curVal = self.nodes[ndIndx].node.value
                    let wtch = SensWatch(node: ndIndx,
                        value: curVal, edge: .posedge, alwysIndx: indx)
                    st.chngWtchs!.append(wtch)
                    let wtch_ = self.snstvLU[ndIndx]
                    if wtch_ == nil {
                        self.snstvLU[ndIndx] = wtch
                    }
                case .edgeNeg(let nd_nm):
                    let ndIndx = self.nodeLU[nd_nm]!
                    let curVal = self.nodes[ndIndx].node.value
                    let wtch = SensWatch(node: self.nodeLU[nd_nm]!,
                        value: curVal, edge: .negedge, alwysIndx: indx)
                    st.chngWtchs!.append(wtch)
                    let wtch_ = self.snstvLU[ndIndx]
                    if wtch_ == nil {
                        self.snstvLU[ndIndx] = wtch
                    }
                case .all(let nd_nm):
                    let ndIndx = self.nodeLU[nd_nm]!
                    let curVal = self.nodes[ndIndx].node.value
                    let wtch = SensWatch(node: ndIndx,
                        value: curVal, edge: .all, alwysIndx: indx)
                    st.chngWtchs!.append(wtch)
                    if self.snstvLU[ndIndx] == nil {
                        self.snstvLU[ndIndx] = wtch
                    }
                case .level(let nd_nm):
                    let ndIndx = self.nodeLU[nd_nm]!
                    let curVal = self.nodes[ndIndx].node.value
                    let wtch = SensWatch(node: ndIndx,
                        value: curVal, edge: .level, alwysIndx: indx)
                    st.chngWtchs!.append(wtch)
                    if self.snstvLU[ndIndx] == nil {
                        self.snstvLU[ndIndx] = wtch
                    }
                }
            }
            alwaysStates[indx] = st
        }
    }
}

extension Circuit {
    func simVrlgInits(ctx: inout Context) {
        // print("Entered simulateInit() to simulate \(self.name)")
        dbg("= module: \(self.module),name: \(self.name)")
        ctx.circDef = self.instanceCircDef ?? Glbls.circDef(for: self.module)!
        self.attachBehavior(from: ctx.circDef)

        let startDepth = ctx.stack.count

        // runAllInitBlcks(on: &circuit, ctx: &ctx)
        ctx.circ = self
        if !self.initStates.isEmpty {
            self.runAllInitBlcks(ctx: &ctx)
        }
        if !self.assgnStates.isEmpty {
            self.runAllAssignBlcks(ctx: &ctx)
        }

        precondition(ctx.stack.count == startDepth,
                    "Stack leak")
        self.initialized = true
    }

    func simVrlgAlwys(ctx: inout Context) {
        // print("Entered simVrlgAlwys() to simulate module: \(ctx.circ!.module) named \(ctx.circ!.name)")
        dbg("= module: \(ctx.circ!.module), name: \(ctx.circ!.name)")
        // circuit.attachBehavior(from: ctx.circDef)

        let startDepth = ctx.stack.count

        // runAllInitBlcks(on: &circuit, ctx: &ctx)
        if !ctx.circDef.assgnBlcks.isEmpty { self.runAllAssignBlcks(ctx: &ctx) } // Currently this should be empty

        for alwysIndx in self.alwysStk {
            self.runAlwysBlck(alwysIndx, ctx: &ctx)
        }


        // self.runAllAlwaysBlcks(ctx: &ctx)
        precondition(ctx.stack.count == startDepth,
                    "Stack leak")
    }
}

extension Circuit {
    func runAllAssignBlcks(ctx: inout Context) {
        let def = ctx.circDef
        for (i, assgnBlk) in def.assgnBlcks.enumerated() {
            ctx.behavIdx = BehavBlockKind.assgnBlock(i)
            let savedCode  = ctx.code
            let savedStack = ctx.stack
            ctx.code  = assgnBlk.code
            ctx.stack = []
            run(ctx: &ctx)
            ctx.code  = savedCode
            ctx.stack = savedStack
        }
    }
}

extension Circuit {
    func runAllInitBlcks(ctx: inout Context) {
        let def = ctx.circDef
        let circuit = ctx.circ!

        for (i, initBlk) in def.initBlcks.enumerated() {
            ctx.behavIdx = .initBlock(i)

            // Load this block's code and private stack into the Context
            ctx.code = initBlk.code
            ctx.stack = circuit.initStates[i].stack

            // Execute the block's instructions
            run(ctx: &ctx)

            // Save back the updated stack
            circuit.initStates[i].stack = ctx.stack

            ctx.behavIdx = nil
        }
    }
}

extension Circuit {
    func runAllAlwaysBlcks(ctx: inout Context) {
        let def = ctx.circDef
        let circuit = ctx.circ!

        for (i, alwaysBlk) in def.alwaysBlcks.enumerated() {

            if !ctx.circ!.alwaysStates[i].noblk.isEmpty {
            
            }
            ctx.behavIdx = .alwaysBlock(i)

            ctx.code = alwaysBlk.code
            ctx.stack = circuit.alwaysStates[i].stack

            run(ctx: &ctx)

            circuit.alwaysStates[i].stack = ctx.stack

            ctx.behavIdx = nil
        }
        writeNonBlocking(ctx: &ctx)
    }
}

extension Circuit {
    func runAlwysBlck(_ indx: Int, ctx: inout Context) {
        let def = ctx.circDef
        let circuit = ctx.circ!
        let alwysBlck = def.alwaysBlcks[indx]
        var alwysSt = circuit.alwaysStates[indx]

        ctx.behavIdx = .alwaysBlock(indx)

        ctx.code = alwysBlck.code
        ctx.stack = alwysSt.stack

        // Only set isEdgeTriggered for clocked (posedge/negedge) always blocks.
        // Combinational blocks (edge: all/level) must read the current value of
        // nodes updated in the same cycle, even if their updTm is a future timestamp.
        let hasClockEdge = alwysBlck.snstvs?.contains(where: {
            if case .edgePos = $0 { return true }
            if case .edgeNeg = $0 { return true }
            return false
        }) ?? false
        ctx.isEdgeTriggered = hasClockEdge
        run(ctx: &ctx)
        ctx.isEdgeTriggered = false

        alwysSt.stack = ctx.stack
        ctx.behavIdx = nil
        writeNonBlocking(ctx: &ctx)
    }
}

extension Circuit {
    func isSync(ref: CmpRef) -> Bool {
        if ref.kind == .sCirc {
            return true
        }
        if (ref.kind == .vCirc) || (ref.kind == .cCirc) {
            if self.cCircs[ref.index].sync == true {
                return true
            } else {
                return false
            }
        }
    return false
    }
}
