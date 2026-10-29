import Foundation

/// Port-level dependencies of a module, and the synchronous-design check
/// (plan ~/.claude/plans/happy-mapping-ladybug.md, Part A).
///
/// For each output port: the input ports that reach it through
/// combinational logic only -- gates, continuous assigns, always blocks
/// without an edge, and child instances' own such paths. A register cuts a
/// path: an edge-triggered always block, a `Reg` (sCirc), a `reg`/`jkq`/
/// `diclq` gate. An asynchronous set/reset (an edge signal that the block
/// also reads, e.g. `R` in `always @(negedge CP or posedge R)`) is a launch
/// control, like the clock, and not a combinational arc (STA treats reset
/// pins with recovery/removal checks, not as data paths).
///
/// A latch (an always block without an edge that writes a node only under a
/// condition) passes D to Q only while it is transparent. So every arc
/// carries a mask: the assignments (0/1) of the module's phase pins under
/// which it exists. A loop is real only if it exists under one assignment;
/// a loop through two latches that are never transparent together
/// (opposite phases) is broken (designer, 2026-10-29).
final class PortDeps {
    typealias Mask = UInt16
    /// Phase pins per module; 2^4 assignments fit a Mask.
    static let maxPhase = 4
    static func full(_ n: Int) -> Mask { n >= 4 ? 0xFFFF : Mask((1 << (1 << n)) - 1) }

    let module: String
    /// Input ports that the arc masks are expressed over (clock-like pins).
    var phase: [String] = []
    /// output port -> input port -> mask over `phase` assignments.
    var arcs: [String: [String: Mask]] = [:]
    var asyncCtrls: Set<String> = []
    var clocks: Set<String> = []
    var registered = false
    var isLatch = false
    /// Real combinational loops: each a list of "node (writer)".
    var loops: [[String]] = []
    /// Assign blocks (indices into assgnBlkWrites) that read registers only
    /// (QP = STATE, QN = ~STATE, a latch's QP = STR): a register's output
    /// stage, run in the start-up launch (Part C).
    var launchAssigns: Set<Int> = []

    /// Set by simCircuit during the start-up launch pass.
    nonisolated(unsafe) static var launching = false

    init(module: String) { self.module = module }

    /// True when some input reaches `port` combinationally, so the port
    /// gives its child an ordering edge in the parent (Part B).
    func isCombinational(_ port: String) -> Bool {
        guard let ins = arcs[port] else { return false }
        return ins.values.contains { $0 != 0 }
    }

    nonisolated(unsafe) static var cache: [String: PortDeps] = [:]
    nonisolated(unsafe) static var warned: Set<String> = []
    static let dumpPath: String? = ProcessInfo.processInfo.environment["SIMRUN_PORTDEPS_DUMP"]

    static func of(_ circ: Circuit) -> PortDeps {
        let key = "\(circ.module)#\(circ.nodes.count)#" + circ.iPrts.map { $0.port }.joined(separator: ",")
        if let d = cache[key] { return d }
        var b = PortDepsBuilder(circ)
        let d = b.build()
        cache[key] = d
        d.report(circ)
        return d
    }

    /// Problems only, once per module (D2, D3).
    private func report(_ circ: Circuit) {
        guard !PortDeps.warned.contains(module) else { return }
        PortDeps.warned.insert(module)
        for lp in loops {
            print("WARNING: \(module): combinational loop: " + lp.joined(separator: " -> "))
        }
        let leaf = circ.cCircs.isEmpty && circ.kind == "verilog" && circ.parent != nil
        if leaf && circ.sync && !registered && !isLatch {
            print("WARNING: \(module): instantiated with circuit = \"sync\" but has no register or latch")
        }
        if leaf && !circ.sync && registered {
            print("WARNING: \(module): instantiated with circuit = \"async\" but has an edge-triggered register")
        }
        if let path = PortDeps.dumpPath { appendDump(path, sync: circ.sync) }
    }

    private func appendDump(_ path: String, sync: Bool) {
        func q(_ s: String) -> String { "'\(s)'" }
        var lines = ["- module: \(q(module))",
                     "  phase: [\(phase.map(q).joined(separator: ", "))]",
                     "  sync: \(sync)",
                     "  registered: \(registered)",
                     "  latch: \(isLatch)",
                     "  clocks: [\(clocks.sorted().map(q).joined(separator: ", "))]",
                     "  async: [\(asyncCtrls.sorted().map(q).joined(separator: ", "))]",
                     "  outputs:"]
        for o in arcs.keys.sorted() {
            let ins = arcs[o]!.filter { $0.value != 0 }.keys.sorted()
            let masks = ins.map { "\(q($0)): \(arcs[o]![$0]!)" }
            lines.append("    \(q(o)): {\(masks.joined(separator: ", "))}")
        }
        lines.append("  launch_assigns: \(launchAssigns.sorted())")
        lines.append("  loops: \(loops.count)")
        let text = lines.joined(separator: "\n") + "\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(text.data(using: .utf8)!); h.closeFile()
        } else {
            _ = FileManager.default.createFile(atPath: path, contents: text.data(using: .utf8))
        }
    }
}

/// Builds a module's PortDeps from the circuit SimRun holds: node indices,
/// gates, assigns' read/write sets, always blocks (from the CircDef), and the
/// children's own PortDeps mapped through their port definitions.
private struct PortDepsBuilder {
    let circ: Circuit
    let deps: PortDeps
    var edges: [Int: [Int: PortDeps.Mask]] = [:]
    /// Root nodes of the phase pins in this module (at most maxPhase).
    var roots: [Int] = []
    let inPortNodes: [Int: String]

    init(_ circ: Circuit) {
        self.circ = circ
        self.deps = PortDeps(module: circ.module)
        var m: [Int: String] = [:]
        for p in circ.iPrts where !PortDepsBuilder.isSupply(p.port) && p.intlIndx < circ.nodes.count {
            m[p.intlIndx] = p.port
        }
        self.inPortNodes = m
    }

    static func isSupply(_ name: String) -> Bool {
        ["VDD", "VSS", "vdd", "vss", "VDDA", "VSSA", "vdda", "vssa", "VDD_HI", "vdd_hi"].contains(name)
    }

    func node(_ name: String) -> Int? {
        guard let i = circ.nodeLU[name], i < circ.nodes.count else { return nil }
        return i
    }

    mutating func add(_ s: Int, _ d: Int, _ m: PortDeps.Mask) {
        guard m != 0 else { return }
        edges[s, default: [:]][d, default: 0] |= m
    }

    var nR: Int { roots.count }
    var fullR: PortDeps.Mask { PortDeps.full(nR) }

    mutating func rootIndex(_ n: Int) -> Int? {
        if let i = roots.firstIndex(of: n) { return i }
        guard roots.count < PortDeps.maxPhase else { return nil }
        roots.append(n)
        return roots.count - 1
    }

    // MARK: tracing a clock pin back through buffers and inverters

    /// (root node, inverted) for node `n`: follows single-input buffers and
    /// inverters (gate primitives, or a child that is one such gate) back to
    /// an input port or to the first other driver.
    func trace(_ start: Int) -> (Int, Bool) {
        var n = start, flip = false
        for _ in 0..<32 {
            if inPortNodes[n] != nil { return (n, flip) }
            let d = circ.nodes[n].nodeDrvr
            switch d.kind {
            case .aCirc where d.index < circ.aCircs.count:
                let g = circ.aCircs[d.index]
                guard g.inps.count == 1, g.kind == .buf || g.kind == .inv else { return (n, flip) }
                if g.kind == .inv { flip.toggle() }
                n = g.inps[0]
            case .vCirc, .cCirc:
                guard d.index < circ.cCircs.count else { return (n, flip) }
                let ch = circ.cCircs[d.index]
                guard ch.cCircs.isEmpty, ch.aCircs.count == 1, ch.assgnBlkWrites.isEmpty,
                      ch.aCircs[0].inps.count == 1,
                      ch.aCircs[0].kind == .buf || ch.aCircs[0].kind == .inv,
                      let ip = ch.iPrts.first(where: { !PortDepsBuilder.isSupply($0.port) }) else { return (n, flip) }
                if ch.aCircs[0].kind == .inv { flip.toggle() }
                n = ip.extlIndx
            default:
                return (n, flip)
            }
            if n >= circ.nodes.count { return (start, false) }
        }
        return (n, flip)
    }

    // MARK: always blocks

    enum Cond { case expr(ExprId, Bool); case unknown }
    struct Write { var lv: [String]; var rv: Set<String>; var condReads: Set<String>; var conds: [Cond] }

    func walk(_ blk: BlockAST, _ cd: CircDef, _ conds: [Cond], _ condReads: Set<String>, _ out: inout [Write]) {
        for sid in blk.stmnts { walkStmt(sid, cd, conds, condReads, &out) }
    }

    func walkStmt(_ sid: StmtId, _ cd: CircDef, _ conds: [Cond], _ condReads: Set<String>, _ out: inout [Write]) {
        switch cd.stmt(for: sid) {
        case .ifst(let s):
            let r = condReads.union(referencedNodeNames(s.cmpr, in: cd))
            walk(s.iftrue, cd, conds + [.expr(s.cmpr, true)], r, &out)
            if let e = s.ifelse { walk(e, cd, conds + [.expr(s.cmpr, false)], r, &out) }
        case .blckst(let b):
            var rv = referencedNodeNames(b.rvalue, in: cd)
            if let de = b.delayExpr { rv.formUnion(referencedNodeNames(de, in: cd)) }
            out.append(Write(lv: lvalueBaseNames(b.lvalue), rv: rv, condReads: condReads, conds: conds))
        case .noblckst(let b):
            var rv = referencedNodeNames(b.rvalue, in: cd)
            if let de = b.delayExpr { rv.formUnion(referencedNodeNames(de, in: cd)) }
            out.append(Write(lv: lvalueBaseNames(b.lvalue), rv: rv, condReads: condReads, conds: conds))
        case .assgnst(let body):
            for a in body.assgns {
                out.append(Write(lv: lvalueBaseNames(a.lvalue), rv: referencedNodeNames(a.rvalue, in: cd),
                                 condReads: condReads, conds: conds))
            }
        case .concatst(let c):
            for a in c.concats {
                out.append(Write(lv: lvalueBaseNames(a.lvalue), rv: referencedNodeNames(a.rvalue, in: cd),
                                 condReads: condReads, conds: conds))
            }
        case .casest(let c):
            let r = condReads.union(referencedNodeNames(c.cmpr, in: cd))
            for it in c.items { walk(it.body, cd, conds + [.unknown], r, &out) }
            if let d = c.defaultBody { walk(d, cd, conds + [.unknown], r, &out) }
        case .whlst(let w):
            walk(w.blck, cd, conds + [.unknown], condReads.union(referencedNodeNames(w.cmpr, in: cd)), &out)
        case .dost(let d):
            let r = condReads.union(referencedNodeNames(d.cmpr, in: cd))
            walk(d.preblck, cd, conds, r, &out)
            walk(d.blck, cd, conds + [.unknown], r, &out)
            walk(d.postblck, cd, conds + [.unknown], r, &out)
        case .forst(let f):
            let r = condReads.union(referencedNodeNames(f.cmpr, in: cd))
            walkStmt(f.pre, cd, conds, r, &out)
            walk(f.body, cd, conds + [.unknown], r, &out)
            walkStmt(f.post, cd, conds + [.unknown], r, &out)
        case .spcfyst, .syscallst, .readmemh:
            break
        }
    }

    /// Three-valued value of a condition (0, 1, or 2 = unknown) under
    /// assignment `a` of the pins in `pinBit`.
    func eval3(_ id: ExprId, _ cd: CircDef, _ pinBit: [String: Int], _ a: Int) -> Int {
        switch cd.expr(for: id) {
        case .int(let v): return v != 0 ? 1 : 0
        case .node(let name):
            guard let b = pinBit[name] else { return 2 }
            return (a >> b) & 1
        case .unary(let op, let arg):
            guard op == .not || op == .lgcnot else { return 2 }
            let v = eval3(arg, cd, pinBit, a)
            return v == 2 ? 2 : 1 - v
        case .gate(let name, let args):
            // A condition written as a gate expression (DG_LTCH_3X1: CP & ~CN).
            guard let op = BnOp(rawValue: name) ?? BnOp(rawValue: "B" + name) else { return 2 }
            return eval3Binary(op, args, cd, pinBit, a)
        case .binary(let op, let args):
            return eval3Binary(op, args, cd, pinBit, a)
        default:
            return 2
        }
    }

    func eval3Binary(_ op: BnOp, _ args: [ExprId], _ cd: CircDef, _ pinBit: [String: Int], _ a: Int) -> Int {
        guard args.count == 2 else { return 2 }
        let x = eval3(args[0], cd, pinBit, a), y = eval3(args[1], cd, pinBit, a)
        func and3(_ p: Int, _ q: Int) -> Int { (p == 0 || q == 0) ? 0 : ((p == 1 && q == 1) ? 1 : 2) }
        func or3(_ p: Int, _ q: Int) -> Int { (p == 1 || q == 1) ? 1 : ((p == 0 && q == 0) ? 0 : 2) }
        func not3(_ p: Int) -> Int { p == 2 ? 2 : 1 - p }
        func xor3(_ p: Int, _ q: Int) -> Int { (p == 2 || q == 2) ? 2 : (p ^ q) }
        switch op {
        case .and, .lgcand: return and3(x, y)
        case .or, .lgcor:   return or3(x, y)
        case .nand:         return not3(and3(x, y))
        case .nor:          return not3(or3(x, y))
        case .xor, .neq:    return xor3(x, y)
        case .xnor, .eq:    return not3(xor3(x, y))
        default:            return 2
        }
    }

    // MARK: build

    mutating func build() -> PortDeps {
        let cd = circ.instanceCircDef ?? Glbls.circDef(for: circ.module)

        // Always blocks: writes with their conditions.
        var levelBlocks: [(writes: [Write], sens: [String])] = []
        var regNodes: Set<Int> = []
        if let cd = cd {
            for blk in cd.behav {
                guard case .alwaysblck(let ab) = blk else { continue }
                var ws: [Write] = []
                walk(ab.body, cd, [], [], &ws)
                let sens = ab.snstvs ?? []
                let edgeNames: [String] = sens.compactMap {
                    switch $0 { case .edgePos(let n), .edgeNeg(let n): return n; default: return nil }
                }
                if !edgeNames.isEmpty {
                    deps.registered = true
                    for w in ws { for n in w.lv { if let i = node(n) { regNodes.insert(i) } } }
                    var read: Set<String> = []
                    for w in ws { read.formUnion(w.rv); read.formUnion(w.condReads) }
                    for n in edgeNames {
                        if read.contains(n) { deps.asyncCtrls.insert(n) } else { deps.clocks.insert(n) }
                    }
                    // A level signal beside an edge (DG_TDR_6X2: @(CP or posedge R),
                    // tested as `if (!CP)`) is the clock of a register written
                    // with a level-sensitive clock.
                    for e in sens {
                        if case .all(let n) = e { deps.clocks.insert(n) }
                        if case .level(let n) = e { deps.clocks.insert(n) }
                    }
                } else {
                    let names: [String] = sens.compactMap {
                        switch $0 { case .all(let n), .level(let n): return n; default: return nil }
                    }
                    levelBlocks.append((ws, names))
                }
            }
        }

        // Phase pins: a latch's own enable pins, then the children's phase pins.
        var latchPins: Set<String> = []
        for lb in levelBlocks {
            for w in lb.writes where !w.rv.isEmpty && !w.conds.isEmpty {
                for c in w.conds { if case .expr(let e, _) = c, let cd = cd {
                    for n in referencedNodeNames(e, in: cd) where node(n).flatMap({ inPortNodes[$0] }) != nil {
                        latchPins.insert(n)
                    }
                } }
            }
        }
        for p in latchPins.sorted() { if let n = node(p) { _ = rootIndex(n) } }
        var childPinRoots: [[String: (Int, Bool)]] = []
        for ch in circ.cCircs {
            let cdp = PortDeps.of(ch)
            var m: [String: (Int, Bool)] = [:]
            for p in cdp.phase {
                guard let ip = ch.iPrts.first(where: { $0.port == p }), ip.extlIndx < circ.nodes.count else { continue }
                let (r, flip) = trace(ip.extlIndx)
                if let ri = rootIndex(r) { m[p] = (ri, flip) }
            }
            childPinRoots.append(m)
        }
        let nR = self.nR, fullR = self.fullR

        // Gates.
        for g in circ.aCircs where !(g.kind == .reg || g.kind == .jkq || g.kind == .diclq) {
            for i in g.inps where i < circ.nodes.count {
                for o in g.outs where o < circ.nodes.count { add(i, o, fullR) }
            }
        }
        // Continuous assigns.
        for k in circ.assgnBlkWrites.indices {
            for i in circ.assgnBlkReads[k] where i < circ.nodes.count {
                for o in circ.assgnBlkWrites[k] where o < circ.nodes.count { add(i, o, fullR) }
            }
        }
        // Level-sensitive always blocks (combinational logic and latches).
        if let cd = cd {
            var pinBit: [String: Int] = [:]
            for p in latchPins { if let n = node(p), let i = roots.firstIndex(of: n) { pinBit[p] = i } }
            for lb in levelBlocks {
                for w in lb.writes {
                    var mask: PortDeps.Mask = 0
                    for a in 0..<(1 << nR) {
                        let ok = w.conds.allSatisfy { c in
                            switch c {
                            case .unknown: return true
                            case .expr(let e, let pol):
                                let v = eval3(e, cd, pinBit, a)
                                return v == 2 || (v == 1) == pol
                            }
                        }
                        if ok { mask |= PortDeps.Mask(1) << PortDeps.Mask(a) }
                    }
                    if !w.rv.isEmpty && mask != fullR {
                        deps.isLatch = true
                        for n in w.lv { if let i = node(n) { regNodes.insert(i) } }
                    }
                    let dsts = w.lv.compactMap { node($0) }
                    for s in w.rv { if let si = node(s) { for d in dsts { add(si, d, mask) } } }
                    // A condition's signals change the output whatever the phase
                    // (a latch opening). The sensitivity list adds nothing of its
                    // own: a signal acts only through what the block does with it.
                    for s in w.condReads { if let si = node(s) { for d in dsts { add(si, d, fullR) } } }
                }
            }
        }
        // A register's output stage: assigns that read registers only, or
        // other such assigns (QN = ~QP).
        var stateNodes = regNodes, grew = true
        while grew {
            grew = false
            for k in circ.assgnBlkWrites.indices where !deps.launchAssigns.contains(k) {
                let reads = circ.assgnBlkReads[k].filter { $0 < circ.nodes.count }
                if !reads.isEmpty && reads.allSatisfy({ stateNodes.contains($0) }) {
                    deps.launchAssigns.insert(k)
                    stateNodes.formUnion(circ.assgnBlkWrites[k])
                    grew = true
                }
            }
        }
        // Children, through their own PortDeps.
        for (ci, ch) in circ.cCircs.enumerated() {
            let cdp = PortDeps.of(ch)
            let pinMap = childPinRoots[ci]
            for op in ch.oPrts where op.extlIndx < circ.nodes.count {
                guard let ins = cdp.arcs[op.port] else { continue }
                for (ipName, m) in ins where m != 0 {
                    guard let ip = ch.iPrts.first(where: { $0.port == ipName }), ip.extlIndx < circ.nodes.count else { continue }
                    add(ip.extlIndx, op.extlIndx, translate(m, cdp.phase, pinMap, nR))
                }
            }
        }

        // Reachability and loops, one phase assignment at a time.
        for a in 0..<(1 << nR) {
            let bit = PortDeps.Mask(1) << PortDeps.Mask(a)
            var adj: [Int: [Int]] = [:]
            for (s, ds) in edges { for (d, m) in ds where m & bit != 0 { adj[s, default: []].append(d) } }
            for (inode, iname) in inPortNodes {
                var seen: Set<Int> = [], stack = [inode]
                while let x = stack.popLast() {
                    for y in adj[x] ?? [] where !seen.contains(y) { seen.insert(y); stack.append(y) }
                }
                for op in circ.oPrts where seen.contains(op.intlIndx) {
                    deps.arcs[op.port, default: [:]][iname, default: 0] |= bit
                }
            }
            for comp in sccs(adj) {
                let desc = comp.map { n -> String in "\(circ.nodes[n].name) (\(writer(n)))" }
                if !deps.loops.contains(desc) { deps.loops.append(desc) }
            }
        }
        for op in circ.oPrts where deps.arcs[op.port] == nil { deps.arcs[op.port] = [:] }

        // Export: masks over the phase roots that are this module's input ports.
        let exported = roots.enumerated().filter { inPortNodes[$0.element] != nil }
        deps.phase = exported.map { inPortNodes[$0.element]! }
        for (o, ins) in deps.arcs {
            for (i, m) in ins { deps.arcs[o]![i] = project(m, exported.map { $0.offset }, nR) }
        }
        return deps
    }

    /// A child's arc mask (over its `phase` pins) as a mask over this
    /// module's roots: assignment a is in it if some child assignment that
    /// agrees with a on the traced pins is in `m`.
    func translate(_ m: PortDeps.Mask, _ cphase: [String], _ pinMap: [String: (Int, Bool)], _ nR: Int) -> PortDeps.Mask {
        if cphase.isEmpty { return m & 1 != 0 ? PortDeps.full(nR) : 0 }
        var out: PortDeps.Mask = 0
        for a in 0..<(1 << nR) {
            for b in 0..<(1 << cphase.count) where m & (PortDeps.Mask(1) << PortDeps.Mask(b)) != 0 {
                let agrees = cphase.enumerated().allSatisfy { (j, p) in
                    guard let (ri, flip) = pinMap[p] else { return true }
                    return ((b >> j) & 1) == (((a >> ri) & 1) ^ (flip ? 1 : 0))
                }
                if agrees { out |= PortDeps.Mask(1) << PortDeps.Mask(a); break }
            }
        }
        return out
    }

    /// Mask over all roots -> mask over the roots at positions `keep`.
    func project(_ m: PortDeps.Mask, _ keep: [Int], _ nR: Int) -> PortDeps.Mask {
        var out: PortDeps.Mask = 0
        for a in 0..<(1 << nR) where m & (PortDeps.Mask(1) << PortDeps.Mask(a)) != 0 {
            var e = 0
            for (j, pos) in keep.enumerated() { e |= ((a >> pos) & 1) << j }
            out |= PortDeps.Mask(1) << PortDeps.Mask(e)
        }
        return out
    }

    func writer(_ n: Int) -> String {
        let d = circ.nodes[n].nodeDrvr
        switch d.kind {
        case .aCirc where d.index < circ.aCircs.count: return circ.aCircs[d.index].name
        case .vCirc where d.index < circ.cCircs.count: return circ.cCircs[d.index].name
        case .cCirc where d.index < circ.cCircs.count: return circ.cCircs[d.index].name
        case .assgnBlk: return "assign[\(d.index)]"
        case .iPrt: return "input"
        default: return "?"
        }
    }

    /// Strongly connected components with a cycle (Tarjan).
    func sccs(_ adj: [Int: [Int]]) -> [[Int]] {
        var index = 0, idx: [Int: Int] = [:], low: [Int: Int] = [:]
        var stack: [Int] = [], onStack: Set<Int> = [], out: [[Int]] = []
        func strong(_ v: Int) {
            idx[v] = index; low[v] = index; index += 1
            stack.append(v); onStack.insert(v)
            for w in adj[v] ?? [] {
                if idx[w] == nil { strong(w); low[v] = min(low[v]!, low[w]!) }
                else if onStack.contains(w) { low[v] = min(low[v]!, idx[w]!) }
            }
            if low[v] == idx[v] {
                var comp: [Int] = []
                while let w = stack.popLast() { onStack.remove(w); comp.append(w); if w == v { break } }
                if comp.count > 1 || (adj[v] ?? []).contains(v) { out.append(comp.sorted()) }
            }
        }
        for v in adj.keys.sorted() where idx[v] == nil { strong(v) }
        return out
    }
}
