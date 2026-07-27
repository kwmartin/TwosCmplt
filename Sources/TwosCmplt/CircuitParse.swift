import Foundation
import SharedTypes

/// Parse a Verilog-style numeric literal: optional `<size>'<b|o|d|h><digits>`.
/// Falls back to plain integer parsing for bare decimal strings.
func parseVerilogInt(_ s: String) -> Int? {
    if let v = Int(s) { return v }
    guard let quoteIdx = s.firstIndex(of: "'") else { return nil }
    let afterQuote = s[s.index(after: quoteIdx)...]
    guard let baseChar = afterQuote.first else { return nil }
    let digits = String(afterQuote.dropFirst()).filter { $0 != "_" }
    switch baseChar.lowercased() {
    case "b": return Int(digits, radix: 2)
    case "o": return Int(digits, radix: 8)
    case "d": return Int(digits, radix: 10)
    case "h": return Int(digits, radix: 16)
    default:  return nil
    }
}

public enum Number: Decodable {
    case int(Int)
    case bool(Bool)
    case real(Double)
}

private struct GatePayload: Decodable {
    let oper: String
    let args: [ExprYAML]
}

public indirect enum ExprYAML: Decodable {
    case int(Int)
    case float(Double)
    case ident(String)
    case node(String)
    case unary(op: UOp, arg: ExprYAML)
    case binary(op: BnOp, args: [ExprYAML])
    case gate(op: String, args: [ExprYAML])
    case select(name: String, args: [ExprYAML])
    case concat(args: [ExprYAML])
    case syscall(name: String, args: [ExprYAML])
    case cndtn(args: [ExprYAML])

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case node
        case op
        case oper
        case args
        case arg
        case gate
        case lvalue
        case rvalue
        case name
        case sgmnts
        case concats
    }

    private enum Kind: String, Decodable {
        case int
        case float
        case str
        case node
        case gt_expr
        case cmpr_expr
        case cmpr_unary
        case cmpr_ident
        case cmpr_gate
        case cndexpr
        case uexpr
        case bexpr
        case sexpr
        case ident
        case select
        case concat
        case sys_tm
        case sys_rltm
        case sys_frmt
        case bit
        case slice
        case syscall
        case cmpr_int
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)

        // print("ExprYAML init for kind: \(kind)")
        switch kind {
        case .int:
            if let v = try? c.decode(Int.self, forKey: .value) {
                self = .int(v)
            } else {
                let s = try c.decode(String.self, forKey: .value)
                self = .int(parseVerilogInt(s) ?? 0)
            }

        case .float:
            let v = try c.decode(Double.self, forKey: .value)
            self = .float(v)

        case .str:
            let name = try c.decode(String.self, forKey: .value)
            self = .node(name)

        case .node:
            let name = try c.decode(String.self, forKey: .node)
            self = .node(name)

        case .gt_expr:
            let op   = try c.decode(BnOp.self, forKey: .oper)
            let args = try c.decode([ExprYAML].self, forKey: .args)
            self = .binary(op: op, args: args)

        case .cmpr_expr:
            let op   = try c.decode(BnOp.self,      forKey: .oper)
            let args = try c.decode([ExprYAML].self, forKey: .args)
            self = .binary(op: op, args: args)

        case .cmpr_unary:
            let arg = try c.decode(ExprYAML.self, forKey: .arg)
            self = arg

        case .cmpr_ident:
            let name  = try c.decode(String.self,   forKey: .node)
            self = .node(name)

        case .cmpr_gate:
            let gate = try c.decode(GatePayload.self, forKey: .gate)
            self = .gate(op: gate.oper, args: gate.args)

        case .cndexpr:
            let args = try c.decode([ExprYAML].self, forKey: .args)
            self = .cndtn(args: args)

        case .uexpr:
            // print("ExprYAML.uexpr: decoding oper")
            let op   = try c.decode(UOp.self,       forKey: .oper)
            // print("ExprYAML.uexpr: op =", op, "decoding args")
            let args = try c.decode([ExprYAML].self, forKey: .args)
            // print("ExprYAML.uexpr: args.count =", args.count)
            self = .unary(op: op, arg: args[0])

        case .bexpr:
            let op   = try c.decode(BnOp.self,      forKey: .oper)
            let args = try c.decode([ExprYAML].self, forKey: .args)
            self = .binary(op: op, args: args)

        case .sexpr:
            let op   = try c.decode(BnOp.self,      forKey: .oper)
            let args = try c.decode([ExprYAML].self, forKey: .args)
            self = .binary(op: op, args: args)

        case .ident:
            let name  = try c.decode(String.self, forKey: .name)
            // sgmnts is optional; default to empty if not present
            let args  = (try? c.decode([ExprYAML].self, forKey: .sgmnts)) ?? []
            if args.isEmpty {
                self = .node(name)
            } else {
                self = .select(name: name, args: args)
            }

        case .select:
            let name  = try c.decode(String.self,   forKey: .name)
            let args = try c.decode([ExprYAML].self, forKey: .sgmnts)
            self = .select(name: name, args: args)

        case .concat:
            let name  = try c.decode(String.self,   forKey: .name)
            let concats = try c.decode([ExprYAML].self, forKey: .concats)
            self = .select(name: name, args: concats)

        case .sys_tm:
            let name  = try c.decode(String.self,   forKey: .name)
            self = .syscall(name: name, args: [])

        case .sys_rltm:
            let name  = try c.decode(String.self,   forKey: .name)
            self = .syscall(name: name, args: [])

        case .sys_frmt:
            let name  = try c.decode(String.self,   forKey: .name)
            let args = try c.decode([ExprYAML].self, forKey: .args)
            self = .syscall(name: name, args: args)

        case .slice:
            let name = try c.decode(String.self, forKey: .name)
            let args = try c.decode([ExprYAML].self, forKey: .sgmnts)
            self = .select(name: name, args: args)

        case .bit:
            let name = try c.decode(String.self, forKey: .name)
            // sgmnts can be [ExprYAML], bare [Int], or [String] (param name)
            let args: [ExprYAML]
            if let exprs = try? c.decode([ExprYAML].self, forKey: .sgmnts) {
                args = exprs
            } else if let ints = try? c.decode([Int].self, forKey: .sgmnts) {
                args = ints.map { .int($0) }
            } else if let strs = try? c.decode([String].self, forKey: .sgmnts) {
                args = strs.map { .node($0) }
            } else {
                args = []
            }
            self = .select(name: name, args: args)

        case .syscall:
            let name = try c.decode(String.self, forKey: .name)
            let args = (try? c.decode([ExprYAML].self, forKey: .value)) ?? []
            self = .syscall(name: name, args: args)

        case .cmpr_int:
            let arg = try c.decode(ExprYAML.self, forKey: .arg)
            self = arg

        }

        // print("ExprYAML init self: \(self)")

    }
}

/*
public enum RValueYAML: Decodable {
    case expr(ExprYAML)
    case concat([ExprYAML])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if let e = try? c.decode(ExprYAML.self) {
            self = .expr(e)
            return
        }

        if let es = try? c.decode([ExprYAML].self) {
            self = .concat(es)
            return
        }

        throw DecodingError.typeMismatch(
            RValueYAML.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected ExprYAML or [ExprYAML] for rvalue"
            )
        )
    }
}
*/

import Yams

func debugBehavBlock6RValue(_ ymlStr: String) {
    do {
        guard let root = try Yams.compose(yaml: ymlStr) else {
            print("No root node")
            return
        }

        guard let rootMap = root.mapping else {
            print("Root is not a mapping")
            return
        }

        guard let behavNode = rootMap.value(forKey: "behav_blcks"),
              let behavSeq = behavNode.sequence,
              behavSeq.count > 6 else {
            print("behav_blcks[6] not found")
            return
        }

        let blk = behavSeq[6]

        guard let blkMap = blk.mapping else {
            print("behav_blcks[6] is not a mapping")
            return
        }

        guard let rvalueNode = blkMap.value(forKey: "rvalue") else {
            print("behav_blcks[6].rvalue not found")
            return
        }

        print("=== raw rvalue node ===")
        print(rvalueNode)

        if let map = rvalueNode.mapping {
            print("rvalue is a mapping")
            print("keys:", map.stringKeys)

            if let concats = map.value(forKey: "concats") {
                print("concats node:", concats)

                if let seq = concats.sequence {
                    print("concats is sequence, count =", seq.count)
                    for (i, n) in seq.enumerated() {
                        print("concats[\(i)] =", n)
                        if let s = n.scalar?.string {
                            print("  scalar:", s)
                        }
                        if let m = n.mapping {
                            print("  mapping keys:", m.stringKeys)
                        }
                    }
                } else {
                    print("concats is not a sequence")
                }
            }
        } else if let seq = rvalueNode.sequence {
            print("rvalue is a sequence, count =", seq.count)
            for (i, n) in seq.enumerated() {
                print("rvalue[\(i)] =", n)
            }
        } else if let scalar = rvalueNode.scalar {
            print("rvalue is scalar:", scalar.string)
        } else {
            print("rvalue is some other node form")
        }

    } catch {
        print("debugBehavBlock6RValue error:", error)
    }
}

public enum RValueYAML: Decodable {
    case expr(ExprYAML)
    case concat([ExprYAML])

    private enum CodingKeys: String, CodingKey {
        case concats
    }

    // Cheap presence-only probe, used to fast-path the common (non-concat) case
    // below without triggering ExprYAML's own decode twice.
    private enum KindProbeKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        // print("🔍 RValueYAML decode at:", decoder.codingPath.map(\.stringValue).joined(separator: " -> "))

        // 0) Fast path: an ordinary kind-tagged expression (the overwhelming
        // common case for every non-concat assign/always rvalue) has a `kind`
        // key and should go straight to ExprYAML -- probing for `concats`
        // first would always throw keyNotFound for these (there's no such
        // key on a kind-tagged node), get caught below, and only then fall
        // through to the same ExprYAML decode reached here directly.
        if let probe = try? decoder.container(keyedBy: KindProbeKeys.self),
           probe.contains(.kind) {
            self = .expr(try ExprYAML(from: decoder))
            return
        }

        // 1) Try keyed container
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self) {
            // print("✓ Got keyed container, allKeys:", keyed.allKeys.map(\.stringValue))

            // Try [String]
            do {
                let names = try keyed.decode([String].self, forKey: .concats)
                // print("✓ Decoded concats as [String]:", names)
                let exprs = names.map { ExprYAML.ident($0) }
                // print("✓ Mapped to ExprYAML.ident:", exprs)
                self = .concat(exprs)
                return
            } catch {
                // print("✗ Failed [String] decode:", error)
            }

            // Try [ExprYAML]
            do {
                let exprs = try keyed.decode([ExprYAML].self, forKey: .concats)
                // print("✓ Decoded concats as [ExprYAML]")
                self = .concat(exprs)
                return
            } catch {
                // print("✗ Failed [ExprYAML] decode:", error)
            }
        } else {
            // print("✗ No keyed container")
        }

        // 2) Try bare array
        if var unkeyed = try? decoder.unkeyedContainer() {
            // print("✓ Got unkeyed container")
            var exprs: [ExprYAML] = []
            while !unkeyed.isAtEnd {
                if let s = try? unkeyed.decode(String.self) {
                    exprs.append(.ident(s))
                } else if let e = try? unkeyed.decode(ExprYAML.self) {
                    exprs.append(e)
                }
            }
            if !exprs.isEmpty {
                print("✓ Decoded bare array, count:", exprs.count)
                self = .concat(exprs)
                return
            }
        }

        // 3) Try single value
        // print("Trying single value container")
        let single = try decoder.singleValueContainer()
        
        if let s = try? single.decode(String.self) {
            // print("✓ Decoded as String:", s)
            self = .expr(.ident(s))
            return
        }
        
        if let e = try? single.decode(ExprYAML.self) {
            // print("✓ Decoded as ExprYAML")
            self = .expr(e)
            return
        }

        print("✗ All decode attempts failed")
        throw DecodingError.typeMismatch(
            RValueYAML.self,
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected rvalue as { concats: [String] }, [ExprYAML], or single expr"
            )
        )
    }
}

public extension RValueYAML {
    func toExprId(in circ: inout CircDef) -> ExprId {
        switch self {
        case .expr(let e):
            // Use your existing lowering
            return e.toExprId(in: &circ)

        case .concat(let exprs):
            let argIds = exprs.map { $0.toExprId(in: &circ) }
            // This is now exactly compatible with your internExpr
            return circ.internExpr(Expr.concat(args: argIds))
        }
    }
}

extension ExprYAML {
    public func toExprId(in circ: inout CircDef) -> ExprId {
        switch self {
        case .int(let v):
            return circ.internExpr(Expr.int(v))

        case .float(let f):
            return circ.internExpr(Expr.real(f))

        case .ident(let i),
             .node(let i):
            return circ.internExpr(Expr.node(i))

        case .binary(let op, let args):
            let argIds = args.map { $0.toExprId(in: &circ) }
            return circ.internExpr(Expr.binary(op: op, args: argIds))

        case .unary(let op, let arg):
            let argId = arg.toExprId(in: &circ)
            return circ.internExpr(Expr.unary(op: op, arg: argId))

        case .gate(let op, let args):
            let argIds = args.map { $0.toExprId(in: &circ) }
            return circ.internExpr(Expr.gate(op: op, args: argIds))

        case .select(let name, let args):
            var argIds = args.map { $0.toExprId(in: &circ) }
            // Normalize single-index bit access (signal[idx]) to two-arg (signal[idx:idx])
            if argIds.count == 1 { argIds = [argIds[0], argIds[0]] }
            return circ.internExpr(Expr.select(name: name, args: argIds))

        case .concat(let args):
            let argIds = args.map { $0.toExprId(in: &circ) }
            return circ.internExpr(Expr.concat(args: argIds))

        case .syscall(let name, let args):
            let argIds = args.map { $0.toExprId(in: &circ) }
            return circ.internExpr(Expr.syscall(name: name, args: argIds))

        case .cndtn(let args):
            let argIds = args.map { $0.toExprId(in: &circ) }
            return circ.internExpr(Expr.cndtn(args: argIds))
        }
    }
}

public indirect enum Expr {
    case int(Int)
    case real(Double)
    case node(String)
    case binary(op: BnOp, args: [ExprId])
    case unary(op: UOp, arg: ExprId)
    case gate(op: String, args: [ExprId])
    case select(name: String, args: [ExprId])
    case concat(args: [ExprId])
    case syscall(name: String, args: [ExprId])
    case cndtn(args: [ExprId])
}

// The next two extensions enable initializations using let vl = Expr(real: 0.0) or Expr(int: 1)
extension Expr {
    init(real value: Double) {
        self = .real(value)
    }

    init(int value: Int) {
        self = .int(value)
    }
}

extension Expr {

    var getInt: Int? {
        if case let .int(i) = self {
            return i
        }
        return nil
    }

    var getReal: Double? {
        if case let .real(d) = self {
            return d
        }
        return nil
    }

    var nodeNm: String? {
        if case let .node(name) = self {
            return name
        }
        return nil
    }

    var selectNm: String? {
        if case let .select(name: name, args: _) = self { return name }
        return nil
    }

    var selectBits: [ExprId]? {
        if case let .select(name: _, args: args) = self { return args }
        return nil
    }

    var sysNm: String? {
        if case let .syscall(name: name, args: _) = self { return name }
        return nil
    }

    var sysArgs: [ExprId]? {
        if case let .syscall(name: _, args: args) = self { return args }
        return nil
    }
}

public struct RootYAML: Decodable {
    public let behav_blcks: [BehavBlckYAML]

    public func toAST(in circ: inout CircDef) -> BehavAST {
        BehavAST(
            behav_blcks: behav_blcks.map { $0.toAST(in: &circ) }
        )
    }
}

//////////////////////////////////////////////////////////////////////////////////////

public enum BehavBlckYAML: Decodable {
    case spcfyblck(SpcfyBlckYAML)
    case initblck(InitBlckYAML)
    case alwaysblck(AlwaysBlckYAML)
    case assgnblck(AssgnBlckYAML)
    case instncblck(VrlgInstYAML)
    case subcircblck(VrlgInstYAML)
    case asyncblck(VrlgInstYAML)
    case syncblck(VrlgInstYAML)
    case gateblck(GateInstYAML)   // new
    case regblck(RegBlckYAML)

    private enum CodingKeys: String, CodingKey { case kind }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)

        switch kind {
        case "specify":
            self = .spcfyblck(try SpcfyBlckYAML(from: decoder))
        case "initial":
            self = .initblck(try InitBlckYAML(from: decoder))
        case "always":
            self = .alwaysblck(try AlwaysBlckYAML(from: decoder))
        case "assign":
            self = .assgnblck(try AssgnBlckYAML(from: decoder))
        case "instance":
            self = .instncblck(try VrlgInstYAML(from: decoder))
        case "subcirc":
            self = .subcircblck(try VrlgInstYAML(from: decoder))
        case "async":
            self = .asyncblck(try VrlgInstYAML(from: decoder))
        case "sync":
            self = .syncblck(try VrlgInstYAML(from: decoder))
        case "gate":
            self = .gateblck(try GateInstYAML(from: decoder))
        case "Reg", "Integer":
            self = .regblck(try RegBlckYAML(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: c,
                debugDescription: "Unknown behav_blcks kind: \(kind)"
            )
        }
    }
}

// One element in behav_blcks when kind == "specify"
public struct SpcfyBlckYAML: Decodable {
    public let variant: SpecifyVariant
    public let delay_expr: DelayExpr
    public let src_sgnls: [String]
    public let edge: Edge
    public let dst_sgnls: [String]
    public let pth_spc: PathSpecifier?   // <- optional

    private enum CodingKeys: String, CodingKey {
        case kind
        case variant
        case delay_expr
        case src_sgnls
        case edge
        case dst_sgnls
        case pth_spc
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // kind is always "specify" – you can assert if you like
        let kind = try c.decode(String.self, forKey: .kind)
        guard kind == "specify" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: c,
                debugDescription: "Expected kind == \"specify\", got \(kind)"
            )
        }

        self.variant   = try c.decode(SpecifyVariant.self, forKey: .variant)
        self.delay_expr = try c.decode(DelayExpr.self, forKey: .delay_expr)
        self.src_sgnls = try c.decode([String].self, forKey: .src_sgnls)
        self.edge      = try c.decode(Edge.self, forKey: .edge)
        self.dst_sgnls = try c.decode([String].self, forKey: .dst_sgnls)
        self.pth_spc   = try c.decodeIfPresent(PathSpecifier.self, forKey: .pth_spc)
    }
}

// "full" or "parallel"
public enum SpecifyVariant: String, Decodable {
    case full
    case parallel
}

// posedge / negedge / all / level
public enum Edge: String, Decodable {
    case posedge
    case negedge
    case all
    case level
}

// pluscolon / minuscolon / colon
public enum PathSpecifier: String, Decodable {
    case pluscolon
    case minuscolon
    case colon
}

// One entry in delay_expr:
// - kind: float / int / arith
// - delay: number (Double or Int in the YAML)
public enum DelayExpr: Decodable {
    case float(Double)
    case int(Int)
    case arith(Double)   // or a more complex type later

    private enum CodingKeys: String, CodingKey {
        case kind
        case delay
    }

    private enum Kind: String, Decodable {
        case float
        case int
        case arith
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)

        switch kind {
        case .float, .arith:
            // YAML numbers decode to Double cleanly in both float/arith cases
            let value = try c.decode(Double.self, forKey: .delay)
            self = (kind == .float) ? .float(value) : .arith(value)

        case .int:
            let value = try c.decode(Int.self, forKey: .delay)
            self = .int(value)
        }
    }
}

extension DelayExpr {
    /// Convert a delay expression to an Int:
    /// - .int(i)    -> i
    /// - .float(f)  -> Int(f)
    /// - .arith(a)  -> Int(a)   // adjust as needed later
    func asInt() -> Int {
        switch self {
        case .int(let i):
            return i
        case .float(let f):
            return Int(f)
        case .arith(let a):
            return Int(a)
        }
    }
}

public struct AssgnBlckYAML: Decodable {
    public let lvalue: LValueYAML
    public let width: Int = 1
    public let rvalue: RValueYAML
    public let delay: Double?

    private enum CodingKeys: String, CodingKey {
        case kind
        case lvalue
        case rvalue
        case delay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let kind = try c.decode(String.self, forKey: .kind)
        guard kind == "assign" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: c,
                debugDescription: "Expected kind == \"assign\", got \(kind)"
            )
        }

        // lvalue can be either a mapping (normal) or a sequence (special assign form)
        if let normalLValue = try? c.decode(LValueYAML.self, forKey: .lvalue) {
            self.lvalue = normalLValue
        } else {
            var lvalueContainer = try c.nestedUnkeyedContainer(forKey: .lvalue)
            let selector = try lvalueContainer.decode(String.self)

            if selector == "lconcat" {
                // [lconcat, [name0, name1, ...]] — left-hand concatenation target
                let names = try lvalueContainer.decode([String].self)
                let parts = names.map { LValueYAML(kind: "ident", name: $0) }
                self.lvalue = LValueYAML(kind: "concat", parts: parts)
            } else {
                // [selector, LValueYAML] — selector currently unused
                let sliceExpr = try lvalueContainer.decode(LValueYAML.self)
                self.lvalue = sliceExpr
            }
        }

        self.rvalue = try c.decode(RValueYAML.self, forKey: .rvalue)

        if c.contains(.delay) {
            if let d = try? c.decode(Double.self, forKey: .delay) {
                self.delay = d
            } else if let i = try? c.decode(Int.self, forKey: .delay) {
                self.delay = Double(i)
            } else if let expr = try? c.decode(ExprYAML.self, forKey: .delay) {
                self.delay = AssgnBlckYAML.evalDelayExpr(expr)
            } else {
                self.delay = nil
            }
        } else {
            self.delay = nil
        }
    }

    static func evalDelayExpr(_ expr: ExprYAML) -> Double? {
        switch expr {
        case .int(let v):   return Double(v)
        case .float(let d): return d
        case .binary(let op, let args):
            guard let lhs = args.first.flatMap({ evalDelayExpr($0) }),
                  let rhs = args.dropFirst().first.flatMap({ evalDelayExpr($0) }) else { return nil }
            switch op {
            case .times:    return lhs * rhs
            case .div:      return lhs / rhs
            case .plus:     return lhs + rhs
            case .minus:    return lhs - rhs
            default:        return nil
            }
        case .unary(let op, let arg):
            guard let v = evalDelayExpr(arg) else { return nil }
            switch op {
            case .minus:    return -v
            default:        return nil
            }
        default: return nil
        }
    }
}

private struct IntOrNode: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        // Case 1: bare scalar int
        if let v = try? c.decode(Int.self) {
            value = v
            return
        }

        // Case 2: { kind: int, value: N }
        struct IntNode: Decodable {
            let kind: String
            let value: Int
        }

        let node = try c.decode(IntNode.self)
        // Optional: guard node.kind == "int"
        value = node.value
    }
}

public enum PortNodeYAML: Decodable {
    case ident(String)
    case concat([PortNodeYAML])
    case slice(String, [Int])
    case sliceExpr(String, [WidthExpr])  // parameterized bounds — resolved in toCircuit
    case bit(String, Int)
    case int(Int)

    private enum CodingKeys: String, CodingKey {
        case kind, name, sgmnts, value
    }

    public init(from decoder: Decoder) throws {
        // Fallback: plain scalar string → .ident (e.g. `node: INV0` instead of `node: {kind: ident, name: INV0}`)
        if let sv = try? decoder.singleValueContainer(), let name = try? sv.decode(String.self) {
            self = .ident(name)
            return
        }

        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)

        switch kind {
        case "ident":
            let name = try c.decode(String.self, forKey: .name)
            self = .ident(name)

        case "concat":
            let segs = try c.decode([PortNodeYAML].self, forKey: .sgmnts)
            self = .concat(segs)

        case "slice":
            let name = try c.decode(String.self, forKey: .name)

            // Accept [Int], [{kind:expr,...}], or [{kind:int,value:...}]
            if let ints = try? c.decode([Int].self, forKey: .sgmnts) {
                self = .slice(name, ints)
            } else if let exprs = try? c.decode([WidthExpr].self, forKey: .sgmnts) {
                let emptyParams: [String: Int] = [:]
                let vals = exprs.map { $0.evaluate(with: emptyParams) }
                if vals.allSatisfy({ $0 != nil }) {
                    self = .slice(name, vals.map { $0! })
                } else {
                    // One or more bounds contain a parameter expression (e.g. nbits-1)
                    // that can't be resolved at decode time.  Store the raw expressions
                    // so toCircuit can resolve them with the actual parameter values.
                    self = .sliceExpr(name, exprs)
                }
            } else {
                let nodes = try c.decode([IntOrNode].self, forKey: .sgmnts)
                self = .slice(name, nodes.map(\.value))
            }

        case "bit":
            let name = try c.decode(String.self, forKey: .name)

            if let ints = try? c.decode([Int].self, forKey: .sgmnts), ints.count == 1 {
                self = .bit(name, ints[0])
            } else if let exprs = try? c.decode([WidthExpr].self, forKey: .sgmnts), exprs.count == 1 {
                let emptyParams: [String: Int] = [:]
                self = .bit(name, exprs[0].evaluate(with: emptyParams) ?? 0)
            } else {
                let nodes = try c.decode([IntOrNode].self, forKey: .sgmnts)
                guard nodes.count == 1 else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: decoder.codingPath,
                            debugDescription: "bit node must have exactly one index"
                        )
                    )
                }
                self = .bit(name, nodes[0].value)
            }

        case "int":
            let value = try c.decode(Int.self, forKey: .value)
            self = .int(value)

        default:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported port node kind: \(kind)"
                )
            )
        }
    }
}

public extension PortNodeYAML {
    var asString: String {
        switch self {
        case .ident(let name):
            return name
        case .concat(let parts):
            return "{\(parts.map(\.asString).joined(separator: ", "))}"
        case .slice(let name, let indices):
            if indices.count == 2 {
                return "\(name)[\(indices[0]):\(indices[1])]"
            } else {
                return "\(name)[\(indices.map(String.init).joined(separator: ":"))]"
            }
        case .sliceExpr(let name, _):
            return name  // unresolved — must call resolve(with:) before use
        case .bit(let name, let index):
            return "\(name)[\(index)]"
        case .int(let value):
            return String(value)
        }
    }

    func resolve(with params: [String: Int]) -> PortNodeYAML {
        guard case .sliceExpr(let name, let exprs) = self else { return self }
        let vals = exprs.map { $0.evaluate(with: params) }
        guard vals.allSatisfy({ $0 != nil }) else {
            preconditionFailure("PortNodeYAML.sliceExpr '\(name)': could not resolve all bounds with params \(params)")
        }
        return .slice(name, vals.map { $0! })
    }
}

// Lightweight port connection type for instances (not the heavyweight PortDef)
public struct InstPortYAML: Decodable {
    public let port: String
    public let nodeYAML: PortNodeYAML

    private enum CodingKeys: String, CodingKey {
        case port, node
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawPort = try c.decode(String.self, forKey: .port)
        self.port = (rawPort == "None") ? "" : rawPort
        self.nodeYAML = try c.decode(PortNodeYAML.self, forKey: .node)
    }

    // Provide a .node property for backward compatibility
    public var node: String {
        nodeYAML.asString
    }
}

public struct VrlgInstYAML: Decodable {
    public let name: String
    public let module: String
    public let params: [ParamYAML]
    public let ports: [InstPortYAML]  // <- CHANGED from [PortDef]

    private enum CodingKeys: String, CodingKey {
        case name, module, ports, params
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name   = try c.decode(String.self, forKey: .name)
        self.module = try c.decode(String.self, forKey: .module)
        self.ports  = try c.decode([InstPortYAML].self, forKey: .ports)  // <- CHANGED
        self.params = try c.decodeIfPresent([ParamYAML].self, forKey: .params) ?? []
    }
}

extension VrlgInstYAML {
    public var outputNode: InstPortYAML? { ports.first }
    public var inputNodes: [InstPortYAML] { Array(ports.dropFirst()) }
}

extension VrlgInstYAML {
    func toPortDefs(
        intlStart: Int = 1_000_000,
        extlStart: Int = 1_000_000
    ) -> [PortDef] {
        var defs: [PortDef] = []
        var intl = intlStart
        var extl = extlStart

        if let out = outputNode {
            defs.append(
                PortDef(port: out.port, node: out.node, intlIndx: intl, extlIndx: extl)
            )
            intl += 1; extl += 1
        }

        for p in inputNodes {
            defs.append(
                PortDef(port: p.port, node: p.node, intlIndx: intl, extlIndx: extl)
            )
            intl += 1; extl += 1
        }

        return defs
    }
}

public struct GateInstYAML: Decodable {
    public let name: String       // instance name, e.g. "nand1"
    public let gate: String       // primitive kind, e.g. "nand"
    public let ports: [String]    // node names, first is output
    public let delay: [ExprYAML]? // same encoding as other ExprYAMLs

    private enum CodingKeys: String, CodingKey {
        case name
        case gate
        case ports
        case delay
    }
}

extension GateInstYAML {
    public var outputNode: String? { ports.first }
    public var inputNodes: [String] { Array(ports.dropFirst()) }
}

extension GateInstYAML {
    func toPortDefs(
        intlStart: Int = 1_000_000,
        extlStart: Int = 1_000_000
    ) -> [PortDef] {
        var defs: [PortDef] = []
        var intl = intlStart
        var extl = extlStart

        if let out = outputNode {
            defs.append(
                PortDef(port: "Y", node: out, intlIndx: intl, extlIndx: extl)
            )
            intl += 1; extl += 1
        }

        for (i, node) in inputNodes.enumerated() {
            defs.append(
                PortDef(port: "A\(i)", node: node, intlIndx: intl, extlIndx: extl)
            )
            intl += 1; extl += 1
        }

        return defs
    }
}

public enum SignalRef {
    case ident(String)
}

public enum EdgeChng {
    case edgePos(String)
    case edgeNeg(String)
    case all(String)
    case level(String)
}

public struct EdgeChngYAML: Decodable {
    let edge: String
    let node: String

    func toEdgeChng() throws -> EdgeChng {
        switch edge {
        case "posedge": return .edgePos(node)
        case "negedge": return .edgeNeg(node)
        case "all":     return .all(node)
        case "level":   return .level(node)
        default:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "Unknown onlyif token: \(edge)"
                )
            )
        }
    }
}

public enum SensChng {
    case edgePos([SignalRef])
    case edgeNeg([SignalRef])
    case all([SignalRef])
    case level([SignalRef])
}

public struct RegBlckYAML: Decodable {
    public let kind: String
    public let name: String
    public let signed: String
    var width: WidthYAML
    let length: [LengthYAML]?
}

public struct SyscallStmntYAML: Decodable {
    public let name: String
    public let value: [ExprYAML]?
}

public struct CaseItemYAML: Decodable {
    public let constant: ExprYAML
    public let execs: [[StmntYAML]]
}

public struct CaseStmntYAML: Decodable {
    public let case_cmpr: ExprYAML
    public let cases: [CaseItemYAML]
}

public struct InitBlckYAML: Decodable {
    public let stmnts: [StmntYAML]
}

public struct AlwaysBlckYAML: Decodable {
    public let stmnts: [StmntYAML]
    public let snstvs: [EdgeChng]?

    private enum CodingKeys: String, CodingKey {
        case stmnts
        case onlyif
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.stmnts = try c.decode([StmntYAML].self, forKey: .stmnts)

        if c.contains(.onlyif) {
            let raw = try c.decode([EdgeChngYAML].self, forKey: .onlyif)
            self.snstvs = try raw.map { try $0.toEdgeChng() }
        } else {
            self.snstvs = nil
        }
    }
}

public indirect enum StmntYAML: Decodable {
    case ifst(IfStmntYAML)
    case dost(DoStmntYAML)
    case whlst(WhlStmntYAML)
    case assgnst(AssgnStmntYAML)
    case concatst(ConcatStmntYAML)
    case spcfyst(SpcfyStmntYAML)
    case blckst(BlckStmntYAML)
    case noblckst(NoblckStmntYAML)
    case syscallst(SyscallStmntYAML)
    case forst(ForStmntYAML)
    case casest(CaseStmntYAML)

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    private enum Kind: String, Decodable {
        case ifst
        case dost
        case whlst
        case assgnst
        case concatst
        case spcfyst
        case blckst
        case noblckst
        case syscall
        case forst
        case casest
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .ifst:
            self = .ifst(try IfStmntYAML(from: decoder))  // NEW
        case .dost:
            self = .dost(try DoStmntYAML(from: decoder))
        case .whlst:
            self = .whlst(try WhlStmntYAML(from: decoder))
        case .assgnst:
            self = .assgnst(try AssgnStmntYAML(from: decoder))
        case .concatst:
            self = .concatst(try ConcatStmntYAML(from: decoder))
        case .spcfyst:
            self = .spcfyst(try SpcfyStmntYAML(from: decoder))
        case .blckst:
            self = .blckst(try BlckStmntYAML(from: decoder))
        case .noblckst:
            self = .noblckst(try NoblckStmntYAML(from: decoder))
        case .syscall:
            self = .syscallst(try SyscallStmntYAML(from: decoder))
        case .forst:
            self = .forst(try ForStmntYAML(from: decoder))
        case .casest:
            self = .casest(try CaseStmntYAML(from: decoder))
        }
    }
}

public struct IfStmntYAML: Decodable {
    public let cmpr_expr: ExprYAML
    public let iftrue: [StmntYAML]
    public let ifelse: [StmntYAML]

    private enum CodingKeys: String, CodingKey {
        case cmpr_expr
        case iftrue
        case ifelse
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.cmpr_expr = try c.decode(ExprYAML.self, forKey: .cmpr_expr)
        self.iftrue    = try c.decode([StmntYAML].self, forKey: .iftrue)
        self.ifelse    = try c.decodeIfPresent([StmntYAML].self, forKey: .ifelse) ?? []
    }
}

public struct LValueYAML: Decodable {
    public let kind: String
    public let name: String?
    public let index: Int?
    public let msb: Int?
    public let lsb: Int?
    public let base: Int?
    public let width: Int?
    public let parts: [LValueYAML]?

    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case index
        case msb
        case lsb
        case base
        case width
        case parts
        case sgmnts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let kind  = try c.decode(String.self, forKey: .kind)
        let name  = try c.decodeIfPresent(String.self, forKey: .name)
        var index = try c.decodeIfPresent(Int.self, forKey: .index)
        var msb   = try c.decodeIfPresent(Int.self, forKey: .msb)
        var lsb   = try c.decodeIfPresent(Int.self, forKey: .lsb)
        let base  = try c.decodeIfPresent(Int.self, forKey: .base)
        let width = try c.decodeIfPresent(Int.self, forKey: .width)
        let parts = try c.decodeIfPresent([LValueYAML].self, forKey: .parts)

        if c.contains(.sgmnts) {
            if let segs = try? c.decode([ExprYAML].self, forKey: .sgmnts) {
                let ints = segs.compactMap { expr -> Int? in
                    if case .int(let i) = expr { return i }
                    return nil
                }

                if kind == "bit", ints.count >= 1 {
                    index = ints[0]
                } else if kind == "slice", ints.count >= 2 {
                    msb = ints[0]
                    lsb = ints[1]
                }
            } else if let ints = try? c.decode([Int].self, forKey: .sgmnts) {
                if kind == "bit", ints.count >= 1 {
                    index = ints[0]
                } else if kind == "slice", ints.count >= 2 {
                    msb = ints[0]
                    lsb = ints[1]
                }
            }
        }

        self.kind = kind
        self.name = name
        self.index = index
        self.msb = msb
        self.lsb = lsb
        self.base = base
        self.width = width
        self.parts = parts
    }

    init(kind: String, name: String? = nil, index: Int? = nil,
         msb: Int? = nil, lsb: Int? = nil, base: Int? = nil,
         width: Int? = nil, parts: [LValueYAML]? = nil) {
        self.kind = kind; self.name = name; self.index = index
        self.msb = msb; self.lsb = lsb; self.base = base
        self.width = width; self.parts = parts
    }
}

public struct BlckStmntYAML: Decodable {
    public let lvalue: LValueYAML
    public let rvalue: ExprYAML
    public let delay: DelayExpr?      // optional 1–3 delay values
}

public struct NoblckStmntYAML: Decodable {
    public let lvalue: LValueYAML
    public let rvalue: ExprYAML
    public let delay: DelayExpr?      // same model
}

public struct WhlStmntYAML : Decodable {
    public let cmpr: ExprYAML
    public let blck: [StmntYAML]
}

public struct ForStmntYAML: Decodable {
    public let cmpr_expr: ExprYAML
    public let pre: StmntYAML
    public let post: StmntYAML
    public let body: [StmntYAML]
}

public struct DoStmntYAML : Decodable {
    public let cmpr: ExprYAML
    public let blck: [StmntYAML]
    public let preblck: [StmntYAML]
    public let postblck: [StmntYAML]
}

/*
public struct AssgnStmntYAML: Decodable {
    public let node: String
    public let assgns: [SingleAssgnYAML]
}
*/

public struct AssgnStmntYAML: Decodable {
    public let assgns: [SingleAssgnYAML]
}

public struct SingleAssgnYAML: Decodable {
    public let lhs: LValueYAML
    public let rhs: ExprYAML
}

public struct ConcatStmntYAML: Decodable {
    public let node: String
    public let concats: [SingleConcatYAML]
}

public struct SingleConcatYAML: Decodable {
    public let lhs: LValueYAML
    public let rhs: ExprYAML
}

public struct SrcSgnlYAML : Decodable {
    public let sgnls: [String]
    public let edge: String
}

public struct DstSgnlYAML : Decodable {
    public let sgnls: [String]
    public let pthspc: String
}

public struct DlySpcYAML : Decodable {
    public let variant: String
    public let delay: Number
}

public struct UnaryYAML: Decodable {
    public let op: UOp
    public let rhs: ExprYAML
}

public struct BinaryYAML: Decodable {
    public let op: BnOp
    public let lhs: ExprYAML
    public let rhs: ExprYAML
}

extension BehavBlckYAML {
    public func toAST(in circ: inout CircDef) -> BehavBlckAST {
        switch self {
        case .spcfyblck(let s):
            return .spcfyblck(s.toAST(in: &circ))

        case .initblck(let s):
            return .initblck(s.toAST(in: &circ))

        case .alwaysblck(let s):
            return .alwaysblck(s.toAST(in: &circ))

        case .assgnblck(let s):
            return .assgnblck(s.toAST(in: &circ))

        case .instncblck(let g):
            return .instncblck(g)

        case .subcircblck(let g):
            return .subcircblck(g)

        case .asyncblck(let g):
            return .asyncblck(g)

        case .syncblck(let g):
            return .syncblck(g)

        case .gateblck(let g):
            return .gateblck(g)

        case .regblck(let r):
            circ.decls.append([DeclYAML(kind: r.kind, name: r.name, signed: r.signed, width: r.width, length: r.length)])
            return .regblck(r)
        }
    }
}

extension StmntYAML {
    func compileStmt(in circ: inout CircDef) -> StmtId {
        let ast: StmntAST
        switch self {
        case .ifst(let s):
            ast = .ifst(s.toAST(in: &circ))
        case .dost(let s):
            ast = .dost(s.toAST(in: &circ))
        case .whlst(let s):
            ast = .whlst(s.toAST(in: &circ))
        case .assgnst(let s):
            ast = .assgnst(s.toAST(in: &circ))
        case .concatst(let s):
            ast = .concatst(s.toAST(in: &circ))
        case .spcfyst(let s):
            ast = .spcfyst(s.toAST(in: &circ))
        case .blckst(let s):
            ast = .blckst(s.toAST(in: &circ))
        case .noblckst(let s):
            ast = .noblckst(s.toAST(in: &circ))
        case .syscallst(let s):
            ast = s.name == "readmemh" ? .readmemh : .syscallst
        case .forst(let s):
            ast = .forst(s.toAST(in: &circ))
        case .casest(let s):
            ast = .casest(s.toAST(in: &circ))
        }
        return circ.internStmt(ast)
    }
}

extension IfStmntYAML {
    func toAST(in circ: inout CircDef) -> IfStmntAST {
        IfStmntAST(
            cmpr: cmpr_expr.toExprId(in: &circ),
            iftrue: BlockAST(stmnts: iftrue.map { $0.compileStmt(in: &circ) }),
            ifelse: BlockAST(stmnts: ifelse.map { $0.compileStmt(in: &circ) })
        )
    }
}

extension InitBlckYAML {
    public func toAST(in circ: inout CircDef) -> InitBlckAST {
        let stmtIds = stmnts.map { $0.compileStmt(in: &circ) }
        return InitBlckAST(body: BlockAST(stmnts: stmtIds))
    }
}

extension LValueYAML {
    public func toAST() -> LValueAST {
        switch kind {
        case "ident":
            guard let name else { fatalError("ident missing name") }
            return .net(name: name)

        case "bit":
            guard let name, let index else { fatalError("bit missing name or index") }
            return .bitSelect(name: name, index: index)

        case "slice":
            guard let name, let msb, let lsb else { fatalError("slice missing fields") }
            return .partSelect(name: name, msb: msb, lsb: lsb)

        case "indexed":
            guard let name, let base, let width else { fatalError("indexed missing fields") }
            return .indexedPartSelect(name: name, base: base, width: width)

        case "concat":
            let astParts = (parts ?? []).map { $0.toAST() }
            return .concat(astParts)

        default:
            fatalError("Unknown LValueYAML kind: \(kind)")
        }
    }
}

/*
Not currently being used anywhere and is wrong
func makeAssgnStmnt(from block: AssgnBlckAST) -> AssgnBody {
    // 1. Extract node name; only .net is allowed here.
    let node: String
    switch block.lvalue {
    case .net(let name):
        node = name
    default:
        preconditionFailure("Expected .net lvalue in assignment block")
    }

    let rhs = block.rvalue

    let single = AssgnAST(
        lvalue: block.lvalue,
        rvalue: rhs,
        delay: block.delay
    )

    return AssgnBody(
        assgns: [single]
    )
}
*/

public extension AssgnBlckYAML {
    func toAST(in circ: inout CircDef) -> AssgnBlckAST {
        let assgn = AssgnAST(
            lvalue: lvalue.toAST(),                 // your existing LValueYAML → LValueAST
            rvalue: rvalue.toExprId(in: &circ),     // use the RValueYAML helper
            delay: delay,
        )
        let assgnBody = AssgnBody(assgns: [assgn])
        let assgnBlck = AssgnBlckAST(body: assgnBody, code: [])
        return assgnBlck
    }

}

extension SpcfyBlckYAML {
    public func toAST(in circ: inout CircDef) -> SpcfyBlckAST {
        SpcfyBlckAST(
            variant: variant,
            delay_expr: delay_expr,
            src_sgnls: src_sgnls,
            edge: edge,
            dst_sgnls: dst_sgnls,
            pth_spc: pth_spc
        )
    }
}

extension AlwaysBlckYAML {
    func toAST(in circ: inout CircDef) -> AlwaysBlckAST {
        return AlwaysBlckAST(
            snstvs: snstvs,  // already [EdgeChng]?
            body: BlockAST(stmnts: stmnts.map { $0.compileStmt(in: &circ) })
        )
    }
}

extension GateInstYAML {
    public func toAST(in circ: inout CircDef) -> GateInstAST {
        let outNode = outputNode ?? "_UNCONNECTED"
        let inNodes = inputNodes

        // Optional: register nodes in circ here, if that’s what other blocks do.
        // e.g. circ.ensureNode(outNode); inNodes.forEach { circ.ensureNode($0) }

        let delayExpr: ExprYAML?
        if let d = delay?.first {        // if you only expect one delay expr
            delayExpr = d
        } else {
            delayExpr = nil
        }

        return GateInstAST(
            name: name,
            gate: gate,
            output: outNode,
            inputs: inNodes,
            delay: delayExpr
        )
    }
}

extension WhlStmntYAML {
    public func toAST(in circ: inout CircDef) -> WhlStmntAST {
        WhlStmntAST(
            cmpr: cmpr.toExprId(in: &circ),
            blck: BlockAST(stmnts: blck.map { $0.compileStmt(in: &circ) })
        )
    }
}

extension DoStmntYAML {
    func toAST(in circ: inout CircDef) -> DoStmntAST {
        DoStmntAST(
            cmpr: cmpr.toExprId(in: &circ),
            blck: BlockAST(stmnts: blck.map { $0.compileStmt(in: &circ) }),
            preblck: BlockAST(stmnts: preblck.map { $0.compileStmt(in: &circ) }),
            postblck: BlockAST(stmnts: postblck.map { $0.compileStmt(in: &circ) })
        )
    }
}

extension CaseItemYAML {
    func toAST(in circ: inout CircDef) -> CaseItemAST {
        let stmtIds = execs.flatMap { $0.map { $0.compileStmt(in: &circ) } }
        return CaseItemAST(
            cmpr: constant.toExprId(in: &circ),
            body: BlockAST(stmnts: stmtIds)
        )
    }
}

extension CaseStmntYAML {
    func toAST(in circ: inout CircDef) -> CaseStmntAST {
        CaseStmntAST(
            cmpr: case_cmpr.toExprId(in: &circ),
            items: cases.map { $0.toAST(in: &circ) },
            defaultBody: nil
        )
    }
}

extension ForStmntYAML {
    func toAST(in circ: inout CircDef) -> ForStmntAST {
        ForStmntAST(
            cmpr: cmpr_expr.toExprId(in: &circ),
            pre: pre.compileStmt(in: &circ),
            post: post.compileStmt(in: &circ),
            body: BlockAST(stmnts: body.map { $0.compileStmt(in: &circ) })
        )
    }
}

extension SingleAssgnYAML {
    func toAST(in circ: inout CircDef) -> AssgnAST {
        let lhsAST = lhs.toAST()
        let w   = lhsAST.Lwidth(in: circ)

        let assgnAST = AssgnAST(
            lvalue: lhsAST,
            lwidth: w,
            rvalue: rhs.toExprId(in: &circ),
            delay: 0.0
        )
        return assgnAST
    }
}

extension AssgnStmntYAML {
    func toAST(in circ: inout CircDef) -> AssgnBody {
        let assgnAsts = assgns.map { $0.toAST(in: &circ) }
        return AssgnBody(assgns: assgnAsts)
    }
}

extension BlckStmntYAML {
    func toAST(in circ: inout CircDef) -> BlckStmntAST {
        let l = lvalue.toAST()
        let r = rvalue.toExprId(in: &circ)

        // Delay: default 0 if nil, otherwise convert via asInt()
        let delayInt: Int = delay.map { $0.asInt() } ?? 0

        return BlckStmntAST(
            lvalue: l,
            rvalue: r,
            delay: delayInt
        )
    }
}

extension NoblckStmntYAML {
    func toAST(in circ: inout CircDef) -> NoblckStmntAST {
        let l = lvalue.toAST()
        let r = rvalue.toExprId(in: &circ)

        // Delay: default 0 if nil, otherwise convert via asInt()
        let delayInt: Int = delay.map { $0.asInt() } ?? 0

        return NoblckStmntAST(
            lvalue: l,
            rvalue: r,
            delay: delayInt
        )
    }
}

extension SpcfyStmntYAML {
    func toAST(in circ: inout CircDef) -> SpcfyStmntAST {
        let astKind: String? = variant

        let firstDelay = delay_expr.first
        let dlyAst = DlySpcAST(
            variant: variant,
            delay: firstDelay?.value ?? 0
        )

        let srcAst = SrcSgnlAST(
            sgnls: src_sgnls,
            edge: edge
        )

        let dstAst = DstSgnlAST(
            sgnls: dst_sgnls,
            pthspc: variant
        )

        return SpcfyStmntAST(
            kind: astKind,
            srcSgnls: [srcAst],
            dstSgnls: [dstAst],
            dly: dlyAst
        )
    }
}

public enum CmprOpr: String, Decodable {
    case lt  = "<"
    case lte = "<="
    case gt  = ">"
    case gte = ">="
    case eq  = "=="
    case neq = "!="
    case lgcor = "||"
    case lgcand = "&&"
}

public enum CmpExpr: Decodable {
    case lt(String)
    case lte(String)
    case gt(String)
    case gte(String)
    case eq(String)
    case neq(String)
    case lgcor(String)
    case lgcand(String)
}

public enum BinLgcOp: String, Decodable {
    case and = "&"
    case or = "|"
    case exor = "^"
}

public enum BinArithOp: String, Decodable {
    case add = "+"
    case sub = "-"
    case mul = "*"
    case div = "/"
    case mod = "%"
}

public enum BinOp: String, Decodable {
    case add = "+"
    case sub = "-"
    case mul = "*"
    case div = "/"
    case mod = "%"
    case lt  = "<"
    case lte = "<="
    case gt  = ">"
    case gte = ">="
    case eq  = "=="
    case neq = "!="
    case lgcor = "||"
    case lgcand = "&&"
    case and = "&"
    case or = "|"
    case exor = "^"
}

/*
public enum BOp: String, Decodable {
    case plus = "Plus:"
    case minus = "Minus:"
    case times = "Times:"
    case div = "Divide:"
    case mod = "Mod:"
    case lt  = "LessThan:"
    case lte = "LessEq:"
    case gt  = "GreaterThan:"
    case gte = "GreaterEq:"
    case eq  = "Eq:"
    case neq = "NotEq:"
    case lgcor = "Lor:"
    case lgcand = "Land:"
    case and = "And:"
    case or = "Or:"
    case exor = "Xor:"
    case exnor = "Xnor:"
}
*/

public enum SOp: String, Decodable {
    case sll = "Sll:"
    case srl = "Srl:"
    case sla = "Sla:"
    case sra = "Sra:"
}

public enum BnOp: String, Decodable {
    case plus = "BPlus:"
    case minus = "BMinus:"
    case times = "BTimes:"
    case div = "BDivide:"
    case mod = "BMod:"
    case lt  = "BLessThan:"
    case lte = "BLessEq:"
    case gt  = "BGreaterThan:"
    case gte = "BGreaterEq:"
    case eq  = "BEq:"
    case neq = "BNotEq:"
    case lgcor = "BLor:"
    case lgcand = "BLand:"
    case and = "BAnd:"
    case or = "BOr:"
    case nand = "BNand:"
    case nor = "BNor:"
    case xor = "BXor:"
    case xnor = "BXnor:"
    case sll = "BSll:"
    case srl = "BSrl:"
    case sla = "BSla:"
    case sra = "BSra:"

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        if let op = BnOp(rawValue: raw) { self = op; return }
        if let op = BnOp(rawValue: "B" + raw) { self = op; return }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
            debugDescription: "Unknown BnOp: \(raw)"))
    }
}

public enum CmprOp: String, Decodable {
    case lt  = "LessThan:"
    case lte = "LessEq:"
    case gt  = "GreaterThan:"
    case gte = "GreaterEq:"
    case eq  = "Eq:"
    case neq = "NotEq:"
    case lgcor = "Lor:"
    case lgcand = "Land:"
}

public enum UOp: String, Decodable {
    case plus    = "UPlus:"    // unary +
    case minus   = "UMinus:"   // unary -

    case lgcnot  = "Ulnot:"    // logical !
    case not     = "Unot:"     // bitwise ~

    case and     = "Uand:"     // reduction &
    case nand    = "Unand:"    // reduction ~&
    case or      = "Uor:"      // reduction |
    case nor     = "Unor:"     // reduction ~|
    case xor     = "UXor:"     // reduction ^
    case xnor    = "UXnor:"    // reduction ~^ or ^~
}

public enum GOp: String, Decodable {
    case or = "Or:"
    case and = "And:"
    case nand = "Nand:"
    case nor = "Nor:"
    case xor = "Xor:"
    case xnor = "Xnor:"
}

/*
public enum Ex: String, Decodable {
    case int(Int)
    case bool(Bool)
    case real(Double)
    case plus = "BPlus:"
    case minus = "BMinus:"
    case times = "BTimes:"
    case div = "BDivide:"
    case mod = "BMod:"
    case lt  = "BLessThan:"
    case lte = "BLessEq:"
    case gt  = "BGreaterThan:"
    case gte = "BGreaterEq:"
    case eq  = "BEq:"
    case neq = "BNotEq:"
    case lgcor = "BLor:"
    case lgcand = "BLand:"
    case and = "BAnd:"
    case or = "BOr:"
    case nand = "BNand:"
    case nor = "BNor:"
    case xor = "BXor:"
    case xnor = "BXnor:"
    case sll = "BSll:"
    case srl = "BSrl:"
    case sla = "BSla:"
    case sra = "BSra:"
    case lgcnot = "Ulnot:"
    case not = "Unot:"
}
*/

public struct BehavAST {
    public var behav_blcks: [BehavBlckAST]
}

public enum LValueAST {
    case net(name: String)
    case bitSelect(name: String, index: Int)
    case partSelect(name: String, msb: Int, lsb: Int)
    case indexedPartSelect(name: String, base: Int, width: Int)
    case concat([LValueAST])
}

public func describeLValue(_ lv: LValueAST) -> String {
    switch lv {
    case .net(let name):
        return name
    case .bitSelect(let name, let index):
        return "\(name)[\(index)]"
    case .partSelect(let name, let msb, let lsb):
        return "\(name)[\(msb):\(lsb)]"
    case .indexedPartSelect(let name, let base, let width):
        return "\(name)[\(base)+:\(width)]"
    case .concat(let parts):
        let inner = parts.map { describeLValue($0) }.joined(separator: ", ")
        return "{\(inner)}"
    }
}

extension LValueAST: CustomStringConvertible {
    public var description: String {
        switch self {
        case .net(let name):
            return name
        case .bitSelect(let name, let index):
            return "\(name)[\(index)]"
        case .partSelect(let name, let msb, let lsb):
            return "\(name)[\(msb):\(lsb)]"
        case .indexedPartSelect(let name, let base, let width):
            return "\(name)[\(base)+:\(width)]"
        case .concat(let parts):
            let inner = parts.map { $0.description }.joined(separator: ", ")
            return "{\(inner)}"
        }
    }
}

public extension LValueAST {
    /// Compute the width of this lvalue, using circDef for net widths.
    func Lwidth(in circ: CircDef) -> Int {
        switch self {
        case .net(let name):
            let nd = circ.getNode(name)
            return nd!.node.nbits

        case .bitSelect:
            return 1

        case .partSelect(_, let msb, let lsb):
            return abs(msb - lsb) + 1

        case .indexedPartSelect(_, _, let width):
            return width

        case .concat(let parts):
            return parts.reduce(0) { $0 + $1.Lwidth(in: circ) }
        }
    }
}

public extension LValueAST {
    /// Returns the plain net name if this lvalue is a simple net.
    /// Traps for bit/part/indexed selects and concats.
    var nodeNm: String {
        switch self {
        case .net(let name):
            return name
        default:
            fatalError("LValueAST.asPlainNetName only valid for .net, got \(self)")
        }
    }
}

public struct InitBlckAST {
    public let body: BlockAST
    public var code: [Instruction] = []
}

public struct AlwaysBlckAST {
    public let snstvs: [EdgeChng]?
    public let body: BlockAST
    public var code: [Instruction] = []
}

public enum BehavBlockKind {
    case initBlock(Int)    // index into circuit.initStates
    case alwaysBlock(Int)  // index into circuit.alwaysStates
    case assgnBlock(Int)
}

public struct SpcfyBlckAST {
    public let variant: SpecifyVariant
    public let delay_expr: DelayExpr
    public let src_sgnls: [String]
    public let edge: Edge
    public let dst_sgnls: [String]
    public let pth_spc: PathSpecifier?
}

public struct AssgnBlckAST {
    public var body: AssgnBody
    public var code: [Instruction] = []   // new: code to compute RHS
}

public struct GateInstAST {
    public let name: String       // instance name
    public let gate: String       // primitive kind
    public let output: String     // output node
    public let inputs: [String]   // input nodes
    public let delay: ExprYAML?    // or [ExprAST] if you prefer
}

extension GateInstAST {
    public func toPortDefs(
        intlStart: Int = 1_000_000,
        extlStart: Int = 1_000_000
    ) -> [PortDef] {
        var defs: [PortDef] = []
        var intl = intlStart
        var extl = extlStart

        defs.append(PortDef(port: "Y", node: output,
                            intlIndx: intl, extlIndx: extl))
        intl += 1; extl += 1

        for (i, node) in inputs.enumerated() {
            defs.append(PortDef(port: "A\(i)", node: node,
                                intlIndx: intl, extlIndx: extl))
            intl += 1; extl += 1
        }

        return defs
    }
}

public struct BlckStmntAST {
    public let lvalue: LValueAST
    public let lwidth: Int = 1
    public let rvalue: ExprId
    public let delay: Int?         // optional array
}

public struct NoblckStmntAST {
    public let lvalue: LValueAST
    public let lwidth: Int = 1
    public let rvalue: ExprId
    public let delay: Int?         // optional array
}

public struct BlockAST {
    public let stmnts: [StmtId]
}

public struct IfStmntAST {
    public let cmpr: ExprId
    public let iftrue: BlockAST
    public let ifelse: BlockAST?
}

public struct WhlStmntAST {
    public let cmpr: ExprId
    public let blck: BlockAST
}

public struct DoStmntAST {
    public let cmpr: ExprId        // loop condition
    public let blck: BlockAST      // main body
    public let preblck: BlockAST   // executes before main body
    public let postblck: BlockAST  // executes after main body
}

public struct ForStmntAST {
    public let cmpr: ExprId
    public let pre: StmtId
    public let post: StmtId
    public let body: BlockAST
}

public struct DelayExprItemYAML: Decodable {
    public let type: String   // "delay"
    public let value: Int
}

public struct SpcfyStmntYAML: Decodable {
    public let type: String          // "specify"
    public let variant: String       // "full"
    public let delay_expr: [DelayExprItemYAML]
    public let src_sgnls: [String]
    public let edge: String
    public let dst_sgnls: [String]
}

public struct AssgnAST {
    public let lvalue: LValueAST
    public var lwidth: Int = 1
    public let rvalue: ExprId
    public let delay: Double?
}

public struct AssgnBody {
    public let assgns: [AssgnAST]
}

public struct ConcatStmntAST {
    public let node: String
    public let concats: [SingleConcatAST]
}

public struct SingleConcatAST {
    public let lvalue: LValueAST
    public let lwidth: Int = 1
    public let rvalue: ExprId
    public let delay: Double?
}

public struct CaseItemAST {
    /// Value to compare the switch expression against.
    public let cmpr: ExprId

    /// Statements to execute when this case matches.
    public let body: BlockAST
}

public struct CaseStmntAST {
    /// The expression in `case (cmpr)`.
    public let cmpr: ExprId

    /// Ordered list of case items.
    public let items: [CaseItemAST]

    /// Optional default block; executed if no item matches.
    public let defaultBody: BlockAST?
}


extension SingleConcatYAML {
    func toAST(in circ: inout CircDef) -> SingleConcatAST {
        SingleConcatAST(
            lvalue: lhs.toAST(),
            rvalue: rhs.toExprId(in: &circ),
            delay: 0.0
        )
    }
}

extension ConcatStmntYAML {
    func toAST(in circ: inout CircDef) -> ConcatStmntAST {
        let concatAsts = concats.map { $0.toAST(in: &circ) }
        return ConcatStmntAST(node: node, concats: concatAsts)
    }
}

public struct SrcSgnlAST {
    public let sgnls: [String]
    public let edge: String
}

public struct DstSgnlAST {
    public let sgnls: [String]
    public let pthspc: String
}

public struct DlySpcAST {
    public let variant: String
    public let delay: Int
}

public struct SpcfyStmntAST {
    public let kind: String?            // Verilog classify: FULL / PARALLEL / etc.
    public let srcSgnls: [SrcSgnlAST]
    public let dstSgnls: [DstSgnlAST]
    public let dly: DlySpcAST
}

public enum BehavBlckAST {
    case spcfyblck(SpcfyBlckAST)
    case initblck(InitBlckAST)
    case alwaysblck(AlwaysBlckAST)
    case assgnblck(AssgnBlckAST)
    case instncblck(VrlgInstYAML)   // new
    case subcircblck(VrlgInstYAML)
    case asyncblck(VrlgInstYAML)
    case syncblck(VrlgInstYAML)
    case gateblck(GateInstYAML)   // new
    case regblck(RegBlckYAML)
}

public enum StmntAST {
    case ifst(IfStmntAST)
    case dost(DoStmntAST)
    case casest(CaseStmntAST)
    case noblckst(NoblckStmntAST)
    case blckst(BlckStmntAST)
    case whlst(WhlStmntAST)
    case assgnst(AssgnBody)
    case concatst(ConcatStmntAST)
    case spcfyst(SpcfyStmntAST)
    case syscallst
    case readmemh
    case forst(ForStmntAST)
}

public struct SmallNod {
    public var name: String = ""
    public var node: TwoCmplt
    public var updTm: Int
}

public enum Value {
    case int(Int)
    case uint(UInt)
    case real(Double)
    case bool(Bool)
    case twoCmplt(SmallNod)
}

extension Value: Equatable {
    public static func == (lhs: Value, rhs: Value) -> Bool {
        switch (lhs, rhs) {
        case let (.int(a), .int(b)):
            return a == b

        case let (.uint(a), .uint(b)):
            return a == b

        case let (.real(a), .real(b)):
            return a == b

        case let (.bool(a), .bool(b)):
            return a == b

        case let (.twoCmplt(a), .twoCmplt(b)):
            return a.name == b.name && a.node == b.node   // ignore updTm

        default:
            return false
        }
    }
}

public extension Value {
    var int: Int? {
        if case let .int(x) = self { return x }
        return nil
    }

    var real: Double? {
        if case let .real(x) = self { return x }
        return nil
    }

    var bool: Bool? {
        if case let .bool(x) = self { return x }
        return nil
    }

    var two: SmallNod? {
        if case let .twoCmplt(x) = self { return x }
        return nil
    }

    var asInt: Int {
        switch self {
        case .int(let x):
            return x
        case .uint(let x):
            return Int(x)
        case .real(let x):
            return x == 0 ? 0 : Int(x)
        case .bool(let b):
            return b ? 1 : 0
        case .twoCmplt(let t):
            return t.node.toInt()          // or however you extract its signed Int
        }
    }

    /// Logical true: anything nonzero.
    var isTrue: Bool {
        return asInt != 0
    }

    /// Logical false: exactly zero.
    var isFalse: Bool {
        return asInt == 0
    }

    static var logicTrue: Value { .int(1) }
    static var logicFalse: Value { .int(0) }
}

public struct Exp {
    public let kind: String       // "int", "real", "bool", "BPlus:", "UPlus:", ...
    public let value: Value?     // nil for operators

    public init(kind: String, value: Value?) {
        self.kind = kind
        self.value = value
    }
}

extension DelayExpr {
    func toExprId(in circ: inout CircDef) -> ExprId {
        switch self {
        case .int(let v):
            return circ.internExpr(Expr.int(v))
        case .float(let d),
             .arith(let d):
            return circ.internExpr(Expr.real(d))
        }
    }
}

public func eval(exp: Exp, lhs: Value?, rhs: Value?) -> Value {
    switch exp.kind {

    case "int", "real", "bool":
        guard let v = exp.value else {
            fatalError("\(exp.kind) without value")
        }
        return v

    default:
        break
    }

    // Try binary op
    if let bop = BnOp(rawValue: exp.kind) {
        guard let lhs, let rhs else {
            fatalError("missing operands for binary op \(bop)")
        }
        return evalBinary(bop, lhs: lhs, rhs: rhs)
    }

    // Try unary op
    if let uop = UOp(rawValue: exp.kind) {
        guard let lhs else {
            fatalError("missing operand for unary op \(uop)")
        }
        return evalUnary(uop, operand: lhs)
    }

    fatalError("unknown kind \(exp.kind)")
}

public func evalBinary(_ op: BnOp, lhs: Value, rhs: Value) -> Value {
    applyBinaryOp(op, lhs, rhs)
}

public func evalUnary(_ op: UOp, operand: Value) -> Value {
    applyUnaryOp(op, operand)
}

public func expEval(_ exps: [Exp], args: [Value]) -> Value {
    var stack: [Value] = []

    for exp in exps {
        switch exp.kind {
        case "int", "real", "bool":
            guard let v = exp.value else {
                fatalError("missing value for literal")
            }
            stack.append(v)

        default:
            if exp.kind.hasPrefix("B") {
                guard let rhs = stack.popLast(),
                      let lhs = stack.popLast() else {
                    fatalError("stack underflow")
                }
                let result = eval(exp: exp, lhs: lhs, rhs: rhs)
                stack.append(result)
            } else if exp.kind.hasPrefix("U") {
                guard let lhs = stack.popLast() else {
                    fatalError("stack underflow")
                }
                let result = eval(exp: exp, lhs: lhs, rhs: nil)
                stack.append(result)
            } else {
                fatalError("Exp's are not correct")
            }
        }
    }

    guard let final = stack.last, stack.count == 1 else {
        fatalError("expression did not reduce to a single value")
    }
    return final
}

