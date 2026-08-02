import Yams
import Glibc
import SharedTypes

public extension Node.Mapping {
    /// Lookup by scalar string key. Returns nil if key missing or key can't be formed.
    func value(forKey key: String) -> Node? {
        let scalar = Node.Scalar(key)          // <- qualify as Node.Scalar
        let keyNode = Node.scalar(scalar)
        guard let mappingKey = try? Node.Mapping.Key(keyNode) else {
            return nil
        }
        return self[mappingKey]
    }

    /// All scalar string keys in this mapping.
    var stringKeys: [String] {
        compactMap { (keyNode, _) in keyNode.scalar?.string }
    }
}

public struct TaggedNode {
    public let kind: String // "record" for fixed-shape nodes, or enum case name
    public let raw: Node // the original YAML node

    public init(kind: String, raw: Node) {
        self.kind = kind
        self.raw = raw
    }
}

public enum TaggedNodeError: Error {
    case notASequence
    case notAMapping
    case missingKind
    case nonScalarKind
}

public func makeTaggedNode(from node: Node,
                           kindKey: String = "kind",
                           defaultKind: String = "record") throws -> TaggedNode {
    guard let mapping = node.mapping else {
        throw TaggedNodeError.notAMapping
    }

    if let kindNode = mapping.value(forKey: kindKey),
       let scalar = kindNode.scalar {
        return TaggedNode(kind: scalar.string, raw: node)
    }

    // No "kind" field → treat as fixed-shape record
    return TaggedNode(kind: defaultKind, raw: node)
}

/// Tag every element of a sequence node.
public func makeTaggedNodes(from sequenceNode: Node,
                            kindKey: String = "kind",
                            defaultKind: String = "record") throws -> [TaggedNode] {
    guard let seq = sequenceNode.sequence else {
        throw TaggedNodeError.notASequence
    }

    return try seq.map {
        try makeTaggedNode(from: $0,
                           kindKey: kindKey,
                           defaultKind: defaultKind)
    }
}

/* Example usage
let root = try Yams.compose(yaml: yamlString)!

if let mapping = root.mapping,
   let someArrayNode = mapping[Node(string: "stmnts")] {
    let taggedStmnts = try makeTaggedNodes(from: someArrayNode,
                                           defaultKind: "record",
                                           kindKey: "kind")
    // taggedStmnts: [TaggedNode], each with .kind and .raw
}

if let mapping = root.mapping {
    let someArrayNode = mapping.value(forKey: "stmnts")  // Node?
    let allKeys = mapping.stringKeys                     // [String]
}

let root = try Yams.compose(yaml: yamlString)!

guard let mapping = root.mapping,
      let stmntsNode = mapping.value(forKey: "stmnts") else {
    // no "stmnts" key → stmntsNode is nil here
    // handle missing field
    fatalError("stmnts missing")
}

let taggedStmnts = try makeTaggedNodes(from: stmntsNode)
// taggedStmnts: [TaggedNode] with .kind and .raw

struct AssgnStmntYAML: Decodable {
    let kind: String
    let lvalue: String
    let rvalue: String
}

struct IfStmntYAML: Decodable {
    let kind: String
    let cmpr: String
    let tBlock: [AssgnStmntYAML]
}

enum StmntYAML {
    case assign(AssgnStmntYAML)
    case `if`(IfStmntYAML)
    case unknown(TaggedNode)   // optional fallback
}

extension TaggedNode {
    func toStatement(using decoder: YAMLDecoder) throws -> StmntYAML {
        switch kind {
        case "assign":
            let v = try decoder.decode(AssgnStmntYAML.self, from: raw)
            return .assign(v)

        case "if":
            let v = try decoder.decode(IfStmntYAML.self, from: raw)
            return .if(v)

        default:
            // either throw, or keep as "unknown" for forward compatibility
            return .unknown(self)
            // or:
            // throw DecodingError.dataCorrupted(
            //     .init(codingPath: [],
            //           debugDescription: "Unknown statement kind: \(kind)")
            // )
        }
    }
}

let decoder = YAMLDecoder()
let taggedStmnts: [TaggedNode] = try makeTaggedNodes(from: stmntsNode)

let stmts: [StmntYAML] = try taggedStmnts.map {
    try $0.toStatement(using: decoder)
}

*/

func yamlKind(from yaml: String) -> String? {
    for rawLine in yaml.split(whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)

        if line.isEmpty || line.hasPrefix("#") {
            continue
        }

        // top-level key only
        if line.hasPrefix("kind:") {
            let value = line.dropFirst("kind:".count)
                .trimmingCharacters(in: .whitespaces)

            return value.isEmpty ? nil : value
        }
    }
    return nil
}

public func makeCircDef(_ mdlNm: String, circ: Circuit? = nil) -> CircDef? {
    if let circDF = Glbls.circDef(for: mdlNm) {
        for blk in circDF.behav_blcks {
            if case .instncblck(let inst)   = blk { _ = makeCircDef(inst.module) }
            if case .subcircblck(let inst)  = blk { _ = makeCircDef(inst.module) }
            if case .asyncblck(let inst)    = blk { _ = makeCircDef(inst.module) }
            if case .syncblck(let inst)     = blk { _ = makeCircDef(inst.module) }
        }
        return circDF
    }

    guard let ymlStr = try? getCircYmlStr(named: mdlNm)
    else { return nil }

    guard let kind = yamlKind(from: ymlStr) else {
        print("Could not determine YAML kind")
        return nil
    }

    if kind == "subcircuit" || kind == "subcirc" {
        print("makeCircDef should only called for kind=verilog and not kind = \(kind)")
        return nil
    }

    // let startMsg = "makeCircDef: decoding \(mdlNm)\n"
    // _ = startMsg.withCString { Glibc.write(2, $0, startMsg.utf8.count) }

    var circDF: CircDef
    do {
        // debugBehavBlock6RValue(ymlStr)
        circDF = try YAMLDecoder().decode(CircDef.self, from: ymlStr)
        // print(circDF)
    } catch let error as DecodingError {
        switch error {
        case .dataCorrupted(let context):
            print("DecodingError.dataCorrupted")
            print("debugDescription:", context.debugDescription)
            print("codingPath:", context.codingPath.map(\.stringValue).joined(separator: " -> "))

            if let underlying = context.underlyingError {
                print("underlyingError:", underlying)
            }

        case .keyNotFound(let key, let context):
            print("DecodingError.keyNotFound:", key.stringValue)
            print("debugDescription:", context.debugDescription)
            print("codingPath:", context.codingPath.map(\.stringValue).joined(separator: " -> "))

        case .typeMismatch(let type, let context):
            print("DecodingError.typeMismatch:", type)
            print("debugDescription:", context.debugDescription)
            print("codingPath:", context.codingPath.map(\.stringValue).joined(separator: " -> "))

            if let underlying = context.underlyingError {
                print("underlyingError:", underlying)
            }

        case .valueNotFound(let type, let context):
            print("DecodingError.valueNotFound:", type)
            print("debugDescription:", context.debugDescription)
            print("codingPath:", context.codingPath.map(\.stringValue).joined(separator: " -> "))

            if let underlying = context.underlyingError {
                print("underlyingError:", underlying)
            }

        @unknown default:
            print("Unknown DecodingError:", error)
        }

        let failMsg = "DECODE FAIL for circuit: \(mdlNm)\n"
        _ = failMsg.withCString { Glibc.write(2, $0, failMsg.utf8.count) }
        fatalError("Failed to decode CircDef")
    } catch {
        let failMsg = "Other error in circuit \(mdlNm): \(error)\n"
        _ = failMsg.withCString { Glibc.write(2, $0, failMsg.utf8.count) }
        fatalError("Failed to decode CircDef")
    }
    // Build behavioral AST into circDF.behav
    _ = circDF.buildBehavAST()

    // Build nodes (mutating)
    _ = circDF.toNodesArryVal()

    if circ != nil {
        circDF.Compile(circ!)
    }

    Glbls.register(circDF)

    for blk in circDF.behav_blcks {
        let depModule: String?
        switch blk {
        case .instncblck(let inst):  depModule = inst.module
        case .subcircblck(let inst): depModule = inst.module
        case .asyncblck(let inst):    depModule = inst.module
        case .syncblck(let inst):     depModule = inst.module
        default:                      depModule = nil
        }
        if let dep = depModule {
            guard makeCircDef(dep) != nil else {
                preconditionFailure(
                    "Module '\(mdlNm)' depends on '\(dep)', but makeCircDef returned nil. " +
                    "Check that Resources/CircuitLib/\(dep).yml exists and is valid."
                )
            }
        }
    }
    return circDF
}

public enum ScalarValue: Decodable {
    case int(Int)
    case dbl(Double)
    case str(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if let i = try? c.decode(Int.self) {
            self = .int(i)
            return
        }
        if let d = try? c.decode(Double.self) {
            self = .dbl(d)
            return
        }
        if let s = try? c.decode(String.self) {
            self = .str(s)
            return
        }

        throw DecodingError.typeMismatch(
            ScalarValue.self,
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected Int, Double, or String for ScalarValue"
            )
        )
    }
}

/*
public struct ParamYAML: Decodable {
    public let kind: String    // "Int"
    public let name: String    // "delay"
    public let value: Value      // 5, or "subcirc"
}
*/

public struct ParamYAML: Decodable {
    public let kind: String       // "Int", "Str", "Real", etc.
    public let name: String
    public let value: ScalarValue // .int / .dbl / .str
}

extension ParamYAML {
    func toParm() -> Parm {
        let v: ParmEnum
        switch value {
        case .int(let i):
            v = .int(i)
        case .dbl(let d):
            v = .real(d)
        case .str(let s):
            v = .str(s)
        }
        return Parm(name: name, value: v)
    }
}

public struct IOPortYAML: Decodable {
    public let name: String
    public let direct: String?
    let width: WidthYAML?
    public let signed: String?

    private enum CodingKeys: String, CodingKey {
        case name, direct, width, signed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name   = try c.decode(String.self, forKey: .name)
        self.direct = try c.decodeIfPresent(String.self, forKey: .direct)
        self.width  = try c.decodeIfPresent(WidthYAML.self, forKey: .width)
        self.signed = try c.decodeIfPresent(String.self, forKey: .signed)
    }

    var nbits: Int {
        guard let w = width else { return 1 }
        return max(1, w.msb - w.lsb + 1)
    }
}

// A minimal expression node used to evaluate parameterized width bounds.
struct LengthYAML: Decodable {
    let kind: String
    let value: [WidthExpr]?
}

public struct WidthExpr: Decodable {
    let kind: String
    let value: Int?
    let name: String?
    let oper: String?
    let args: [WidthExpr]?

    func evaluate(with params: [String: Int]) -> Int? {
        switch kind {
        case "int":  return value
        case "ident": return name.flatMap { params[$0] }
        case "bexpr":
            guard let args, args.count == 2,
                  let a = args[0].evaluate(with: params),
                  let b = args[1].evaluate(with: params) else { return nil }
            switch oper {
            case "BMinus:": return a - b
            case "BPlus:":  return a + b
            case "Times:":  return a * b
            default:        return nil
            }
        default: return nil
        }
    }
}

struct WidthYAML: Decodable {
    var msb: Int
    var lsb: Int
    // Stored when the bound is an expression (ident or bexpr) so it can be
    // resolved later once the module's default params are known.
    var msbExpr: WidthExpr?
    var lsbExpr: WidthExpr?

    mutating func resolve(with params: [String: Int]) {
        if let e = msbExpr, let v = e.evaluate(with: params) { msb = v; msbExpr = nil }
        if let e = lsbExpr, let v = e.evaluate(with: params) { lsb = v; lsbExpr = nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Case 1: bare [Int, Int] (e.g., width: [0, 0])
        if let ints = try? container.decode([Int].self), ints.count == 2 {
            msb = ints[0]; lsb = ints[1]; return
        }

        // Case 2: { kind: width, width: [expr, expr] }
        struct WidthNode: Decodable {
            let kind: String
            let width: [WidthExpr]
        }

        if let node = try? container.decode(WidthNode.self), node.width.count == 2 {
            // Evaluate statically where possible; store expression for deferred resolution.
            let emptyParams: [String: Int] = [:]
            msb = node.width[0].evaluate(with: emptyParams) ?? 0
            lsb = node.width[1].evaluate(with: emptyParams) ?? 0
            msbExpr = (node.width[0].evaluate(with: emptyParams) == nil) ? node.width[0] : nil
            lsbExpr = (node.width[1].evaluate(with: emptyParams) == nil) ? node.width[1] : nil
            return
        }

        // Case 3: bare [WidthExpr, WidthExpr] — e.g. width: [{kind: bexpr, ...}, {kind: int, ...}]
        if let exprs = try? container.decode([WidthExpr].self), exprs.count == 2 {
            let emptyParams: [String: Int] = [:]
            msb = exprs[0].evaluate(with: emptyParams) ?? 0
            lsb = exprs[1].evaluate(with: emptyParams) ?? 0
            msbExpr = (exprs[0].evaluate(with: emptyParams) == nil) ? exprs[0] : nil
            lsbExpr = (exprs[1].evaluate(with: emptyParams) == nil) ? exprs[1] : nil
            return
        }

        throw DecodingError.typeMismatch(
            WidthYAML.self,
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected width as [Int] or {kind: width, width: [expr, expr]}"
            )
        )
    }
}

public struct DeclYAML: Decodable {
    let kind: String
    let name: String
    let signed: String
    var width: WidthYAML
    let length: [LengthYAML]?
}

public struct GateSlot {
    let kind: Kind
    let name: String
    let inps: [Int]
    let outs: [Int]
    let delay: Int
}

public struct CircDef {
    public let module: String
    public let kind: String
    public var params: [ParamYAML]
    public let io_ports: [IOPortYAML]

    public var decls: [[DeclYAML]]
    public var nodes: [Nod] = []
    public let behav_blcks: [BehavBlckYAML]

    public var behav: [BehavBlckAST]
    public var initBlcks: [InitBlckAST] = []
    public var alwaysBlcks: [AlwaysBlckAST] = []
    public var assgnBlcks: [AssgnBlckAST] = []
    public var vrlgInsts: [VrlgInstYAML] = []
    public var gateInsts: [GateInstYAML] = []
    public var aCircs: [Gate] = []
    public var sCircs: [Reg] = []
    public var stmts: [StmntAST]
    public var exprs: [Expr]
    public var timingArcs: [TimingArc] = []

    public init(module: String,
                kind: String,
                params: [ParamYAML],
                io_ports: [IOPortYAML],
                decls: [[DeclYAML]],
                behav_blcks: [BehavBlckYAML]) {
        self.module = module
        self.kind = kind
        self.params = params
        self.io_ports = io_ports
        self.decls = decls
        self.behav_blcks = behav_blcks

        self.behav = []
        self.initBlcks = []
        self.alwaysBlcks = []

        self.exprs = []
        self.stmts = []
        self.timingArcs = []
    }
}

public extension CircDef {
    func toParamsArryVal() -> ArryVal {
        let prms: [Parm] = params.map { $0.toParm() }
        return .prms(prms)
    }
}

public extension CircDef {
    mutating func toNodesArryVal() -> ArryVal {
        nodes.removeAll(keepingCapacity: true)

        var avNodes: [NodeEnum] = []

        let paramInts: [String: Int] = Dictionary(uniqueKeysWithValues:
            params.compactMap { p -> (String, Int)? in
                if case .int(let i) = p.value { return (p.name, i) }
                return nil
            }
        )

        // IO ports — use width from port declaration, resolving param expressions
        for p in io_ports {
            var resolvedWidth = p.width
            resolvedWidth?.resolve(with: paramInts)
            let isSigned = (p.signed == "True")
            let nb = resolvedWidth.map { max(1, $0.msb - $0.lsb + 1) } ?? 1
            let nod = Nod(name: p.name, value: TwoCmplt(0, nbits: nb, signed: isSigned))
            nodes.append(nod)
            avNodes.append(.def(NodeDef(name: p.name, nbits: nb)))
        }

        // Reg/Wire declarations — preserve nbits and signed from the YAML width field.
        // If the name already exists from io_ports (e.g. "output reg QP"), update the
        // existing node's value in place rather than appending a duplicate entry.
        // Emit .def(NodeDef) so MakeCircuit's .def branch propagates the correct nbits.
        for group in decls {
            for d in group where d.kind == "Reg" || d.kind == "Wire" {
                var resolvedDeclWidth = d.width
                resolvedDeclWidth.resolve(with: paramInts)
                let nbits  = max(1, resolvedDeclWidth.msb - resolvedDeclWidth.lsb + 1)
                let newVal = TwoCmplt(0, nbits: nbits, signed: d.signed == "True")

                // Array declaration: create one node per element
                if let lengths = d.length, !lengths.isEmpty,
                   let lenYAML = lengths.first,
                   let loBound = lenYAML.value?[0].evaluate(with: paramInts),
                   let hiBound = lenYAML.value?[1].evaluate(with: paramInts) {
                    let lo = min(loBound, hiBound)
                    let hi = max(loBound, hiBound)
                    for i in lo...hi {
                        let indexedName = "\(d.name)[\(i)]"
                        nodes.append(Nod(name: indexedName, value: newVal))
                        avNodes.append(.def(NodeDef(name: indexedName, nbits: nbits)))
                    }
                    continue
                }

                if let idx = nodes.firstIndex(where: { $0.name == d.name }) {
                    nodes[idx].node = newVal
                    // Upgrade the existing avNodes entry (added by io_ports) to carry nbits.
                    if let avIdx = avNodes.firstIndex(where: {
                        switch $0 {
                        case .name(let n): return n == d.name
                        case .def(let nd): return nd.name == d.name
                        }
                    }) {
                        avNodes[avIdx] = .def(NodeDef(name: d.name, nbits: nbits))
                    }
                } else {
                    nodes.append(Nod(name: d.name, value: newVal))
                    avNodes.append(.def(NodeDef(name: d.name, nbits: nbits)))
                }
            }
        }


        // Implicitly add VDD and VSS if not declared — power rails are assumed present in Verilog
        for supplyName in ["VDD", "VSS"] where !nodes.contains(where: { $0.name == supplyName }) {
            nodes.append(Nod(supplyName))
            avNodes.append(.name(supplyName))
        }

        return .nodes(avNodes)
    }
}

extension CircDef {
    func getNode(_ name: String) -> Nod? {
        nodes.first { $0.name == name }
    }
}

extension CircDef {
    public func toInPrtsArryVal() -> ArryVal {
        var seen = Set<String>()
        var elems: [ArryElem] = []
        for p in io_ports where p.direct?.hasPrefix("Input") == true {
            if seen.insert(p.name).inserted {
                elems.append(.string(p.name))
            }
        }
        for group in decls {
            for d in group where d.kind == "Input" {
                if seen.insert(d.name).inserted {
                    elems.append(.string(d.name))
                }
            }
        }
        return .arry(elems)
    }

    public func toOutPrtsArryVal() -> ArryVal {
        var seen = Set<String>()
        var elems: [ArryElem] = []
        for p in io_ports where p.direct?.hasPrefix("Output") == true {
            if seen.insert(p.name).inserted {
                elems.append(.string(p.name))
            }
        }
        for group in decls {
            for d in group where d.kind == "Output" {
                if seen.insert(d.name).inserted {
                    elems.append(.string(d.name))
                }
            }
        }
        return .arry(elems)
    }
}

public extension CircDef {
    mutating func toCircuitDict() -> [String: ArryVal] {
        var dict: [String: ArryVal] = [:]

        dict["module"]  = .str(module)
        dict["kind"]    = .str(kind)
        dict["params"]  = toParamsArryVal()
        dict["inPrts"]  = toInPrtsArryVal()
        dict["outPrts"] = toOutPrtsArryVal()
        dict["nodes"]   = toNodesArryVal()

        return dict
    }
}

extension CircDef: Decodable {
    enum CodingKeys: String, CodingKey {
        case module
        case kind
        case params
        case io_ports
        case decls
        case behav_blcks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let module   = try c.decode(String.self, forKey: .module)
        let kind     = try c.decode(String.self, forKey: .kind)
        let params   = try c.decodeIfPresent([ParamYAML].self, forKey: .params) ?? []
        let io_ports = try c.decodeIfPresent([IOPortYAML].self, forKey: .io_ports) ?? []
        let rawDecls = try c.decodeIfPresent([[DeclYAML]?].self, forKey: .decls) ?? []
        let decls    = rawDecls.compactMap { $0 }
        let behav    = try c.decodeIfPresent([BehavBlckYAML].self, forKey: .behav_blcks) ?? []

        self.init(module: module,
                  kind: kind,
                  params: params,
                  io_ports: io_ports,
                  decls: decls,
                  behav_blcks: behav)
    }
}

public struct ExprId: Hashable {
    public let raw: Int
}

public struct StmtId: Hashable {
    public let raw: Int
}

extension CircDef {
    public mutating func internExpr(_ e: Expr) -> ExprId {
        let id = ExprId(raw: exprs.count)
        exprs.append(e)
        return id
    }

    public mutating func internStmt(_ s: StmntAST) -> StmtId {
        let id = StmtId(raw: stmts.count)
        stmts.append(s)
        return id
    }

    public func getExpr(_ id: ExprId) -> Expr {
        exprs[id.raw]
    }

    public func getStmt(_ id: StmtId) -> StmntAST {
        stmts[id.raw]
    }
}

public extension CircDef {
    func expr(for id: ExprId) -> Expr {
        exprs[id.raw]
    }

    func stmt(for id: StmtId) -> StmntAST {
        stmts[id.raw]
    }
}

extension CircDef {
    /// Returns the integer value of the given ExprId:
    /// - `.int(i)`   -> i
    /// - `.real(d)`  -> Int(d)
    /// - anything else -> 0
    func intValue(for id: ExprId) -> Int {
        let e = getExpr(id)

        if let i = e.getInt {
            return i
        }

        if let d = e.getReal {
            return Int(d)  // or Int(round(d)) if you prefer
        }

        return 0
    }
}

public extension CircDef {
    mutating func buildBehavAST()  -> [BehavBlckAST] {
        let blocks = behav_blcks.map { $0.toAST(in: &self) }
        self.behav = blocks
        return self.behav
    }
}

public struct GateInstResolved {
    let kind: Kind
    let name: String
    let inps: [Int]
    let outs: [Int]
    let delay: Int
}

extension CircDef {
    // Map a node name -> its index in your nodes array.
    // You already have something equivalent; use that.
    func nodeIndexMap() -> [String: Int] {
        var map: [String: Int] = [:]
        for (i, n) in nodes.enumerated() {
            map[n.name] = i
        }
        return map
    }

    public func resolvedGates() -> [GateInstResolved] {
        let nameToIndex = nodeIndexMap()
        var result: [GateInstResolved] = []

        for gi in gateInsts {
            guard let outName = gi.outputNode,
                  let outIdx = nameToIndex[outName] else {
                continue // or preconditionFailure
            }

            var inIdxs: [Int] = []
            for n in gi.inputNodes {
                if let idx = nameToIndex[n] {
                    inIdxs.append(idx)
                } else {
                    // handle missing node (error/log/continue)
                }
            }

            // Map Verilog gate string to Gate.Kind; for now assume names match
            let kind = Kind(rawValue: gi.gate) ?? .nand

            // For now, reduce delay ExprYAML to an Int (e.g., first value, rounded)
            let delayVal: Int
            if let d = gi.delay?.first {
                delayVal = delayExprToInt(d)
            } else {
                delayVal = 1
            }

            let resolved = GateInstResolved(
                kind: kind,
                name: gi.name,
                inps: inIdxs,
                outs: [outIdx],
                delay: delayVal
            )
            result.append(resolved)
        }

        return result
    }

    private func delayExprToInt(_ expr: ExprYAML) -> Int {
        // Very simple placeholder: you can refine later.
        switch expr {
        case .int(let v):
            return v
        case .float(let d):
            return Int(d.rounded())
        case .binary( /* op, args */ _, let args):
            // Example: assume Times(a, b) and multiply if both literals
            if case let .float(a)? = args.first,
               case let .float(b)? = args.dropFirst().first {
                return Int((a * b).rounded())
            }
            return 1
        default:
            return 1
        }
    }
}

public extension CircDef {
    mutating func clearBehav() {
        initBlcks.removeAll(keepingCapacity: true)
        alwaysBlcks.removeAll(keepingCapacity: true)
        assgnBlcks.removeAll(keepingCapacity: true)
        vrlgInsts.removeAll(keepingCapacity: true)
        gateInsts.removeAll(keepingCapacity: true)
    }
}

public extension CircDef {
    mutating func copyBehav() {
        for blk in behav {
            switch blk {
            case .initblck(let initBlk):
                initBlcks.append(initBlk)

            case .alwaysblck(let alwaysBlk):
                alwaysBlcks.append(alwaysBlk)

            case .assgnblck(let assgnBlk):
                assgnBlcks.append(assgnBlk)

            case .instncblck(let vrlgBlk):
                vrlgInsts.append(vrlgBlk)

            case .subcircblck(let vrlgBlk):
                vrlgInsts.append(vrlgBlk)

            case .asyncblck(let vrlgBlk):
                vrlgInsts.append(vrlgBlk)

            case .syncblck(let vrlgBlk):
                vrlgInsts.append(vrlgBlk)

            case .gateblck(let gateBlk):
                gateInsts.append(gateBlk)

            case .spcfyblck:
                break

            case .regblck:
                break
            }
        }
    }
}

extension CircDef {
    func gateSlots() -> [GateSlot] {
        let nameToIndex = nodeIndexMap()
        var result: [GateSlot] = []

        for blk in self.behav_blcks {
            if case .gateblck(let gi) = blk {

                guard let outName = gi.outputNode,
                      let outIdx = nameToIndex[outName] else {
                    continue
                }

                var inIdxs: [Int] = []
                for n in gi.inputNodes {
                    if let idx = nameToIndex[n] {
                        inIdxs.append(idx)
                    }
                }

                let kind: Kind
                if gi.gate == "not" {
                    kind = Kind(rawValue: "inv")!
                } else {
                    kind = Kind(rawValue: gi.gate)!
                }
                let delayVal = extractDelay(from: gi)

                result.append(GateSlot(
                    kind: kind,
                    name: gi.name,
                    inps: inIdxs,
                    outs: [outIdx],
                    delay: delayVal
                ))
            }
        }
        return result
    }

    private func extractDelay(from gi: GateInstYAML) -> Int {
        guard let expr = gi.delay?.first else { return 1 }
        switch expr {
        case .int(let v):   return v
        case .float(let d): return Int(d.rounded())
        case .binary(_, let args):
            if case let .float(a)? = args.first,
               case let .float(b)? = args.dropFirst().first {
                return Int((a * b).rounded())
            }
            return 1
        default:
            return 1
        }
    }
}

// This function is not used. We are now storing vCircs as cCircs
extension CircDef {
    func convert2Vrlg(into circ: Circuit) {
        circ.vCircs.reserveCapacity(circ.vCircs.count + vrlgInsts.count)

        for vi in vrlgInsts {

            guard var circDF = makeCircDef(vi.module) else {
                fatalError("Couldn't build CircDef for \(vi.module)")
            } 

            let circ = circDF.toCircuit()

            circ.vCircs.append(circ)
        }
    }
}

public extension CircDef {
    mutating func Compile(_ circ: Circuit) {
        var ctx = Context(circDef: self)
        ctx.circ = circ
        // self.copyBehav()
        generateCode(for: &self, ctx: &ctx)
        circ.initStates = Array(repeating: InitState(), count: ctx.circDef.initBlcks.count)
        circ.alwaysStates = Array(repeating: AlwaysState(), count: ctx.circDef.alwaysBlcks.count)
        self = ctx.circDef // copy back to self as ctx.circDef is distinct from self
        // Derive initBlcks / alwaysBlcks from behav.behav_blcks
        // self.copyBehav()
    }
}

public extension CircDef {
    func hasAllBlckSens() -> Bool {
        // Check raw behav_blcks (always populated from YAML) rather than alwaysBlcks
        // which is only populated after copyBehav() is called.
        for blk in behav_blcks {
            if case .alwaysblck(let ab) = blk {
                if ab.snstvs?.isEmpty == false {
                    return true
                }
            }
        }
        return false
    }
}

public extension CircDef {
    mutating func toCircuit(_ parent: Circuit? = nil) -> Circuit{

        if self.kind != "verilog" {
            preconditionFailure("makeCircDef should only called for kind=verilog and not kind = \(self.kind)")
        }

        let circDct = self.toCircuitDict()

        // Extract nodes from circDct["nodes"] exactly as fromYAML does
        guard let nodesVal = circDct["nodes"],
              case let .nodes(nodesArray) = nodesVal
        else {
            preconditionFailure("No 'nodes' entry for subcircuit \(self.module)")
        }

        // toCircuitDict() called toNodesArryVal() above, which populated self.nodes with the
        // correct nbits derived from the decl width fields.  Build a lookup so we can reuse
        // those pre-initialised Nods rather than falling back to the default 1-bit constructor.
        let selfNodesByName = Dictionary(uniqueKeysWithValues: self.nodes.map { ($0.name, $0) })

        var nodeLU: [String: Int] = [:]
        var nodes: [Nod] = []

        for (i, node) in nodesArray.enumerated() {
            switch node {
            case .name(let s):
                nodeLU[s] = i
                nodes.append(selfNodesByName[s] ?? Nod(s))

            case .def(let def):
                nodeLU[def.name] = i
                nodes.append(selfNodesByName[def.name] ?? Nod(def.name))
            }
        }

        // Minimal Circuit with nodes + nodeLU
        let circ = Circuit(nodes: nodes, nodeLU: nodeLU, cmpRefs: [], evalOrder: [])
        circ.module = self.module
        circ.kind   = self.kind
        circ.parent = parent
        // Pre-set index to position in parent's cCircs so sub-children see the
        // correct path when getIndxs is called during wireFromDict / MakeCircuit.
        circ.index  = parent?.cCircs.count ?? 0

        // Wire in all ports and components
        circ.wireFromDict(self.module, circDct: circDct)
        if circ.indexs.isEmpty && (circ.parent == nil) {
            circ.indexs = [0]
            Glbls.topCircuit = circ
        }

        // circ = Circuit(module: self.kind, name: self.module)!

        // self.copyBehav()
        for blk in self.behav_blcks {
            let inst: VrlgInstYAML
            switch blk {
            case .instncblck(let i):   inst = i
            case .subcircblck(let i):  inst = i
            case .asyncblck(let i):    inst = i
            case .syncblck(let i):     inst = i
            default: continue
            }
            do {
                guard var crDf = Glbls.circDef(for: inst.module) else {
                    preconditionFailure(
                        "Instance '\(inst.name)' in module '\(self.module)' references " +
                        "subcircuit '\(inst.module)', but no CircDef is registered for it. " +
                        "Ensure '\(inst.module).yml' exists in Resources/CircuitLib and " +
                        "was loaded by makeCircDef()."
                    )
                }
                // Apply instance-level parameter overrides before building the circuit.
                // Positional params (name == "None") are applied in declaration order;
                // named params are matched by name.
                var positionalIdx = 0
                for instParam in inst.params {
                    if instParam.name == "None" {
                        if positionalIdx < crDf.params.count {
                            let targetName = crDf.params[positionalIdx].name
                            crDf.params[positionalIdx] = ParamYAML(
                                kind: instParam.kind,
                                name: targetName,
                                value: instParam.value)
                            positionalIdx += 1
                        }
                    } else {
                        if let idx = crDf.params.firstIndex(where: { $0.name == instParam.name }) {
                            crDf.params[idx] = instParam
                        }
                    }
                }
                let cir = crDf.toCircuit(circ)
                cir.instanceCircDef = crDf   // keep instance-specific CircDef for eval context

                guard let circParam = crDf.params.first(where: { $0.name == "circuit" }),
                      case let .str(circMode) = circParam.value,
                      circMode == "sync" || circMode == "async" else {
                    preconditionFailure("Circuit '\(inst.module)' must have circuit=sync or circuit=async parameter")
                }
                cir.sync = (circMode == "sync")

                cir.name = inst.name
                let supplyNames: Set<String> = ["vdd", "vdda", "vdd_hi", "vss", "vssa"]
                let highSupplyNames: Set<String> = ["vdd", "vdda", "vdd_hi"]

                // Build a param map for resolving parameterized port slice expressions
                // (e.g. IN[nbits-1:0]) using the parent module's actual parameter values.
                let parentParamInts: [String: Int] = Dictionary(uniqueKeysWithValues:
                    self.params.compactMap { p -> (String, Int)? in
                        if case .int(let i) = p.value { return (p.name, i) }
                        return nil
                    }
                )

                var ioIdx = 0                        // positional cursor (positional ports only)
                var wiredPortNames: Set<String> = [] // io_port names successfully wired

                for prt in inst.ports {
                    let resolvedNodeYAML = prt.nodeYAML.resolve(with: parentParamInts)
                    if case .concat(let parts) = resolvedNodeYAML, prt.port.isEmpty {
                        // Positional concat → multi-slot power supply wiring
                        // Validate: all parts must be power supply idents
                        var partNames: [String]? = []
                        for p in parts {
                            if case .ident(let n) = p, supplyNames.contains(n.lowercased()) {
                                partNames!.append(n)
                            } else {
                                partNames = nil
                                break
                            }
                        }

                        guard let partNames else {
                            print("ERROR in '\(inst.name)' of '\(inst.module)': .concat at io_port position \(ioIdx) contains non-power-supply elements; .concat is only permitted for power supply connections")
                            ioIdx += 1
                            continue
                        }

                        guard ioIdx + partNames.count <= crDf.io_ports.count else {
                            print("ERROR in '\(inst.name)' of '\(inst.module)': power supply concat overflows io_ports at position \(ioIdx)")
                            break
                        }

                        for (i, partName) in partNames.enumerated() {
                            let ioPrt = crDf.io_ports[ioIdx + i]

                            guard ioPrt.direct?.hasPrefix("Output") != true else {
                                print("ERROR in '\(inst.name)' of '\(inst.module)': power supply '\(partName)' connected to output port '\(ioPrt.name)'")
                                continue
                            }

                            guard supplyNames.contains(ioPrt.name.lowercased()) else {
                                print("ERROR in '\(inst.name)' of '\(inst.module)': power supply '\(partName)' maps to non-supply io_port '\(ioPrt.name)'")
                                continue
                            }

                            let portName = ioPrt.name
                            if let idx = cir.iPrts.firstIndex(where: { $0.port == portName }) {
                                cir.iPrts[idx].node = partName
                                cir.iPrts[idx].port = portName
                                cir.iPrts[idx].intlIndx = cir.nodeLU[portName] ?? 1000000
                                cir.iPrts[idx].extlIndx = highSupplyNames.contains(partName.lowercased()) ? 1000001 : 1000000
                                wiredPortNames.insert(portName)
                            } else {
                                print("ERROR in '\(inst.name)' of '\(inst.module)': '\(portName)' not found in iPrts")
                            }
                        }
                        ioIdx += partNames.count

                    } else if case .concat(let parts) = resolvedNodeYAML, !prt.port.isEmpty {
                        // Named port with a concat node.
                        let isAllVDD = parts.allSatisfy {
                            if case .ident(let n) = $0 { return highSupplyNames.contains(n.lowercased()) }
                            return false
                        }
                        let isAllSupply = parts.allSatisfy {
                            if case .ident(let n) = $0 { return supplyNames.contains(n.lowercased()) }
                            return false
                        }
                        if isAllSupply {
                            // Pure supply concat → VSS or VDD
                            let supplyNode = isAllVDD ? "VDD" : "VSS"
                            if let idx = cir.iPrts.firstIndex(where: { $0.port == prt.port }) {
                                cir.iPrts[idx].node = supplyNode
                                cir.iPrts[idx].intlIndx = cir.nodeLU[prt.port] ?? 1000000
                                cir.iPrts[idx].extlIndx = isAllVDD ? 1000001 : 1000000
                                wiredPortNames.insert(prt.port)
                            }
                        } else {
                            // Mixed concat: supply bits zero/one-extend a real signal (e.g. {8'b0, FINE[7:0]}).
                            // Use the first non-supply part as the driving signal.
                            let sigPart = parts.first(where: {
                                if case .ident(let n) = $0 { return !supplyNames.contains(n.lowercased()) }
                                return true
                            })
                            if let sigPart, let idx = cir.iPrts.firstIndex(where: { $0.port == prt.port }) {
                                let sigNodeStr = sigPart.asString   // e.g. "FINE[7:0]"
                                let sigBaseName = baseName(sigNodeStr)  // e.g. "FINE"
                                cir.iPrts[idx].node = sigNodeStr
                                cir.iPrts[idx].intlIndx = cir.nodeLU[prt.port] ?? 1000000
                                cir.iPrts[idx].extlIndx = circ.nodeLU[sigBaseName] ?? 1000000
                                wiredPortNames.insert(prt.port)
                            }
                        }
                        ioIdx += 1

                    } else {
                        // Single-slot: named ports look up io_port by name; positional use ioIdx
                        let ioPrt: IOPortYAML
                        let prt_nm: String
                        if prt.port.isEmpty {
                            guard ioIdx < crDf.io_ports.count else {
                                print("ERROR in '\(inst.name)' of '\(inst.module)': too many port connections, expected \(crDf.io_ports.count)")
                                break
                            }
                            ioPrt  = crDf.io_ports[ioIdx]
                            prt_nm = ioPrt.name
                        } else {
                            guard let found = crDf.io_ports.first(where: { $0.name == prt.port }) else {
                                print("ERROR in '\(inst.name)' of '\(inst.module)': named port '\(prt.port)' not in io_ports of '\(inst.module)'")
                                ioIdx += 1
                                continue
                            }
                            ioPrt  = found
                            prt_nm = prt.port
                        }

                        let nd_nm = resolvedNodeYAML.asString
                        assert(prt_nm.firstIndex(of: "[") == nil, "prt_nm should not contain '['")

                        // Use direct if present; fall back to cir's port lists when direct is absent
                        let isOutput = ioPrt.direct.map { $0.hasPrefix("Output") }
                            ?? cir.oPrts.contains(where: { $0.port == prt_nm })

                        if isOutput {
                            if let idx = cir.oPrts.firstIndex(where: { $0.port == prt_nm }) {
                                cir.oPrts[idx].node = baseName(nd_nm)
                                cir.oPrts[idx].port = prt_nm
                                cir.oPrts[idx].intlIndx = cir.nodeLU[prt_nm]!
                                cir.oPrts[idx].extlIndx = circ.nodeLU[baseName(nd_nm)]!
                                if let range = parseBitRange(nd_nm) {
                                    cir.oPrts[idx].extlBitRange = range
                                } else {
                                    cir.oPrts[idx].extlBitIndex = parseSingleBitIndex(nd_nm)
                                }
                                wiredPortNames.insert(prt_nm)
                            } else {
                                print("ERROR in '\(inst.name)' of '\(inst.module)': '\(prt_nm)' not found in oPrts")
                            }
                        } else {
                            if let idx = cir.iPrts.firstIndex(where: { $0.port == prt_nm }) {
                                cir.iPrts[idx].node = nd_nm
                                cir.iPrts[idx].port = prt_nm
                                cir.iPrts[idx].intlIndx = cir.nodeLU[prt_nm]!
                                cir.iPrts[idx].extlIndx = circ.nodeLU[baseName(nd_nm)]!
                                wiredPortNames.insert(prt_nm)
                            } else {
                                print("ERROR in '\(inst.name)' of '\(inst.module)': '\(prt_nm)' not found in iPrts")
                            }
                        }
                        ioIdx += 1
                    }
                }

                // Post-loop: implicitly wire unconnected supply ports; error on any other missing port
                for ioPrt in crDf.io_ports where !wiredPortNames.contains(ioPrt.name) {
                    let portName = ioPrt.name
                    if supplyNames.contains(portName.lowercased()) {
                        if let idx = cir.iPrts.firstIndex(where: { $0.port == portName }) {
                            let isHigh = highSupplyNames.contains(portName.lowercased())
                            cir.iPrts[idx].node = portName
                            cir.iPrts[idx].intlIndx = cir.nodeLU[portName] ?? 1000000
                            cir.iPrts[idx].extlIndx = isHigh ? 1000001 : 1000000
                        }
                    } else {
                        print("ERROR in '\(inst.name)' of '\(inst.module)': io_port '\(portName)' is not connected")
                    }
                }

                cir.parent = circ
                cir.indexs = getIndxs(cir)
                //circ.vCircs.append(cir)
                circ.cCircs.append(cir)
            }
        }

        // Wire each continuous-assign block into Kahn's-algorithm scheduling,
        // the same way instance/gate components already are — see
        // CircDef.md. Must use self.behav (not circDef.assgnBlcks, which
        // isn't populated until self.Compile(circ) runs further below) and
        // must count assign blocks the same way copyBehav() does (one
        // counter increment per .assgnblck entry in self.behav, matching
        // circDef.assgnBlcks' eventual array order) so CmpRef indices line
        // up with circDef.assgnBlcks[i] once it's populated.
        for blk in self.behav {
            guard case .assgnblck(let assgnBlckAST) = blk else { continue }

            var writeIndices: [Int] = []
            var readIndices: [Int] = []
            for assgn in assgnBlckAST.body.assgns {
                writeIndices += lvalueBaseNames(assgn.lvalue).compactMap { circ.nodeLU[$0] }
                readIndices += referencedNodeNames(assgn.rvalue, in: self).compactMap { circ.nodeLU[$0] }
            }

            let ref = CmpRef(kind: .assgnBlk, index: circ.assgnBlkWrites.count)
            circ.assgnBlkWrites.append(writeIndices)
            circ.assgnBlkReads.append(readIndices)
            for idx in writeIndices {
                circ.nodes[idx].nodeDrvr = ref
            }
            for idx in readIndices {
                circ.nodes[idx].nodeSinks.append(ref)
            }
        }

        let slots = self.gateSlots()
        circ.aCircs.reserveCapacity(circ.aCircs.count + slots.count)

        for (idx, s) in slots.enumerated() {
            let gate = Gate(
                kind: s.kind,
                name: s.name,
                ninps: s.inps.count,
                index: idx,
                circuit: circ,
                inps: s.inps,
                outs: s.outs,
                delay: s.delay
            )
            circ.aCircs.append(gate)
        }

        setNodeRefs(circ)
        // Initialize evalOrder if needed, is probably always needed
        if circ.evalOrder.isEmpty && !(circ.module == "CAP") {
            initializeCmpCnts(circ)
        }
        if circ.evalOrder.isEmpty && !circ.cmpRefs.isEmpty {
            let cmpInfo = circ.cmpRefs.map { "\($0.kind)[\($0.index)]" }.joined(separator: ", ")
            preconditionFailure(
                "Circuit '\(circ.module)' has empty evalOrder but non-empty cmpRefs=[\(cmpInfo)] — " +
                "evaluation order could not be determined for one or more components"
            )
        }
        // A circuit with no components (e.g. a passive stub like CAP) is allowed to have an empty evalOrder.

        let id = ObjectIdentifier(circ)
        _ = id
        // print("Circ ID: \(id)")

        // Fix the hierarchy
        for i in circ.aCircs.indices {
            if !(circ.aCircs[i].circuit === circ) {
                // print("aCirc ID: \(ObjectIdentifier(circ.aCircs[i].circuit))")
                circ.aCircs[i].circuit = circ
                // print("aCirc ID: \(ObjectIdentifier(circ.aCircs[i].circuit))")
            }
        }

        for i in circ.sCircs.indices {
            if !(circ.sCircs[i].circuit === circ) {
                // print("sCirc ID: \(ObjectIdentifier(circ.sCircs[i].circuit))")
                circ.sCircs[i].circuit = circ
                // print("sCirc ID: \(ObjectIdentifier(circ.sCircs[i].circuit))")
            }
        }

        for child in circ.vCircs {
            if child.parent !== circ {
                child.parent = circ
            }
        }

        if circ.name == "" && circ.parent == nil {
            circ.name = "Top"
        }

        self.Compile(circ)

        Glbls.register(self)

        /*
        for (idx, blk) in self.vrlgInsts.enumerated() {
            let sub_circ = genCirc(blk.module)!
            if circ.vCircs.count <= idx {
                circ.vCircs.append(sub_circ)
            } else {
                circ.vCircs[idx] = sub_circ
            }
        }
        */

        return circ
    }
}