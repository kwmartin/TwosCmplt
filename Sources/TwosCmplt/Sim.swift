import Foundation
import Yams
import SharedTypes

fileprivate func parseTimeExpression(_ expr: String, per: Int) throws -> Int {
    let s = expr.trimmingCharacters(in: .whitespaces)

    // Plain integer, e.g. "0" or "123"
    if let v = Int(s) {
        return v
    }

    // Just "PER"
    if s == "PER" {
        return per
    }

    // Patterns like "12*PER"
    if let star = s.firstIndex(of: "*") {
        let left  = s[..<star].trimmingCharacters(in: .whitespaces)
        let right = s[s.index(after: star)...].trimmingCharacters(in: .whitespaces)

        if let factor = Int(left), right == "PER" {
            return factor * per
        }

        if let factor = Double(left), right == "PER" {
            return Int(factor * Double(per))
        }

    }

    throw DecodingError.dataCorrupted(
        .init(codingPath: [],
              debugDescription: "Invalid time expression: \(expr)")
    )
}

public extension Array where Element == ScheduledUpdate {
    mutating func insertSorted(_ newElem: ScheduledUpdate) {
        // Fast path: most of the time we just append.
        if let last = self.last, last.updTm <= newElem.updTm {
            self.append(newElem)
            return
        }
        if self.isEmpty {
            self.append(newElem)
            return
        }

        // Otherwise, binary search for insertion index by updTm.
        var low = 0
        var high = self.count
        while low < high {
            let mid = (low + high) / 2
            if self[mid].updTm <= newElem.updTm {
                low = mid + 1
            } else {
                high = mid
            }
        }

        self.insert(newElem, at: low)
    }
}

public struct ModStruct: Decodable, @unchecked Sendable {
    public let ifst: IfStmntYAML

    public enum CodingKeys: String, CodingKey {
        case ifst = "IfExprStatement"
    }

}

import Foundation

// MARK: - Root spec

public struct SpecStruct: Decodable, @unchecked Sendable {
    public let module: String?
    public let constants: Constants
    public let finishTm: Int
    public let clock: [Clock]
    public let saveNds: [SaveNode]
    public let timeSpcs: [TimeSpec]

    public enum CodingKeys: String, CodingKey {
        case module   = "Module"
        case constants = "Constants"
        case finishTm  = "FinishTime"
        case clock     = "Clock"
        case saveNds   = "SaveNds"
        case timeSpcs  = "TimeSpcs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        module = try container.decodeIfPresent(String.self, forKey: .module)
        constants = try container.decode(Constants.self, forKey: .constants)

        guard let per = constants["PER"] else {
            throw DecodingError.dataCorruptedError(
                forKey: .constants,
                in: container,
                debugDescription: "Missing PER constant"
            )
        }

        let finishStr = try container.decode(String.self, forKey: .finishTm)
        finishTm = try Self.parseTimeExpression(finishStr, per: per)

        let rawClocks = try container.decodeIfPresent([RawClock].self, forKey: .clock) ?? []
        clock = try rawClocks.map { try Clock(fromRaw: $0, per: per) }

        saveNds = try container.decodeIfPresent([SaveNode].self, forKey: .saveNds) ?? []

        let rawSpecs = try container.decodeIfPresent([RawTimeSpec].self, forKey: .timeSpcs) ?? []
        timeSpcs = try rawSpecs.map { try TimeSpec(fromRaw: $0, per: per) }
    }
}

// MARK: - Constants
// Supports both:
//   Constants:
//     PER: 1000
//
// and the old form:
//   Constants:
//   - [PER, 1000]

public struct Constants: Decodable, Sendable {
    public let values: [Constant]

    public init(values: [Constant]) {
        self.values = values
    }

    public subscript(_ name: String) -> Int? {
        values.first(where: { $0.name == name })?.value
    }

    public var dictionary: [String: Int] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.name, $0.value) })
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()

        if let dict = try? single.decode([String: Int].self) {
            self.values = dict.map { Constant(name: $0.key, value: $0.value) }
                .sorted { $0.name < $1.name }
            return
        }

        if let array = try? single.decode([Constant].self) {
            self.values = array
            return
        }

        throw DecodingError.dataCorruptedError(
            in: single,
            debugDescription: "Constants must decode from either [String: Int] or [Constant]"
        )
    }
}

public struct Constant: Decodable, Sendable {
    public let name: String
    public let value: Int

    public init(name: String, value: Int) {
        self.name = name
        self.value = value
    }

    // Supports old YAML tuples like:
    // - [PER, 1000]
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.name = try container.decode(String.self)
        self.value = try container.decode(Int.self)
    }
}

// MARK: - SaveNds

public struct SaveNode: Decodable, Sendable {
    public let name: String
    public let format: String

    public enum CodingKeys: String, CodingKey {
        case name
        case format
    }

    public init(name: String, format: String) {
        self.name = name
        self.format = format
    }
}

// MARK: - Clock

public struct RawClock: Decodable, Sendable {
    public let clkNm: String
    public let initVal: Int?
    public let per: String
    public let delay: String?

    public enum CodingKeys: String, CodingKey {
        case clkNm
        case initVal
        case per
        case delay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clkNm = try c.decode(String.self, forKey: .clkNm)
        initVal = try c.decodeIfPresent(Int.self, forKey: .initVal)
        per = try c.decode(String.self, forKey: .per)
        delay = try c.decodeIfPresent(String.self, forKey: .delay)
    }
}

public struct Clock: Sendable {
    public let clkNm: String
    public let initVal: Int
    public let per: Int
    public let delay: Int

    public init(clkNm: String, initVal: Int, per: Int, delay: Int) {
        self.clkNm = clkNm
        self.initVal = initVal
        self.per = per
        self.delay = delay
    }

    public init(fromRaw raw: RawClock, per globalPER: Int) throws {
        self.clkNm = raw.clkNm
        self.initVal = raw.initVal ?? 0
        self.per = try SpecStruct.parseTimeExpression(raw.per, per: globalPER)
        self.delay = try SpecStruct.parseTimeExpression(raw.delay ?? "0", per: globalPER)
    }
}

// MARK: - TimeSpcs
// Supports two entry formats:
//   dict:  {tm: "0", vls: [[NAME, value], ...]}
//   flat:  [NAME, value]   ← treated as time-0 with a single signal

public struct RawTimeSpec: Decodable, Sendable {
    public let tm: String
    public let vls: [SignalValue]

    public enum CodingKeys: String, CodingKey {
        case tm
        case vls
    }

    public init(from decoder: Decoder) throws {
        // Dict format: {tm: "...", vls: [...]}
        if let c = try? decoder.container(keyedBy: CodingKeys.self), c.contains(.tm) {
            if let intTm = try? c.decode(Int.self, forKey: .tm) {
                self.tm = String(intTm)
            } else if let strTm = try? c.decode(String.self, forKey: .tm) {
                self.tm = strTm
            } else if let dblTm = try? c.decode(Double.self, forKey: .tm) {
                self.tm = String(dblTm)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .tm,
                    in: c,
                    debugDescription: "tm must be Int, Double, or String"
                )
            }
            self.vls = try c.decode([SignalValue].self, forKey: .vls)
            return
        }
        // Flat format: [name, value] → time 0 with a single signal
        var u = try decoder.unkeyedContainer()
        let sigName = try u.decode(String.self)
        let sigValue: Int
        if let intVal = try? u.decode(Int.self) {
            sigValue = intVal
        } else {
            let str = try u.decode(String.self)
            sigValue = try SignalValue.parseValue(str, codingPath: decoder.codingPath)
        }
        self.tm = "0"
        self.vls = [SignalValue(name: sigName, value: sigValue)]
    }
}

public struct TimeSpec: Sendable {
    public let tm: Int
    public let vls: [SignalValue]

    public init(tm: Int, vls: [SignalValue]) {
        self.tm = tm
        self.vls = vls
    }

    public init(fromRaw raw: RawTimeSpec, per: Int) throws {
        self.tm = try SpecStruct.parseTimeExpression(raw.tm, per: per)
        self.vls = raw.vls
    }
}

// MARK: - Signal values
// Decodes entries like:
// - [INIT, 1]
// - [FRQ, "0x4000000"]
// - [FRQ, "34h4000000"]   ← {nbits}h{hex} format

public struct SignalValue: Decodable, Sendable {
    public let name: String
    public let value: Int

    public init(name: String, value: Int) {
        self.name = name
        self.value = value
    }

    // Parse a string value: "0x..." hex, "{n}h..." nbits-hex, or decimal.
    static func parseValue(_ str: String, codingPath: [CodingKey]) throws -> Int {
        if str.hasPrefix("0x") || str.hasPrefix("0X") {
            guard let v = Int(str.dropFirst(2), radix: 16) else {
                throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Cannot parse hex value: \(str)"))
            }
            return v
        }
        // {nbits}h{hex} format, e.g. "34h4000000"
        if let hIdx = str.firstIndex(of: "h") {
            let prefix = str[str.startIndex..<hIdx]
            if !prefix.isEmpty && prefix.allSatisfy(\.isNumber) {
                let hexPart = String(str[str.index(after: hIdx)...])
                guard let v = Int(hexPart, radix: 16) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Cannot parse nbits-hex value: \(str)"))
                }
                return v
            }
        }
        guard let v = Int(str) else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Cannot parse integer value: \(str)"))
        }
        return v
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.name = try container.decode(String.self)
        if let intVal = try? container.decode(Int.self) {
            self.value = intVal
        } else {
            let str = try container.decode(String.self)
            self.value = try Self.parseValue(str, codingPath: decoder.codingPath)
        }
    }
}

// MARK: - Time expression parsing
// Supports examples like:
//   0
//   PER
//   16*PER
//   1.1*PER

extension SpecStruct {
    fileprivate static func parseTimeExpression(_ text: String, per: Int) throws -> Int {
        let expr = text.replacingOccurrences(of: " ", with: "")

        if let intVal = Int(expr) {
            return intVal
        }

        if expr == "PER" {
            return per
        }

        if expr.hasSuffix("*PER") {
            let lhs = String(expr.dropLast(4)) // removes "*PER"

            if let intMul = Int(lhs) {
                return intMul * per
            }

            if let dblMul = Double(lhs) {
                return Int((dblMul * Double(per)).rounded())
            }
        }

        throw DecodingError.dataCorrupted(
            .init(
                codingPath: [],
                debugDescription: "Unsupported time expression: \(text)"
            )
        )
    }
}

public extension SpecStruct {
    func constant(named name: String) -> Int? {
        constants[name]
    }
}

public extension SpecStruct {
    func constantValue(named name: String) -> Int? {
        constants[name]
    }
}

public enum ParmError: @unchecked Sendable, LocalizedError {
    case unexpectedType(Any, key: String)

    public var errorDescription: String? {
        switch self {
        case let .unexpectedType(value, key):
            return "Unexpected type \(type(of: value)) for key \"\(key)\""
        }
    }
}

public func loadInpSpcs(_ circNm: String) -> [String: Any] {
    guard let inpSpcsStr = try? getInpSpcsStr(named: circNm)
    else { preconditionFailure("Reading Input inpSpcsStr Failed") }

    guard let spcsDct = try? Yams.load(yaml: inpSpcsStr) as? [String: Any] else {
        preconditionFailure("Setting  spcsDct Failed")
    }
    return spcsDct
}


public func parseConstants(_ spcsDct: [String: Any]) throws -> [Parm] {
    var parms: [Parm] = []

    // 1. Pull out the raw Constants value.
    guard let rawConstants = spcsDct["Constants"] else {
        return parms   // or throw if Constants is required
    }

    // 2. Treat it as an array of "rows".
    guard let rows = rawConstants as? [Any] else {
        // e.g. throw a decoding error
        return parms
    }

    for row in rows {
        // 3. Each row should be a 2‑element array: [String, Int].
        guard let pair = row as? [Any], pair.count == 2 else {
            continue   // or throw
        }

        guard let name = pair[0] as? String,
              let intValue = pair[1] as? Int else {
            continue   // or throw
        }

        parms.append(Parm(name: name, value: .int(intValue)))
    }

    return parms
}

public func loadSpec(url: URL) throws -> SpecStruct {

    // This can throw (file missing, permissions, etc.), so the function is marked `throws`.
    let data = try Data(contentsOf: url)   // [web:130]

    let decoder = YAMLDecoder()
    // This can also throw (syntax error, type mismatch), so this line is also `try`.
    let spec = try decoder.decode(SpecStruct.self, from: data)

    return spec
}

/// Removes any TimeSpcs.vls entries referencing nodes not in `knownNodes` and writes the
/// cleaned YAML back to `url`. Prints a warning for each name removed. No-ops if the file
/// doesn't exist or has no unknown entries.
public func cleanSpecFile(at url: URL, knownNodes: Set<String>) {
    guard let yamlStr = try? String(contentsOf: url, encoding: .utf8) else { return }
    guard let root = try? compose(yaml: yamlStr) else { return }
    guard case .mapping(var rootMap) = root else { return }
    guard let tsIdx = rootMap.firstIndex(where: { $0.key.string == "TimeSpcs" }) else { return }
    guard case let .sequence(timeSeq) = rootMap[tsIdx].value else { return }

    var removedNames: Set<String> = []
    var newTsNodes: [Node] = []
    var tsChanged = false

    for tsNode in timeSeq {
        // Flat format: [name, value]
        if case let .sequence(flatPair) = tsNode,
           let first = flatPair.first,
           let name = first.string,
           flatPair.count == 2 {
            if knownNodes.contains(name) {
                newTsNodes.append(tsNode)
            } else {
                removedNames.insert(name)
                tsChanged = true
            }
            continue
        }

        guard case .mapping(var tsMap) = tsNode else {
            newTsNodes.append(tsNode)
            continue
        }
        guard let vlsIdx = tsMap.firstIndex(where: { $0.key.string == "vls" }) else {
            newTsNodes.append(Node.mapping(tsMap))
            continue
        }
        guard case let .sequence(vlsSeq) = tsMap[vlsIdx].value else {
            newTsNodes.append(Node.mapping(tsMap))
            continue
        }

        let filteredVls: [Node] = vlsSeq.filter { vlNode in
            guard case let .sequence(pair) = vlNode,
                  let first = pair.first,
                  let name = first.string else { return true }
            if knownNodes.contains(name) { return true }
            removedNames.insert(name)
            return false
        }

        if filteredVls.isEmpty && !vlsSeq.isEmpty {
            // All vls entries removed — drop this time spec entry entirely
            tsChanged = true
        } else if filteredVls.count != vlsSeq.count {
            tsChanged = true
            let newVlsSeq = Node.Sequence(filteredVls, vlsSeq.tag, vlsSeq.style)
            tsMap[vlsIdx] = (key: tsMap[vlsIdx].key, value: Node.sequence(newVlsSeq))
            newTsNodes.append(Node.mapping(tsMap))
        } else {
            newTsNodes.append(Node.mapping(tsMap))
        }
    }

    guard tsChanged else { return }

    let newTimeSeq = Node.Sequence(newTsNodes, timeSeq.tag, timeSeq.style)
    rootMap[tsIdx] = (key: rootMap[tsIdx].key, value: Node.sequence(newTimeSeq))
    let newRoot = Node.mapping(rootMap)

    print("⚠️ Removing unknown nodes from spec \(url.lastPathComponent): \(removedNames.sorted().joined(separator: ", "))")
    if let output = try? serialize(node: newRoot) {
        try? output.write(to: url, atomically: true, encoding: .utf8)
    }
}

public func mergeTimeSpcs(_ base: [TimeSpec], _ extra: [TimeSpec]) -> [TimeSpec] {
    var i = 0
    var j = 0
    var result: [TimeSpec] = []
    result.reserveCapacity(base.count + extra.count)

    while i < base.count && j < extra.count {
        if base[i].tm <= extra[j].tm {
            result.append(base[i]); i += 1
        } else {
            result.append(extra[j]); j += 1
        }
    }
    if i < base.count { result.append(contentsOf: base[i...]) }
    if j < extra.count { result.append(contentsOf: extra[j...]) }
    return result
}

public func genClkChngs(_ spec: SpecStruct) -> [TimeSpec] {
    let clkSpcs = spec.clock
    var tmSpcs: [TimeSpec] = []

    for clk in clkSpcs {
        var tSpcs: [TimeSpec] = []
        var tm = 0
        var clkVal = clk.initVal

        tSpcs.append(
            TimeSpec(
                tm: tm,
                vls: [SignalValue(name: clk.clkNm, value: clkVal)]
            )
        )

        tm += clk.delay
        tm += clk.per / 2

        while tm <= spec.finishTm {
            clkVal = (clkVal == 0) ? 1 : 0
            tSpcs.append(
                TimeSpec(
                    tm: tm,
                    vls: [SignalValue(name: clk.clkNm, value: clkVal)]
                )
            )

            tm += clk.per / 2
            if tm > spec.finishTm { break }

            clkVal = (clkVal == 0) ? 1 : 0
            tSpcs.append(
                TimeSpec(
                    tm: tm,
                    vls: [SignalValue(name: clk.clkNm, value: clkVal)]
                )
            )

            tm += clk.per / 2
        }

        tmSpcs = mergeTimeSpcs(tSpcs, tmSpcs)
    }

    return tmSpcs
}

public extension TimeSpec {
    init(tm: Int, pair: (String, Int)) {
        self.init(
            tm: tm,
            vls: [SignalValue(name: pair.0, value: pair.1)]
        )
    }
}

public func makeConstants(_ spcsDct: [String: Any]) -> [Parm] {
    var parms: [Parm] = []
    if let constants = spcsDct["Constants"] as? [[String: Any]] {
        for constant in constants {
            if let spc = constant as? [String: Int] {
                for (key, value) in spc {
                    // key is String, value is Int
                    print("Key '\(key)' has value \(value)")
                    parms.append(Parm(name: key, value: .int(value)))
                }
            }
            if let per = constant["PER"] as? Int {
                print("PER =", per)
            }
        }
    }
    if let clocks = spcsDct["Clock"] as? [[String: Any]] {
        for clk in clocks {
            let name  = clk["clkNm"]  as? String
            let initV = clk["initVal"] as? Int
            let perRef = clk["per"]    as? String   // "PER"
            let delay = clk["delay"]  as? Int
            print("Clock:", name ?? "?", initV ?? -1, perRef ?? "?", delay ?? -1)
        }
    }

    if let timeSpcs = spcsDct["TimeSpcs"] as? [[String: Any]] {
        for entry in timeSpcs {
            let tm = entry["tm"]          // could be Int or String like "PER" or "2*PER"
            let vls = entry["vls"] as? [[Any]]  // each inner is [tag, value]

            print("tm =", tm ?? "nil")
            if let pairs = vls {
                for pair in pairs {
                    if pair.count == 2 {
                        let tag = pair[0] as? String
                        let value = pair[1]
                        print("  \(tag ?? "?") -> \(value)")
                    }
                }
            }
        }
    }
    return parms
}

func setInputs(_ circ: Circuit, tmSpcs: [TimeSpec]) {
    for spc in tmSpcs {
        for vl in spc.vls {
            circ.setNode(vl.name, val: vl.value, tm: spc.tm)
        }
    }
}

public struct Context {
    // Arena owner: gives access to exprs / stmts for ExprId / StmtId.
    public var circDef: CircDef
    public var circ: Circuit? = nil      // renamed
    public var behavIdx: BehavBlockKind? = nil

    // Expression arena
    public var exprs: [Expr] = []

    // Codegen / execution state
    public var block: CompiledBlock?          // optional: only set when executing
    public var code: [Instruction]            // code buffer for codegen

    // Evaluation stack and variables
    public var stack: [Value]
    public var vars: [String: Value]

    // Collected specify timing arcs
    public var timingArcs: [TimingArc]
    public var simTime: Int = 0
    // True only while executing an edge-triggered always block; used by readNode
    // to gate the prevValue check so combinational assign blocks are unaffected.
    public var isEdgeTriggered: Bool = false

    public init(circDef: CircDef,
                block: CompiledBlock? = nil,
                code: [Instruction] = [],
                stack: [Value] = [],
                vars: [String: Value] = [:],
                timingArcs: [TimingArc] = [],
                simTime: Int = 0) {
        self.circDef = circDef
        self.block = block
        self.code = code
        self.stack = stack
        self.vars = vars
        self.timingArcs = timingArcs
        self.simTime = simTime
    }

    // Arena insertion: addExpr
    @discardableResult
    public mutating func addExpr(_ e: Expr) -> ExprId {
        exprs.append(e)
        return ExprId(raw: exprs.count - 1)
    }

    // Look up instruction pointer for a label in the current compiled block.
    public func address(for label: Label) -> Int {
        guard let blk = block else {
            fatalError("address(for:) called with no compiled block set")
        }
        guard let ip = blk.labelToIP[label] else {
            fatalError("Unknown label: \(label)")
        }
        return ip
    }

    // Stack operations
    public mutating func push(_ v: Value) {
        stack.append(v)
    }

    public mutating func pop() -> Value {
        stack.removeLast()
    }

    // Variable access
    public mutating func write(_ name: String, _ v: Value) {
        vars[name] = v
    }

    public func read(_ name: String) -> Value {
        guard let v = vars[name] else {
            fatalError("Read of unknown variable \(name)")
        }
        return v
    }

    // Syscall hook
    public mutating func syscall(_ name: String, args: [Value]) -> Value {
        switch name {
        case "time":
            return .int(self.simTime)
        case "readmemh":
            execReadMemH(ctx: &self)
            return .int(0)
        case "eq":
            guard args.count == 2 else { return .int(0) }
            return .int(args[0].asInt == args[1].asInt ? 1 : 0)
        default:
            return .int(-1)
        }
    }

    public mutating func evalGate(_ name: String, args: [Value]) -> Value {
        let ints: [Int] = args.map { $0.asInt }
        switch name {
        case "and", "BAnd:", "BLand:":

            var result = 0x1
            for i in ints {
                result &= i & 0x1
            }
            return .int(result)

        case "nand", "BNand:":

            var result = 0x1
            for i in ints {
                result &= i & 0x1
            }
            result = result == 0x1 ? 0 : 0x1
            return .int(result)

        case "or", "BOr:", "BLor:":

            var result = 0x0
            for i in ints {
                result &= i | 0x1
            }
            return .int(result)

        case "nor", "BNor:":

            var result = 0x0
            for i in ints {
                result &= i | 0x1
            }
            result = result == 0x1 ? 0 : 0x1
            return .int(result)

        case "xor", "BXor:":

            var result = 0x0
            for i in ints {
                result ^= i | 0x1
            }
            return .int(result)

        case "xnor", "BXnor:":

            var result = 0x0
            for i in ints {
                result ^= i | 0x1
            }
            result = result == 0x1 ? 0 : 0x1
            return .int(result)

        default:
            print("Unrecognized gate: \(name)")
            return .int(0)
        }
    }
    public mutating func getSelect(_ name: String, msb: Int, lsb: Int) -> SmallNod {
        guard let ckt = circ else {
            fatalError("readNode called with no Circuit set in Context")
        }
        guard let idx = ckt.nodeLU[name] else {
            fatalError("getSelect: Unknown node name '\(name)' in circuit '\(ckt.module)'")
        }

        precondition(idx >= 0 && idx < ckt.nodes.count,
                     "nodeLU[\(name)] = \(idx) out of bounds for nodes.count \(ckt.nodes.count)")

        let nod = ckt.nodes[idx]
        let slc = nod.node.selBits(n1: msb, n2: lsb)
        let tm = nod.updTm
        let nd = SmallNod(name: name, node: slc, updTm: tm)
        return nd
    }

    public mutating func getTwoCmplt(_ name: String) -> TwoCmplt {
        guard let ckt = circ else {
            fatalError("readNode called with no Circuit set in Context")
        }
        guard let idx = ckt.nodeLU[name] else {
            fatalError("Unknown node name \(name)")
        }

        precondition(idx >= 0 && idx < ckt.nodes.count,
                     "nodeLU[\(name)] = \(idx) out of bounds for nodes.count \(ckt.nodes.count)")

        let nod = ckt.nodes[idx]
        return nod.node
    }
}

extension Context {
    // Low-level nod access using Circuit’s nodes / nodeLU
    public func readNode(_ name: String) -> SmallNod {
        guard let ckt = circ else {
            fatalError("readNode called with no Circuit set in Context")
        }
        guard
            let idx = ckt.nodeLU[name]
        else {
            if let v = vars[name] {
                return SmallNod(name: name, node: TwoCmplt(v.asInt, nbits: 32), updTm: simTime)
            }
            // Array passed by name (e.g. as syscall arg): return zero sentinel
            if ckt.nodeLU["\(name)[0]"] != nil {
                return SmallNod(name: name, node: TwoCmplt(0, nbits: 32), updTm: simTime)
            }
            fatalError("Unknown node name \(name)")
        }
        let nd = ckt.nodes[idx]

        // Special-case supplies: entries exist in nodeLU but not in nodes[]
        if idx == 1000000 { // VSS
            return SmallNod(name: name, node: TwoCmplt(0, nbits: 1), updTm: self.simTime)
        }
        if idx == 1000001 { // VDD
            return SmallNod(name: name, node: TwoCmplt(1, nbits: 1), updTm: self.simTime)
        }

        precondition(idx >= 0 && idx < ckt.nodes.count,
                     "nodeLU[\(name)] = \(idx) out of bounds for nodes.count \(ckt.nodes.count)")

        // If the node's value was updated with a future timestamp (set by a gate's
        // propagation delay firing in the same eval sweep), use the previous stable
        // value instead — the new value hasn't physically arrived at simTime yet.
        if isEdgeTriggered && nd.updTm > simTime {
            var prevNode = nd.node
            prevNode.value = nd.prevValue
            return SmallNod(name: name, node: prevNode, updTm: nd.updTm)
        }

        return SmallNod(name: name, node: nd.node, updTm: nd.updTm)
    }

    public mutating func writeNode(_ name: String, _ v: Value, tm: Int) {
        guard let ckt = circ else {
            fatalError("writeNode called with no Circuit set in Context")
        }
        guard let idx = ckt.nodeLU[name] else {
            fatalError("Unknown node name \(name)")
        }

        let twos: TwoCmplt
        switch v {
        case .twoCmplt(let t):
            twos = t.node
        case .int(let i):
            twos = TwoCmplt(i, nbits: ckt.nodes[idx].node.nbits)
        case .uint(let u):
            twos = TwoCmplt(Int(u), nbits: ckt.nodes[idx].node.nbits)
        case .real(let d):
            twos = TwoCmplt(Int(d), nbits: ckt.nodes[idx].node.nbits)
        case .bool(let b):
            twos = TwoCmplt(b ? 1 : 0, nbits: ckt.nodes[idx].node.nbits)
        }

        ckt.setNode(name, val: twos.value, tm: tm)
    }
}

extension Context {
    /// For a .node returns (name, []),
    /// for a .select returns (name, [msb, lsb]),
    /// otherwise returns nil.
    func nodeOrSelectInfo(for exprId: ExprId) -> (String, [Int])? {
        let expr = circDef.expr(for: exprId)

        switch expr {
        case .node(let name):
            return (name, [])

        case .select(name: let name, args: let args):
            precondition(args.count == 2, ".select must have msb,lsb")
            let msbExpr = circDef.expr(for: args[0])
            let lsbExpr = circDef.expr(for: args[1])

            guard
                let msb = msbExpr.getInt,
                let lsb = lsbExpr.getInt
            else {
                return nil
            }

            return (name, [msb, lsb])

        default:
            return nil
        }
    }
}

extension Context {
    func inspectConcat(_ expr: Expr) -> [(String, [Int])] {
        guard case let .concat(args: ids) = expr else { return [] }
        return ids.compactMap { nodeOrSelectInfo(for: $0) }
    }
}

extension Array where Element == Expr {
    mutating func appendExpr(_ e: Expr) -> ExprId {
        append(e)
        return ExprId(raw: count - 1)
    }
}

public func writeNd(_ ckt: Circuit, _ name: String, _ v: Value, updTm: Int) {
    guard let idx = ckt.nodeLU[name] else {
        fatalError("Unknown node name \(name)")
    }

    let twos: TwoCmplt
    switch v {
    case .twoCmplt(let t):
        twos = t.node
    case .int(let i):
        twos = TwoCmplt(i, nbits: ckt.nodes[idx].node.nbits)
    case .uint(let u):
        twos = TwoCmplt(Int(u), nbits: ckt.nodes[idx].node.nbits)
    case .real(let d):
        twos = TwoCmplt(Int(d), nbits: ckt.nodes[idx].node.nbits)
    case .bool(let b):
        twos = TwoCmplt(b ? 1 : 0, nbits: ckt.nodes[idx].node.nbits)
    }

    ckt.setNode(name, val: twos.value, tm: updTm)
}

public func assignToLValue(_ lhs: LValueAST, rhs: Value, tm: Int, ctx: inout Context) {
    var nd: SmallNod
    var tcvar: TwoCmplt
    var time: Int = tm
    if time >= ctx.simTime {
        ctx.simTime = time
    }

    switch lhs {
    case .net(let name):
        let arcDelay = ctx.circDef.timingArcs.first(where: { $0.dst == name })?.delay ?? 0
        let val = rhs.asInt
        if ctx.circ?.nodeLU[name] != nil {
            ctx.circ!.setNode(name, val: val, tm: tm + arcDelay)
        } else {
            ctx.vars[name] = .int(val)
        }
    case .bitSelect(let name, let n1):
        if ctx.circ?.nodeLU[name] != nil {
            nd = ctx.readNode(name)
            tcvar = nd.node
            time = nd.updTm
        } else {
            preconditionFailure("Node \(name) must be present")
        }
        let bit = (rhs.asInt)&0x1
        let newval = tcvar.setBit(bit, n1: n1).value
        ctx.circ!.setNode(name, val: newval, tm: time)

    case .partSelect(let name, let n1, let n2):
        if ctx.circ?.nodeLU[name] != nil {
            nd = ctx.readNode(name)
            tcvar = nd.node
            time = nd.updTm
        } else {
            preconditionFailure("Node \(name) must be present")
        }
        let nbits = n1 - n2 + 1
        let msk = ((1<<nbits) - 1)
        let slc = (rhs.asInt)&msk
        let newval = tcvar.setBits(slc, n1: n1, n2: n2).value
        ctx.circ!.setNode(name, val: newval, tm: tm)

    case .indexedPartSelect(let name, let n2, let nbits):
        if ctx.circ?.nodeLU[name] != nil {
            nd = ctx.readNode(name)
            tcvar = nd.node
            time = nd.updTm
        } else {
            preconditionFailure("Node \(name) must be present")
        }
        let n1 = n2 + nbits - 1
        let msk = ((1<<nbits) - 1)
        let slc = (rhs.asInt)&msk
        let newval = tcvar.setBits(slc, n1: n1, n2: n2).value
        ctx.circ!.setNode(name, val: newval, tm: tm)

    case .concat(let parts):
        let totalVal = rhs.asInt
        var offset = parts.reduce(0) { $0 + $1.Lwidth(in: ctx.circDef) }
        for part in parts {
            let w = part.Lwidth(in: ctx.circDef)
            offset -= w
            let msk: Int = w >= Int.bitWidth ? -1 : (1 << w) - 1
            let sliceInt = (totalVal >> offset) & msk
            assignToLValue(part, rhs: .int(sliceInt), tm: tm, ctx: &ctx)
        }
    }
}

// One scheduled non-blocking update
public struct ScheduledUpdate {
    public let lvalue: LValueAST    // where to write (node / slice / concat)
    public let value: Value         // what value to write
    public let updTm: Int            // sim time when it should become visible
}

public func execReadMemH(ctx: inout Context) {
    guard let ckt = ctx.circ else { return }
    guard let datfileParam = ctx.circDef.params.first(where: { $0.name == "datfile" }),
          case .str(let filename) = datfileParam.value else {
        print("readmemh: no datfile string parameter in \(ctx.circDef.module)")
        return
    }
    guard let depthParam = ctx.circDef.params.first(where: { $0.name == "depth" }),
          case .int(let depth) = depthParam.value else {
        print("readmemh: no depth parameter in \(ctx.circDef.module)")
        return
    }
    guard let ndataParam = ctx.circDef.params.first(where: { $0.name == "ndata" }),
          case .int(let ndata) = ndataParam.value else {
        print("readmemh: no ndata parameter in \(ctx.circDef.module)")
        return
    }
    let fileURL = Glbls.memFilesDir.appendingPathComponent(filename)
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("readmemh: could not read file \(fileURL.path)")
        return
    }
    let lines = content.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("@") }
    let mask = ndata < 64 ? (1 << ndata) - 1 : Int.max
    for i in 0..<min(depth, lines.count) {
        let hexStr = lines[i].replacingOccurrences(of: "_", with: "")
        if let val = Int(hexStr, radix: 16) {
            let nodeName = "MEM[\(i)]"
            if ckt.nodeLU[nodeName] != nil {
                ckt.setNode(nodeName, val: val & mask, tm: ctx.simTime)
            }
        }
    }
}

func writeAlwysSchdl(ctx: inout Context, tm: Int) {
    let circuit = ctx.circ!

    for i in circuit.alwaysStates.indices {
        // Write noblk
        var pending = circuit.alwaysStates[i].noblk
        var remaining: [ScheduledUpdate] = []

        for upd in pending {
            if upd.updTm <= tm {
                assignToLValue(upd.lvalue, rhs: upd.value, tm: tm, ctx: &ctx)
            } else {
                remaining.append(upd)
            }
        }

        circuit.alwaysStates[i].noblk = remaining

        // Write blk
        pending = circuit.alwaysStates[i].blk
        remaining = []

        for upd in pending {
            if upd.updTm <= tm {
                assignToLValue(upd.lvalue, rhs: upd.value, tm: tm, ctx: &ctx)
            } else {
                remaining.append(upd)
            }
        }

        circuit.alwaysStates[i].blk = remaining
    }
}

func writeNonBlocking(ctx: inout Context) {
    let circuit = ctx.circ!

    // for each always block we are writing all the noblk's
    for i in circuit.alwaysStates.indices {
        let noblks = circuit.alwaysStates[i].noblk

        for upd in noblks {
            assignToLValue(upd.lvalue, rhs: upd.value, tm: upd.updTm, ctx: &ctx)
        }
        circuit.alwaysStates[i].noblk = []
    }
}

func commitNonBlocking(ctx: inout Context) {
    let circuit = ctx.circ!

    // this version only write noblk's with updTm's less than simTime. 
    let now = ctx.simTime

    // for each always block
    for i in circuit.alwaysStates.indices {
        let pending = circuit.alwaysStates[i].noblk
        var remaining: [ScheduledUpdate] = []

        for upd in pending {
            if upd.updTm <= now {
                assignToLValue(upd.lvalue, rhs: upd.value, tm: upd.updTm, ctx: &ctx)
            } else {
                remaining.append(upd)
            }
        }

        circuit.alwaysStates[i].noblk = remaining
    }

    // similarly for initStates if they may schedule NBAs
}

public func stackNonBlockValue(lvalue: LValueAST,
                               value: Value,
                               delay: Int?,
                               ctx: inout Context)
{
    guard let circuit = ctx.circ else {
        fatalError("stackNonBlockValue with no Circuit")
    }
    guard let block = ctx.behavIdx else {
        fatalError("stackNonBlockValue outside init/always block")
    }

    // let ndNm = lvalue.nodeNm
    // let val = value.asInt
    let now = ctx.simTime

    let idly: Int = delay ?? 0

    var updTm: Int = now
    updTm += idly

    let upd = ScheduledUpdate( lvalue: lvalue,
                                value: value,
                                updTm: updTm )
    switch block {
    case .alwaysBlock(let idx):
        circuit.alwaysStates[idx].noblk.insertSorted(upd)
        circuit.alwaysStates[idx].updTm = updTm
    case .initBlock(let idx):
        circuit.initStates[idx].noblk.insertSorted(upd)
        circuit.initStates[idx].updTm = updTm
    case .assgnBlock(let idx):
        _ = idx
        // print("idx: \(idx)")
        break
    }
    /*
    if updTm <= now {
        ctx.circ!.setNode(ndNm, val: val, tm: updTm)
    } else {
        let upd = ScheduledUpdate( lvalue: lvalue,
                                    value: value,
                                    updTm: updTm )
        switch block {
        case .alwaysBlock(let idx):
            circuit.alwaysStates[idx].noblk.insertSorted(upd)
            circuit.alwaysStates[idx].updTm = updTm
        case .initBlock(let idx):
            circuit.initStates[idx].noblk.insertSorted(upd)
            circuit.initStates[idx].updTm = updTm
        case .assgnBlock(let idx):
            print("idx: \(idx)")
            break
        }
    }
    */
}

public func setLeftNet(lvalue: LValueAST,
                               value: Value,
                               delay: Int?,
                               ctx: inout Context)
{
    let val = value.asInt
    let updTm = ctx.simTime + (delay ?? 0)

    switch lvalue {
    case .net(let name):
        let arcDelay = ctx.circDef.timingArcs.first(where: { $0.dst == name })?.delay ?? 0
        if ctx.circ?.nodeLU[name] != nil {
            ctx.circ!.setNode(name, val: val, tm: updTm + arcDelay)
        } else {
            ctx.vars[name] = .int(val)
        }

    case .bitSelect(let name, let index):
        var tc = ctx.readNode(name).node
        let newval = tc.setBit(val & 1, n1: index).value
        ctx.circ!.setNode(name, val: newval, tm: updTm)

    case .partSelect(let name, let msb, let lsb):
        var tc = ctx.readNode(name).node
        let nbits = msb - lsb + 1
        let msk = (1 << nbits) - 1
        let newval = tc.setBits(val & msk, n1: msb, n2: lsb).value
        ctx.circ!.setNode(name, val: newval, tm: updTm)

    case .indexedPartSelect(let name, let base, let width):
        var tc = ctx.readNode(name).node
        let msk = (1 << width) - 1
        let newval = tc.setBits(val & msk, n1: base + width - 1, n2: base).value
        ctx.circ!.setNode(name, val: newval, tm: updTm)

    case .concat(let parts):
        var offset = parts.reduce(0) { $0 + $1.Lwidth(in: ctx.circDef) }
        for part in parts {
            let w = part.Lwidth(in: ctx.circDef)
            offset -= w
            let msk: Int = w >= Int.bitWidth ? -1 : (1 << w) - 1
            let sliceInt = (val >> offset) & msk
            setLeftNet(lvalue: part, value: .int(sliceInt), delay: delay, ctx: &ctx)
        }
    }
}

public func run(ctx: inout Context) {
    dbg("= \(ctx.circ!.module), name: \(ctx.circ!.name)")

    var tm: Int = ctx.simTime
    var ip = 0   // instruction pointer

    while ip < ctx.code.count {
        let instr = ctx.code[ip]

        switch instr.op {

        // --- Loads / stores ---

        case .loadConstReal(let d):
            ctx.push(.real(d))
            ip += 1

        case .loadConstInt(let i):
            ctx.push(.int(i))
            ip += 1

        case .loadSignal(let name):
            let nd = ctx.readNode(name)

            ctx.push(.twoCmplt(nd))
            ip += 1

        case .storeSignal(let name):
            let v = ctx.pop()
            guard case .twoCmplt(_) = v else {
                preconditionFailure("Can only run .storeSignal on a TwoCmplt")
            }

            ctx.writeNode(name, v, tm: tm)
            ip += 1

        // --- Syscalls ---

        case .gateOp(let name, let argCount):
            var args: [Value] = []
            args.reserveCapacity(argCount)
            for _ in 0..<argCount {
                args.append(ctx.pop())
            }
            args.reverse()              // restore original order
            let result = ctx.evalGate(name, args: args)
            ctx.push(result)
            ip += 1

        case .select(let name, let argCount):
            if argCount == 1 {
                // Array access: name[idx]
                let idx = ctx.pop().asInt
                let nodeName = "\(name)[\(idx)]"
                let result = ctx.readNode(nodeName)
                ctx.push(.twoCmplt(result))
            } else {
                // Part select: name[msb:lsb]
                // Also handles array access that was normalized 1→2 arg: MEM[idx] → MEM[idx:idx]
                let lsb = ctx.pop().asInt
                let msb = ctx.pop().asInt
                if ctx.circ?.nodeLU[name] == nil,
                   ctx.circ?.nodeLU["\(name)[\(lsb)]"] != nil {
                    let result = ctx.readNode("\(name)[\(lsb)]")
                    ctx.push(.twoCmplt(result))
                } else {
                    let result = ctx.getSelect(name, msb: msb, lsb: lsb)
                    ctx.push(.twoCmplt(result))
                }
            }
            ip += 1

        case .concat(let argCount):
            var args: [Value] = []
            args.reserveCapacity(argCount)
            for _ in 0..<argCount {
                args.append(ctx.pop())
            }
            args.reverse()              // restore original order

            var result = TwoCmplt(0, nbits: 0)
            for arg in args {
                guard case let .twoCmplt(vl) = arg
                else { preconditionFailure("Arg: \(arg) in concat not SmallNod")}
                result = result.joinBts(reg: vl.node)
                if vl.updTm > tm { tm = vl.updTm} 
            }

            let nd = SmallNod(name: "", node: result, updTm: tm)
            ctx.push(.twoCmplt(nd))
            ip += 1

        case .callSyscall(let name, let argCount):
            var args: [Value] = []
            args.reserveCapacity(argCount)
            for _ in 0..<argCount {
                args.append(ctx.pop())
            }
            args.reverse()              // restore original order
            let result = ctx.syscall(name, args: args)
            ctx.push(result)
            ip += 1

        // --- Unary ops via UOp ---

        case .unaryOp(let uop):
            let v = ctx.pop()
            let result = applyUnaryOp(uop, v)
            ctx.push(result)
            ip += 1

        // --- Binary ops via BnOp ---

        case .binOp(let op):
            let rhs = ctx.pop()
            let lhs = ctx.pop()
            let result = applyBinaryOp(op, lhs, rhs)
            ctx.push(result)
            ip += 1

        // --- Control flow ---

        case .br(let target):
            ip = target

        case .brFalse(let target):
            let cond = ctx.pop()
            if !asBool(cond) {
                ip = target
            } else {
                ip += 1
            }

        case .noblckAssign(let lvAst, let delay):
            let rhsVal = ctx.pop()
            stackNonBlockValue(lvalue: lvAst,
                               value: rhsVal,
                               delay: delay,
                               ctx: &ctx)
            ip += 1

        case .blckAssign(let lvAst, let delay):
            let rhsVal = ctx.pop()
            setLeftNet(lvalue: lvAst,
                               value: rhsVal,
                               delay: delay,
                               ctx: &ctx)
            ip += 1

        case .assgn(let lvAst, let delay):
            let rhsVal = ctx.pop()
            setLeftNet(lvalue: lvAst,
                               value: rhsVal,
                               delay: delay,
                               ctx: &ctx)
            ip += 1

        case .drop:
            _ = ctx.pop()
            ip += 1

        }
    }
}

struct SortedNodeChangeQueue {
    private var storage: [NodeChng] = []

    // Optional: call once from owner when you know an upper bound.
    mutating func reserveCapacity(_ n: Int) {
        storage.reserveCapacity(n)
    }

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }

    // Insert keeping ascending order by updTm.
    mutating func insert(_ ch: NodeChng) {
        let idx = insertionIndex(for: ch)
        storage.insert(ch, at: idx)
    }

    // Get and remove the earliest change.
    mutating func popFirst() -> NodeChng? {
        storage.isEmpty ? nil : storage.removeFirst()
    }

    // Peek earliest without removing.
    func first() -> NodeChng? {
        storage.first
    }

    // Clear but keep buffer for reuse.
    mutating func removeAll(keepingCapacity keep: Bool = true) {
        storage.removeAll(keepingCapacity: keep)
    }

    // Tail-biased insertion index: walk backwards from the end.
    private func insertionIndex(for ch: NodeChng) -> Int {
        var i = storage.count
        while i > 0 && storage[i - 1].updTm > ch.updTm {
            i -= 1
        }
        return i
    }

    // Optional: simple iterator over all in time order.
    func forEach(_ body: (NodeChng) -> Void) {
        storage.forEach(body)
    }
}

public func loadSpecs(_ circ_nm: String) -> (per: Int, finishTm: Int, tmSpcs: [TimeSpec]) {
    loadSpecs(fromURL: Glbls.simSpcsDir.file(circ_nm, ext: "yml"))
}

public func loadSpecs(fromURL url: URL) -> (per: Int, finishTm: Int, tmSpcs: [TimeSpec]) {
    do {
        let spec = try loadSpec(url: url)
        var tmSpcs = genClkChngs(spec)
        tmSpcs = mergeTimeSpcs(spec.timeSpcs, tmSpcs)
        guard let per = spec.constantValue(named: "PER") else {
            preconditionFailure("Missing PER constant")
        }
        return (per: per, finishTm: spec.finishTm, tmSpcs: tmSpcs)
    } catch {
        preconditionFailure("Failed to load spec from \(url.path): \(error)")
    }
}

public func simCircuit(_ circ: Circuit, per: Int, finishTm: Int, tmSpcs: [TimeSpec]) -> [TimeSpec] {

    DbgLggr.shared.close()
    DbgLggr.shared.open()

    Glbls.period = per

    let rtrnSpcs: [TimeSpec] = []
    var inputSpcs: [TimeSpec] = []
    Glbls.nodeChngs.removeAll(keepingCapacity: true)

    var tm = 0
    var tm2 = tm + per/2
    var updTm = tm

    inputSpcs = tmSpcs.filter { $0.tm <= 0}
    setInputs(circ, tmSpcs: inputSpcs)

    if circ.kind == "verilog" && circ.initialized == false {
        circ.eval(async: true, tm: updTm)
    } else {
        circ.eval(async: true, tm: updTm)
    }

    while tm <= finishTm {
        // inputSpcs = tmSpcs.filter { $0.tm >= tm && $0.tm <= tm2  && $0.vl.0 != "CLK"}
        inputSpcs = tmSpcs.filter { $0.tm > tm && $0.tm <= tm2}

        if let maxSpec = inputSpcs.max(by: { $0.tm < $1.tm }) {
            if maxSpec.tm > updTm {
                updTm = maxSpec.tm
            }
        }

        setInputs(circ, tmSpcs: inputSpcs)
        circ.eval(async: true, tm: updTm)
        circ.eval(async: false, tm: updTm)
        tm += per/2
        tm2 += per/2
        // inputSpcs = tmSpcs.filter { $0.tm > tm && $0.tm <= tm2 && $0.vl.0 == "CLK"}
        inputSpcs = tmSpcs.filter { $0.tm > tm && $0.tm <= tm2}

        if let maxSpec = inputSpcs.max(by: { $0.tm < $1.tm }) {
            if maxSpec.tm > updTm {
                updTm = maxSpec.tm
            }
        }

        setInputs(circ, tmSpcs: inputSpcs)
        circ.eval(async: false, tm: updTm)
        circ.eval(async: true, tm: updTm)  // for async after regs to outputs
        tm += per/2
        tm2 += per/2
    }
    if Glbls.saveChngs == true {
        saveNodeChngs()
    }
    if Glbls.saveDefMap == true {
        saveDefMap()
    }
    DbgLggr.shared.close()
    return rtrnSpcs
}


