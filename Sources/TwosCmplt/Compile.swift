import Foundation
import Yams
import SharedTypes

public func generateCode(for circDef: inout CircDef,
                         ctx: inout Context)
{
    circDef.clearBehav()
    circDef.copyBehav()
    ctx.circDef = circDef
    ctx.circ!.initStates = Array(repeating: InitState(), count: ctx.circDef.initBlcks.count)
    ctx.circ!.alwaysStates = Array(repeating: AlwaysState(), count: ctx.circDef.alwaysBlcks.count)

    generateAllBlcks(&circDef.behav, ctx: &ctx)
    circDef.timingArcs = ctx.timingArcs
    ctx.circDef.timingArcs = ctx.timingArcs
}

public func generateAllBlcks(_ behav: inout [BehavBlckAST],
                             ctx: inout Context) {
    var prevKind: String? = nil
    var typeIdx = 0
    for i in behav.indices {
        let kind: String
        switch behav[i] {
        case .initblck:   kind = "init"
        case .alwaysblck: kind = "always"
        case .assgnblck:  kind = "assgn"
        default:          kind = "other"
        }
        if kind == prevKind {
            typeIdx += 1
        } else {
            typeIdx = 0
            prevKind = kind
        }
        generateBlock(at: i, typeIdx: typeIdx, behav: &behav, ctx: &ctx)
    }
}


public func generateBlock(at index: Int,
                          typeIdx: Int,
                          behav: inout [BehavBlckAST],
                          ctx: inout Context) {
    var crcDf = ctx.circDef
    ctx.code = []

    switch behav[index] {
    case .initblck(var initBlk):
        ctx.behavIdx = .initBlock(typeIdx)
        let code = generateInitBlock(initBlk, ctx: &ctx)
        initBlk.code = code
        crcDf.initBlcks[typeIdx].code = code

    case .alwaysblck(var alwaysBlk):
        ctx.behavIdx = .alwaysBlock(typeIdx)
        let code = generateAlwaysBlock(alwaysBlk, ctx: &ctx)
        alwaysBlk.code = code
        crcDf.alwaysBlcks[typeIdx].code = code

    case .assgnblck(var assgnBlk):
        ctx.behavIdx = .assgnBlock(typeIdx)
        let code = generateAssignBlock(assgnBlk, ctx: &ctx)
        assgnBlk.code = code
        behav[index] = .assgnblck(assgnBlk)
        crcDf.assgnBlcks[typeIdx].code = code

    case .spcfyblck(let spcfyBlk):
        generateSpecifyBlock(spcfyBlk, ctx: &ctx)

    case .instncblck(let instncBlk):
        _ = instncBlk
        break

    case .subcircblck(let instncBlk):
        _ = instncBlk
        break

    case .asyncblck(let instncBlk):
        _ = instncBlk
        break

    case .syncblck(let instncBlk):
        _ = instncBlk
        break

    case .gateblck(let gateBlk):
        _ = gateBlk
        break

    case .regblck:
        break
    }
    ctx.circDef = crcDf
}

public func generateAlwaysBlock(_ alwaysBlk: AlwaysBlckAST,
                                ctx: inout Context) -> [Instruction]
{
    ctx.code = []
    genBlock(alwaysBlk.body, ctx: &ctx)
    let code = ctx.code
    return code
}

public func generateInitBlock(_ initBlk: InitBlckAST,
                              ctx: inout Context) -> [Instruction] {
    ctx.code = []
    genBlock(initBlk.body, ctx: &ctx)
    let code = ctx.code
    return code
}

public func generateAssignBlock(_ blk: AssgnBlckAST,
                                ctx: inout Context) -> [Instruction] {
    ctx.code = []
    let assgns = blk.body.assgns
    if assgns.count >= 0 {
        for assgn in assgns {
            genAssgnStmtCode(assgn, ctx: &ctx)
        }
    }
    let code = ctx.code
    return code
}

func lvalueBaseName(_ lv: LValueAST) -> String {
    switch lv {
    case .net(let name),
         .bitSelect(let name, _),
         .partSelect(let name, _, _),
         .indexedPartSelect(let name, _, _):
        return name
    case .concat:
        return "<concat>"
    }
}

// Like lvalueBaseName, but decomposes a .concat target into every node name
// it writes, rather than collapsing it to a single placeholder. Used to
// build a continuous assign's write set for Kahn's-algorithm scheduling
// (see CircDef.md).
func lvalueBaseNames(_ lv: LValueAST) -> [String] {
    switch lv {
    case .net(let name),
         .bitSelect(let name, _),
         .partSelect(let name, _, _),
         .indexedPartSelect(let name, _, _):
        return [name]
    case .concat(let parts):
        return parts.flatMap { lvalueBaseNames($0) }
    }
}

// Collects every node name referenced anywhere in an expression tree — used
// to build a continuous assign's read set for Kahn's-algorithm scheduling
// (see CircDef.md). Recurses through every Expr case that can nest further
// ExprIds; a .select's own bound expressions are walked too, in case a
// bound is itself an expression referencing other nodes (e.g. a
// parameterized slice).
func referencedNodeNames(_ id: ExprId, in circDef: CircDef) -> Set<String> {
    var names: Set<String> = []
    func walk(_ id: ExprId) {
        switch circDef.expr(for: id) {
        case .int, .real:
            break
        case .node(let name):
            names.insert(name)
        case .select(let name, let args):
            names.insert(name)
            for a in args { walk(a) }
        case .unary(_, let arg):
            walk(arg)
        case .binary(_, let args),
             .gate(_, let args),
             .syscall(_, let args),
             .cndtn(let args),
             .concat(let args):
            for a in args { walk(a) }
        }
    }
    walk(id)
    return names
}

public func delayExprToNumber(_ d: DelayExpr) -> Number {
    switch d {
    case .float(let v):
        return .real(v)

    case .int(let i):
        return .int(i)

    case .arith(let v):
        // Treat arithmetic delay as real for now.
        return .real(v)
    }
}

public func delayToInt(_ d: DelayExpr) -> Int {
    switch d {
    case .float(let v):
        return Int(v)

    case .int(let i):
        return i

    case .arith(let v):
        // Treat arithmetic delay as real for now.
        return Int(v)
    }
}

public func generateSpecifyBlock(_ blk: SpcfyBlckAST, ctx: inout Context) {
    // 1. Src signals + edge
    let src = SrcSgnlAST(
        sgnls: blk.src_sgnls,
        edge: blk.edge.rawValue        // "posedge", "negedge", "all", "level"
    )

    // 2. Dst signals + path specifier
    let pathString: String = blk.pth_spc?.rawValue ?? ""   // "pluscolon", "minuscolon", "colon" or ""

    let dst = DstSgnlAST(
        sgnls: blk.dst_sgnls,
        pthspc: pathString
    )

    // 3. Delay: choose a policy; here, use the first delay expression if present
    let delayNumber: Int

    delayNumber = delayToInt(blk.delay_expr)

    let dly = DlySpcAST(
        variant: blk.variant.rawValue, // "full" or "parallel"
        delay: delayNumber
    )

    // 4. Build statement‑level AST and feed existing pipeline
    let stmtAST = SpcfyStmntAST(
        kind: blk.variant.rawValue,    // or nil if you don’t want it duplicated
        srcSgnls: [src],
        dstSgnls: [dst],
        dly: dly
    )

    let stmnt = StmntAST.spcfyst(stmtAST)
    genStmt(stmnt, ctx: &ctx)
}

public func genStmtFromAST(_ stmt: StmntAST, ctx: inout Context) {
    genStmt(stmt, ctx: &ctx)
}

public struct SyscallExpr {
    var name: String
    var args: [Expr]
}

// Expression evaluator (ID-based)
public func evalExpr(_ id: ExprId, ctx: inout Context) -> Value {
    let expr = ctx.circDef.expr(for: id)

    switch expr {

    case .real(let r):
        return .real(r)

    case .int(let i):
        return .int(i)

    case .node(let name):
        return ctx.read(name)

    case .syscall(let name, let args):
        let argValues = args.map { evalExpr($0, ctx: &ctx) }
        return ctx.syscall(name, args: argValues)

    case .binary(let op, let args):
        precondition(args.count == 2, "Binary op expects 2 args")
        let lhs = evalExpr(args[0], ctx: &ctx)
        let rhs = evalExpr(args[1], ctx: &ctx)
        return applyBinaryOp(op, lhs, rhs)

    case .unary(let op, let arg):
        let v = evalExpr(arg, ctx: &ctx)
        return applyUnaryOp(op, v)

    case .gate(let op, let args):
        let argValues = args.map { evalExpr($0, ctx: &ctx) }
        return ctx.syscall("gate_\(op)", args: argValues)

    case .select(let name, let args):
        precondition(args.count == 2, "select expects 2 args (msb, lsb)")
        let msb = evalExpr(args[0], ctx: &ctx).asInt
        let lsb = evalExpr(args[1], ctx: &ctx).asInt
        return .twoCmplt(ctx.getSelect(name, msb: msb, lsb: lsb))

    case .concat(let args):
        let argValues = args.map { evalExpr($0, ctx: &ctx) }
        return ctx.syscall("concat", args: argValues)

    case .cndtn(let args):
        precondition(args.count == 1, "cndtn expects 1 arg for now, got \(args.count)")
        return evalExpr(args[0], ctx: &ctx)
    }
}

// Statement evaluator (ID-based)
public func evalStmt(_ id: StmtId, ctx: inout Context) {
    let stmt = ctx.circDef.stmt(for: id)

    switch stmt {

    // if-statement: if (cmpr) iftrue else iffalse
    case .ifst(let ifAst):
        let condVal = evalExpr(ifAst.cmpr, ctx: &ctx)

        if condVal.isTrue {   // use your own truth test on Value
            for innerId in ifAst.iftrue.stmnts {   // [StmtId]
                evalStmt(innerId, ctx: &ctx)
            }
        } else if let elseBlk = ifAst.ifelse {
            for innerId in elseBlk.stmnts {
                evalStmt(innerId, ctx: &ctx)
            }
        }

    case .blckst(let b):
        let value = evalExpr(b.rvalue, ctx: &ctx)
        assignToLValue(b.lvalue, rhs: value, tm: ctx.simTime, ctx: &ctx)

    // non-blocking assignment: lvalue <= rvalue [with optional delays]
    case .noblckst(let nb):
        let value = evalExpr(nb.rvalue, ctx: &ctx)
        assignToLValue(nb.lvalue, rhs: value, tm: ctx.simTime, ctx: &ctx)

    // other statement forms, if you have them
    case .whlst(let w):
        while evalExpr(w.cmpr, ctx: &ctx).isTrue {
            for innerId in w.blck.stmnts {      // WhlStmntAST has `blck: BlockAST`
                evalStmt(innerId, ctx: &ctx)
            }
        }

    case .casest(let cs):
        let key = evalExpr(cs.cmpr, ctx: &ctx)
        // naive linear case matching
        for item in cs.items {
            let matchVal = evalExpr(item.cmpr, ctx: &ctx)
            if matchVal == key {
                for innerId in item.body.stmnts {
                    evalStmt(innerId, ctx: &ctx)
                }
                break
            }
        }

    // if you truly don’t have other cases, you can omit this;
    // otherwise, keep a default to stay exhaustive as your enum evolves.
    default:
        break
    }
}

public func applyBinaryOp(_ op: BnOp, _ lhs: Value, _ rhs: Value) -> Value {
    switch op {

    // MARK: - Arithmetic

    case .plus:
        switch (lhs, rhs) {
        case (.real, _), (_, .real):
            return .real(asDouble(lhs) + asDouble(rhs))
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: l.node + r.node,
                    updTm: updTm
                )
            )
        default:
            return .int(asInt(lhs) + asInt(rhs))
        }

    case .minus:
        switch (lhs, rhs) {
        case (.real, _), (_, .real):
            return .real(asDouble(lhs) - asDouble(rhs))
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: l.node - r.node,
                    updTm: updTm
                )
            )
        default:
            return .int(asInt(lhs) - asInt(rhs))
        }

    case .times:
        switch (lhs, rhs) {
        case (.real, _), (_, .real):
            return .real(asDouble(lhs) * asDouble(rhs))
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: l.node * r.node,
                    updTm: updTm
                )
            )
        default:
            return .int(asInt(lhs) * asInt(rhs))
        }

    case .div:
        switch (lhs, rhs) {
        case (.real, _), (_, .real):
            return .real(asDouble(lhs) / asDouble(rhs))
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: l.node / r.node,
                    updTm: updTm
                )
            )
        default:
            return .int(asInt(lhs) / asInt(rhs))
        }

    case .mod:
        switch (lhs, rhs) {
        case (.real, _), (_, .real):
            return .real(
                asDouble(lhs).truncatingRemainder(dividingBy: asDouble(rhs))
            )
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: l.node % r.node,
                    updTm: updTm
                )
            )
        default:
            return .int(asInt(lhs) % asInt(rhs))
        }

    // MARK: - Comparisons

    case .lt:
        if isReal(lhs) || isReal(rhs) {
            return .bool(asDouble(lhs) < asDouble(rhs))
        } else {
            return .bool(asInt(lhs) < asInt(rhs))
        }

    case .lte:
        if isReal(lhs) || isReal(rhs) {
            return .bool(asDouble(lhs) <= asDouble(rhs))
        } else {
            return .bool(asInt(lhs) <= asInt(rhs))
        }

    case .gt:
        if isReal(lhs) || isReal(rhs) {
            return .bool(asDouble(lhs) > asDouble(rhs))
        } else {
            return .bool(asInt(lhs) > asInt(rhs))
        }

    case .gte:
        if isReal(lhs) || isReal(rhs) {
            return .bool(asDouble(lhs) >= asDouble(rhs))
        } else {
            return .bool(asInt(lhs) >= asInt(rhs))
        }

    case .eq:
        if isReal(lhs) || isReal(rhs) {
            return .bool(asDouble(lhs) == asDouble(rhs))
        } else {
            return .bool(asInt(lhs) == asInt(rhs))
        }

    case .neq:
        if isReal(lhs) || isReal(rhs) {
            return .bool(asDouble(lhs) != asDouble(rhs))
        } else {
            return .bool(asInt(lhs) != asInt(rhs))
        }

    // MARK: - Logical

    case .lgcor:
        return .bool(asBool(lhs) || asBool(rhs))

    case .lgcand:
        return .bool(asBool(lhs) && asBool(rhs))

    // MARK: - Bitwise

    case .and:
        switch (lhs, rhs) {
        case (.real, _), (_, .real):
            return .real(asDouble(lhs) + asDouble(rhs))
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: l.node & r.node,
                    updTm: updTm
                )
            )
        default:
            return .int(asInt(lhs) + asInt(rhs))
        }

    case .or:
        switch (lhs, rhs) {
        case (.real, _), (_, .real):
            return .real(asDouble(lhs) + asDouble(rhs))
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: l.node | r.node,
                    updTm: updTm
                )
            )
        default:
            return .int(asInt(lhs) | asInt(rhs))
        }

    case .nand:
        switch (lhs, rhs) {
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: ~(l.node & r.node),
                    updTm: updTm
                )
            )
        default:
            return .int(~(asInt(lhs) & asInt(rhs)))
        }

    case .nor:
        switch (lhs, rhs) {
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: ~(l.node | r.node),
                    updTm: updTm
                )
            )
        default:
            return .int(~(asInt(lhs) | asInt(rhs)))
        }

    case .xor:
        switch (lhs, rhs) {
        case (.real, _), (_, .real):
            return .real(asDouble(lhs) + asDouble(rhs))
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: l.node ^ r.node,
                    updTm: updTm
                )
            )
        default:
            return .int(asInt(lhs) ^ asInt(rhs))
        }

    case .xnor:
        switch (lhs, rhs) {
        case let (.twoCmplt(l), .twoCmplt(r)):
            let updTm = l.updTm >= r.updTm ? l.updTm : r.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: ~(l.node ^ r.node),
                    updTm: updTm
                )
            )
        default:
            return .int(~(asInt(lhs) ^ asInt(rhs)))
        }

    case .sll, .sla:
        let shift = asInt(rhs)
        switch lhs {
        case let .twoCmplt(l):
            let updTm = l.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: l.node << shift,
                    updTm: updTm
                )
            )
        default:
            return .int(asInt(lhs) << shift)
        }

    case .srl, .sra:
        let shift = asInt(rhs)
        switch lhs {
        case let .twoCmplt(l):
            let updTm = l.updTm
            return .twoCmplt(
                SmallNod(
                    name: l.name,
                    node: l.node >> shift,
                    updTm: updTm
                )
            )
        default:
            return .int(asInt(lhs) >> shift)
        }
    }
}

public func isReal(_ v: Value) -> Bool {
    if case .real = v { return true }
    return false
}

extension SmallNod {
    public func withNode(_ newNode: TwoCmplt) -> SmallNod {
        SmallNod(name: self.name, node: newNode, updTm: self.updTm)
    }
}

public func applyUnaryOp(_ op: UOp, _ v: Value) -> Value {
    switch op {

    // MARK: - Arithmetic unary +/-

    case .plus:
        // Unary +: coerce to numeric, leave sign unchanged
        switch v {
        case .real:
            return .real(asDouble(v))
        default:
            return .int(asInt(v))
        }

    case .minus:
        // Unary -: numeric negation
        switch v {
        case .real:
            return .real(-asDouble(v))

        case let .twoCmplt(s):
            return .twoCmplt(s.withNode(-s.node))

        default:
            return .int(-asInt(v))
        }

    // MARK: - Logical / bitwise not

    case .lgcnot:   // logical !
        return .bool(!asBool(v))

    case .not:      // bitwise ~
        switch v {
        case let .twoCmplt(s):
            return .twoCmplt(s.withNode(~s.node))
        default:
            return .int(~asInt(v))
        }

    // MARK: - Reduction operators

    case .and:      // reduction &
        return .bool(reduceBits(asInt(v), op: { $0 && $1 }, identity: true))

    case .nand:     // reduction ~&
        return .bool(!reduceBits(asInt(v), op: { $0 && $1 }, identity: true))

    case .or:       // reduction |
        return .bool(reduceBits(asInt(v), op: { $0 || $1 }, identity: false))

    case .nor:      // reduction ~|
        return .bool(!reduceBits(asInt(v), op: { $0 || $1 }, identity: false))

    case .xor:      // reduction ^
        return .bool(reduceBits(asInt(v), op: { $0 != $1 }, identity: false))

    case .xnor:     // reduction ~^ or ^~
        return .bool(!reduceBits(asInt(v), op: { $0 != $1 }, identity: false))
    }
}

public func reduceBits(_ x: Int,
                       op: (Bool, Bool) -> Bool,
                       identity: Bool) -> Bool {
    var value = UInt(bitPattern: x)
    var acc = identity
    while value != 0 {
        let bit = (value & 1) != 0
        acc = op(acc, bit)
        value >>= 1
    }
    return acc
}

// Helper to pull a Double out of Value
public func asDouble(_ v: Value) -> Double {
    switch v {
    case .real(let d):
        return d
    case .int(let i):
        return Double(i)
    case .uint(let i):
        return Double(i)
    case .bool(let b):
        return b ? 1.0 : 0.0
    case .twoCmplt(let t):
        return Double(t.node.toInt())
    }
}

public func asInt(_ v: Value) -> Int {
    switch v {
    case .int(let i):
        return i
    case .uint(let u):
        return Int(u)
    case .real(let d):
        return Int(d)
    case .bool(let b):
        return b ? 1 : 0
    case .twoCmplt(let t):
        return t.node.toInt()
    }
}

public func asBool(_ v: Value) -> Bool {
    switch v {
    case .bool(let b):
        return b
    case .int(let i):
        return i != 0
    case .uint(let u):
        return u != 0
    case .real(let d):
        return d != 0.0
    case .twoCmplt(let t):
        return t.node.toInt() != 0
    }
}

public func asTwoCmplt(_ v: Value) -> TwoCmplt {
    switch v {
    case .twoCmplt(let t):
        return t.node
    case .int(let i):
        return TwoCmplt(value: i)
    case .uint(let u):
        return TwoCmplt(value: Int(u), signed: false)
    case .real(let d):
        return TwoCmplt(value: Int(d))
    case .bool(let b):
        return TwoCmplt(value: b ? 1 : 0)
    }
}

public func genNonBlockStmtCode(_ ast: NoblckStmntAST,
                                ctx: inout Context)
{
    // 1. Look up the Expr from the ExprId in circDef
    let expr = ctx.circDef.getExpr(ast.rvalue)   // or expr(for: ast.rvalue)

    // 2. Generate code that evaluates the RHS expression and pushes its Value.
    genExpr(expr, ctx: &ctx)

    // 3. Emit a non-blocking-assign opcode carrying the LValueAST and delay info.
    ctx.code.append(
        Instruction(op: .noblckAssign(ast.lvalue, ast.delay))
    )
}

public func genBlockStmtCode(_ ast: BlckStmntAST,
                                ctx: inout Context)
{
    // 1. Look up the Expr from the ExprId in circDef
    let expr = ctx.circDef.getExpr(ast.rvalue)   // or expr(for: ast.rvalue)

    // 2. Generate code that evaluates the RHS expression and pushes its Value.
    genExpr(expr, ctx: &ctx)

    // 3. Emit a non-blocking-assign opcode carrying the LValueAST and delay info.
    ctx.code.append(
        Instruction(op: .blckAssign(ast.lvalue, ast.delay))
    )
}

public func genBlock(_ block: BlockAST, ctx: inout Context) {
    for id in block.stmnts {              // id: StmtId
        let st = ctx.circDef.stmt(for: id)   // StmntAST
        genStmt(st, ctx: &ctx)
    }
}

public func genStmt(_ st: StmntAST, ctx: inout Context) {
    switch st {
    case .ifst(let ifAst):
        genIfStmt(ifAst, ctx: &ctx)
    case .whlst(let whlAst):
        genWhlStmt(whlAst, ctx: &ctx)
    case .dost(let doAst):
        genDoStmt(doAst, ctx: &ctx)
    case .casest(let csAst):
        genCaseStmt(csAst, ctx: &ctx)
    case .assgnst(let assgnBody):
        let assgns = assgnBody.assgns
        genAssignStmt(assgns[0], ctx: &ctx)
    case .concatst(let concatAst):
        genConcatStmt(concatAst, ctx: &ctx)
    case .spcfyst(let spcfyAst):
        genSpecifyStmt(spcfyAst, ctx: &ctx)
    case .blckst(let blkStmtAst):
        genBlockStmtCode(blkStmtAst, ctx: &ctx)
    case .noblckst(let nbAst):
        genNonBlockStmtCode(nbAst, ctx: &ctx)
    case .syscallst:
        break
    case .readmemh:
        ctx.code.append(.init(op: .callSyscall("readmemh", argCount: 0)))
        ctx.code.append(.init(op: .drop))
    case .forst(let forAst):
        genForStmt(forAst, ctx: &ctx)
    }
}

public func genBehavStmt(_ st: StmntAST,
                         ctx: inout Context)
{
    switch st {
    case .noblckst(let nbAst):
        doNoBlcklUpd(nbAst, ctx: &ctx)
    case .blckst(let nbAst):
        doBlcklUpd(nbAst, ctx: &ctx)
    default:
        genStmt(st, ctx: &ctx)
    }
}

public func genIfStmt(_ ifAst: IfStmntAST, ctx: inout Context) {
    // Evaluate condition
    let cmprExpr = ctx.circDef.expr(for: ifAst.cmpr)
    genExpr(cmprExpr, ctx: &ctx)

    // brFalse -> skip then-block (to either else or end)
    let brFalseIndex = ctx.code.count
    ctx.code.append(.init(op: .brFalse(-1))) // this branch will be replaced shortly

    // Then-block
    genBlock(ifAst.iftrue, ctx: &ctx)

    if let elseBlk = ifAst.ifelse {
        // We have an else: add branch to end, then place else right after
        let brEndIndex = ctx.code.count
        ctx.code.append(.init(op: .br(-1)))  // this branch will be replaced shortly

        let elseStart = ctx.code.count
        ctx.code[brFalseIndex].op = .brFalse(elseStart)

        genBlock(elseBlk, ctx: &ctx)

        let endOfIf = ctx.code.count
        ctx.code[brEndIndex].op = .br(endOfIf)
    } else {
        // No else: falling through after then-block is the end
        let endOfIf = ctx.code.count
        ctx.code[brFalseIndex].op = .brFalse(endOfIf)
    }
}

public func genAssgnStmtCode(_ ast: AssgnAST,
                                ctx: inout Context)
{
    // 1. Look up the Expr from the ExprId in circDef
    let expr = ctx.circDef.getExpr(ast.rvalue)   // or expr(for: ast.rvalue)

    // 2. Generate code that evaluates the RHS expression and pushes its Value.
    genExpr(expr, ctx: &ctx)

    // 3. Emit a non-blocking-assign opcode carrying the LValueAST and delay info.
    let delay: Int = Int(ast.delay ?? 0.0)

    ctx.code.append(
        Instruction(op: .assgn(ast.lvalue, delay))
    )
}

public func genExpr(_ expr: Expr, ctx: inout Context) {
    switch expr {

    case .int(let i):
        ctx.code.append(.init(op: .loadConstInt(i)))

    case .real(let d):
        ctx.code.append(.init(op: .loadConstReal(d)))

    case .node(let name):
        if let param = ctx.circDef.params.first(where: { $0.name == name }) {
            switch param.value {
            case .int(let intVal):
                ctx.code.append(.init(op: .loadConstInt(intVal)))
            case .dbl(let d):
                ctx.code.append(.init(op: .loadConstReal(d)))
            case .str:
                ctx.code.append(.init(op: .loadConstInt(0)))
            }
        } else {
            ctx.code.append(.init(op: .loadSignal(name)))
        }

    case .binary(let op, let args):
        precondition(args.count == 2, "binary expects 2 args")
        // args: [ExprId] – resolve each via ctx.circDef before recursing
        let lhs = ctx.circDef.expr(for: args[0])
        let rhs = ctx.circDef.expr(for: args[1])
        genExpr(lhs, ctx: &ctx)
        genExpr(rhs, ctx: &ctx)
        ctx.code.append(.init(op: .binOp(op)))

    case .unary(let op, let arg):
        // arg: ExprId
        let sub = ctx.circDef.expr(for: arg)
        genExpr(sub, ctx: &ctx)
        ctx.code.append(.init(op: .unaryOp(op)))

    case .syscall(let name, let args):
        // args: [ExprId]
        for a in args {
            let sub = ctx.circDef.expr(for: a)
            genExpr(sub, ctx: &ctx)
        }
        ctx.code.append(.init(op: .callSyscall(name, argCount: args.count)))

    case .gate(let op, let args):
        // Treat as syscall "gate_<op>" for now
        for a in args {
            let sub = ctx.circDef.expr(for: a)
            genExpr(sub, ctx: &ctx)
        }
        ctx.code.append(.init(op: .gateOp(op, argCount: args.count)))

    case .select(let name, let args):
        for a in args {
            let sub = ctx.circDef.expr(for: a)
            genExpr(sub, ctx: &ctx)
        }
        ctx.code.append(.init(op: .select(name, argCount: args.count)))

    case .concat(let args):
        // Treat as syscall "concat_<name>"
        for a in args {
            let sub = ctx.circDef.expr(for: a)
            genExpr(sub, ctx: &ctx)
        }
        ctx.code.append(.init(op: .concat(count: args.count)))

    case .cndtn(let args):
        // ternary: args = [condition, true_val, false_val]
        precondition(args.count == 3, "cndtn must have exactly 3 args: condition, true_val, false_val")
        genExpr(ctx.circDef.expr(for: args[0]), ctx: &ctx)
        let brFalseIdx = ctx.code.count
        ctx.code.append(.init(op: .brFalse(-1)))
        genExpr(ctx.circDef.expr(for: args[1]), ctx: &ctx)
        let brEndIdx = ctx.code.count
        ctx.code.append(.init(op: .br(-1)))
        let elseStart = ctx.code.count
        ctx.code[brFalseIdx].op = .brFalse(elseStart)
        genExpr(ctx.circDef.expr(for: args[2]), ctx: &ctx)
        let endLabel = ctx.code.count
        ctx.code[brEndIdx].op = .br(endLabel)
    }
}

public func genWhlStmt(_ whlAst: WhlStmntAST, ctx: inout Context) {
    let condStart = ctx.code.count

    let cmprExpr = ctx.circDef.expr(for: whlAst.cmpr)
    genExpr(cmprExpr, ctx: &ctx)

    let brFalseIndex = ctx.code.count
    ctx.code.append(.init(op: .brFalse(-1)))

    genBlock(whlAst.blck, ctx: &ctx)

    ctx.code.append(.init(op: .br(condStart)))

    let endOfLoop = ctx.code.count
    ctx.code[brFalseIndex].op = .brFalse(endOfLoop)
}

public func genForStmt(_ forAst: ForStmntAST, ctx: inout Context) {
    genStmt(ctx.circDef.getStmt(forAst.pre), ctx: &ctx)

    let condStart = ctx.code.count
    let cmprExpr = ctx.circDef.expr(for: forAst.cmpr)
    genExpr(cmprExpr, ctx: &ctx)

    let brFalseIndex = ctx.code.count
    ctx.code.append(.init(op: .brFalse(-1)))

    genBlock(forAst.body, ctx: &ctx)
    genStmt(ctx.circDef.getStmt(forAst.post), ctx: &ctx)

    ctx.code.append(.init(op: .br(condStart)))
    let endOfLoop = ctx.code.count
    ctx.code[brFalseIndex].op = .brFalse(endOfLoop)
}

public func genDoStmt(_ doAst: DoStmntAST, ctx: inout Context) {
    genBlock(doAst.preblck, ctx: &ctx)

    let loopStart = ctx.code.count

    genBlock(doAst.blck, ctx: &ctx)
    genBlock(doAst.postblck, ctx: &ctx)

    let cmprExpr = ctx.circDef.expr(for: doAst.cmpr)
    genExpr(cmprExpr, ctx: &ctx)

    let brFalseIndex = ctx.code.count
    ctx.code.append(.init(op: .brFalse(-1)))
    ctx.code.append(.init(op: .br(loopStart)))

    let endOfLoop = ctx.code.count
    ctx.code[brFalseIndex].op = .brFalse(endOfLoop)
}

public func genAssignStmt(_ ast: AssgnAST,
                          ctx: inout Context)
{
    // For now, assume a single assignment per statement.
    // If you later support multiple assignments, you can extend this logic.

    let expr = ctx.circDef.getExpr(ast.rvalue)
    genExpr(expr, ctx: &ctx)
    let delay: Int = Int(ast.delay ?? 0.0)
    ctx.code.append(
        Instruction(op: .assgn(ast.lvalue, delay)))
}

func width(of lhs: LValueAST, ctx: Context) -> Int {
    switch lhs {
    case .net(let name):
        guard let v = ctx.vars[name] else {
            fatalError("No value for net \(name)")
        }
        guard case let .twoCmplt(twos) = v else {
            fatalError("width(of:) only implemented for twoCmplt nets")
        }
        return twos.node.nbits

    case .bitSelect:
        return 1

    case .partSelect(_, let msb, let lsb):
        return msb - lsb + 1

    case .indexedPartSelect(_, _, let width):
        return width

    case .concat(let parts):
        return parts.reduce(0) { $0 + width(of: $1, ctx: ctx) }
    }
}

func writeBit(_ cur: Value, at index: Int, with bitVal: Value) -> Value {
    guard case let .twoCmplt(twos) = cur else {
        fatalError("writeBit only implemented for .twoCmplt")
    }

    let bit: Int
    switch bitVal {
    case .int(let i):
        bit = i & 1
    case .bool(let b):
        bit = b ? 1 : 0
    case .twoCmplt(let v):
        bit = v.node.selBit(n: 0) & 1   // assume 1-bit rhs
    default:
        fatalError("writeBit rhs must be int, bool, or 1-bit twoCmplt")
    }

    let mask = ~(1 << index)
    let newVal = (twos.node.value & mask) | (bit << index)
    let updated = TwoCmplt(value: newVal, nbits: twos.node.nbits)
    let newNd = SmallNod(name: twos.name, node: updated, updTm: twos.updTm)
    return .twoCmplt(newNd)
}

func writeSlice(_ cur: Value, msb: Int, lsb: Int, with sliceVal: Value) -> Value {
    guard case let .twoCmplt(twos) = cur else {
        fatalError("writeSlice only implemented for .twoCmplt")
    }
    guard case let .twoCmplt(sv) = sliceVal else {
        fatalError("writeSlice rhs must be .twoCmplt")
    }

    let width = msb - lsb + 1
    precondition(width == sv.node.nbits, "slice width mismatch")

    let mask = ~(((1 << width) - 1) << lsb)
    let cleared = twos.node.value & mask
    let inserted = (sv.node.value & ((1 << width) - 1)) << lsb
    let newVal = cleared | inserted

    let updated = TwoCmplt(value: newVal, nbits: twos.node.nbits)
    let newNd = SmallNod(name: twos.name, node: updated, updTm: twos.updTm)
    return .twoCmplt(newNd)
}

func extractSlice(_ v: Value, msb: Int, lsb: Int) -> TwoCmplt {
    guard case let .twoCmplt(twos) = v else {
        fatalError("extractSlice only implemented for .twoCmplt")
    }
    let slice = twos.node.selBits(n1: msb, n2: lsb)
    return slice
}

public func genConcatStmt(_ ast: ConcatStmntAST, ctx: inout Context) {
    // Purely bytecode-emitting, mirroring genAssgnStmtCode/genAssignStmt:
    // genExpr only appends Instructions to ctx.code at this (codegen) point —
    // it never pushes onto ctx.stack, the *runtime* value stack — so calling
    // ctx.pop() here (as this used to) popped from an empty stack. Emitting a
    // .assgn opcode per part and letting the VM's setLeftNet handle the write
    // at execution time avoids that entirely.
    for single in ast.concats {
        let rhsExpr = ctx.circDef.expr(for: single.rvalue)
        genExpr(rhsExpr, ctx: &ctx)
        let delay: Int = Int(single.delay ?? 0.0)
        ctx.code.append(Instruction(op: .assgn(single.lvalue, delay)))
    }
}

public func genSpecifyStmt(_ ast: SpcfyStmntAST, ctx: inout Context) {
    // For now, treat all source/dest pairs as having the same delay.
    for src in ast.srcSgnls {
        for dst in ast.dstSgnls {
            for srcName in src.sgnls {
                for dstName in dst.sgnls {
                    let arc = TimingArc(
                        src: srcName,
                        edge: src.edge,
                        dst: dstName,
                        pathSpec: dst.pthspc,
                        variant: ast.dly.variant,   // or ast.kind ?? ast.dly.variant
                        delay: ast.dly.delay
                    )
                    ctx.timingArcs.append(arc)
                }
            }
        }
    }
}

public func doBlcklUpd(_ ast: BlckStmntAST,
                            ctx: inout Context)
{
    guard let circuit = ctx.circ else {
        fatalError("doBlcklUpd with no Circuit")
    }
    guard let block = ctx.behavIdx else {
        fatalError("doBlcklUpd outside init/always block")
    }

    let rhsVal = evalExpr(ast.rvalue, ctx: &ctx)
    let when   = ctx.simTime

    let upd = ScheduledUpdate(lvalue: ast.lvalue,
                                value: rhsVal,
                                updTm: when)

    switch block {
    case .alwaysBlock(let idx):
        circuit.alwaysStates[idx].blk.append(upd)
    case .initBlock(let idx):
        circuit.initStates[idx].blk.append(upd)
    case .assgnBlock:
        break
    }
}

public func doNoBlcklUpd(_ ast: NoblckStmntAST,
                            ctx: inout Context)
{
    guard let circuit = ctx.circ else {
        fatalError("doNoBlcklUpd with no Circuit")
    }
    guard let block = ctx.behavIdx else {
        fatalError("doNoBlcklUpd outside init/always block")
    }

    let rhsVal = evalExpr(ast.rvalue, ctx: &ctx)
    let when   = ctx.simTime

    let upd = ScheduledUpdate(lvalue: ast.lvalue,
                                value: rhsVal,
                                updTm: when)

    switch block {
    case .alwaysBlock(let idx):
        circuit.alwaysStates[idx].noblk.append(upd)
    case .initBlock(let idx):
        circuit.initStates[idx].noblk.append(upd)
    case .assgnBlock:
        break
    }
}

public func genCaseStmt(_ cs: CaseStmntAST, ctx: inout Context) {
    // Re-evaluate the switch expression for each case comparison (pure bytecode generation,
    // no runtime stack ops at compile time). Switch expressions are typically simple signal
    // loads so re-evaluation is cheap.
    let switchExpr = ctx.circDef.expr(for: cs.cmpr)

    var endJumps: [Int] = []

    for item in cs.items {
        // Load switch value
        genExpr(switchExpr, ctx: &ctx)
        // Load case constant
        let caseExpr = ctx.circDef.expr(for: item.cmpr)
        genExpr(caseExpr, ctx: &ctx)
        // Compare: eq(switch, case) → bool on stack
        ctx.code.append(.init(op: .callSyscall("eq", argCount: 2)))

        let brFalseIndex = ctx.code.count
        ctx.code.append(.init(op: .brFalse(-1)))

        genBlock(item.body, ctx: &ctx)

        let brEndIndex = ctx.code.count
        ctx.code.append(.init(op: .br(-1)))
        endJumps.append(brEndIndex)

        let skipCase = ctx.code.count
        ctx.code[brFalseIndex].op = .brFalse(skipCase)
    }

    // 3. Optional default body
    if let defBody = cs.defaultBody {
        genBlock(defBody, ctx: &ctx)
    }

    // 4. End-of-case label
    let endOfCase = ctx.code.count

    // Patch all jumps to end of case
    for idx in endJumps {
        ctx.code[idx].op = .br(endOfCase)
    }
}

public enum Opcode {
    // Load/store

    case loadConstReal(Double)
    case loadConstInt(Int)
    case loadSignal(String)
    case storeSignal(String)

    case gateOp(String, argCount: Int)
    case select(String, argCount: Int)
    case concat(count: Int)

    // System calls
    case callSyscall(String, argCount: Int)

    // Binary / unary ops
    case binOp(BnOp)
    case unaryOp(UOp)

    // Control flow
    case br(Int)
    case brFalse(Int)

    // non-blocking assign; RHS will be taken from top of stack at run time
    case noblckAssign(LValueAST, Int?)
    // blocking assign; RHS will be taken from top of stack at run time
    case blckAssign(LValueAST, Int?)

    case assgn(LValueAST, Int?)

    case drop
}

public struct Instruction {
    public var op: Opcode
}

public struct TimingArc {
    public let src: String
    public let edge: String
    public let dst: String
    public let pathSpec: String
    public let variant: String
    public let delay: Int
}

public struct Label: Hashable, CustomStringConvertible {
    public let name: String
    public var description: String { name }

    public init(name: String) {
        self.name = name
    }
}

// MARK: - Instructions

public enum Stmt {
    case label(Label)
    case pushInt(Int)
    case pushBool(Bool)
    case loadVar(String)
    case greaterThanZero          // consumes top Int, pushes Bool
    case printString(String)
    case jump(Label)
    case jumpIfFalse(Label)
    case nop
}

// MARK: - Compiled block

public struct CompiledBlock {
    public var code: [Stmt]
    public var labelToIP: [Label: Int]

    public init(code: [Stmt], labelToIP: [Label: Int]) {
        self.code = code
        self.labelToIP = labelToIP
    }
}

// Build label table (label → instruction index to jump to).
public func buildLabelTable(for code: [Stmt]) -> [Label: Int] {
    var table: [Label: Int] = [:]
    for (ip, stmt) in code.enumerated() {
        if case let .label(label) = stmt {
            // Jump to the instruction *after* the label
            table[label] = ip + 1
        }
    }
    return table
}

private func bitWidth(of t: TwoCmplt) -> Int {
    // Verilog-style: number of bits in the vector
    return t.nbits
}

private func asBits(_ v: Value) -> (bits: Int, width: Int) {
    switch v {
    case .twoCmplt(let t):
        return (t.node.toInt(), bitWidth(of: t.node))
    case .int(let i):
        // Treat plain Int as an unsigned 32-bit vector for reductions
        return (i, 32)
    case .uint(let u):
        // Treat plain Int as an unsigned 32-bit vector for reductions
        return (Int(u), 32)
    case .real(let d):
        return (Int(d), 32)
    case .bool(let b):
        return (b ? 1 : 0, 1)
    }
}

private func reduceAnd(_ x: Int, width: Int) -> Bool {
    // True iff all low `width` bits are 1
    let mask = (width >= Int.bitWidth) ? ~0 : ((1 << width) - 1)
    return (x & mask) == mask
}

private func reduceOr(_ x: Int, width: Int) -> Bool {
    // True iff any low `width` bit is 1
    let mask = (width >= Int.bitWidth) ? ~0 : ((1 << width) - 1)
    return (x & mask) != 0
}

private func reduceXor(_ x: Int, width: Int) -> Bool {
    // XOR of low `width` bits (parity of 1s)
    var v = x
    var count = 0
    for _ in 0..<width {
        if (v & 1) != 0 { count += 1 }
        v >>= 1
    }
    return (count & 1) == 1
}
