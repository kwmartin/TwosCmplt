import TwosCmplt
import Foundation
import Glibc
import Yams

// Debug harness for the TST_CNTRM8 crash:
//   Circuit.swift:618: Evaluation order not determined for 'CNTRM8' evalOrder=1 cmpRefs=7
//
// It runs the same steps as SimRun (Config.yaml -> makeCircDef -> toCircuit
// -> loadSpecs -> simCircuit -> saveNodeChngs) for one circuit, and before
// building it prints two things read straight from Resources/CircuitLib:
//
//   1. The instance tree, with the circuit=sync|async value each instance
//      ends up with (its module's own param, overridden by the instance's).
//      initializeCmpCnts() only breaks dependency edges at sync children.
//   2. For every module with child instances, any feedback loop between
//      those children that passes only through async children: a child's
//      output net feeding, eventually, one of its own inputs. Such a loop
//      leaves refCnts > 0 for its members, so sortCmpRefs() never adds them
//      to evalOrder and the precondition at Circuit.swift:618 fires.
//
// In VS Code: put a breakpoint on the preconditionFailure in
// initializeCmpCnts() (Circuit.swift), or on sortCmpRefs(), and run
// "Debug CNTRM8". Arguments (all optional):
//   CNTRM8 [<CircuitName>=TST_CNTRM8] [--config Config.yaml] [--spec <spec.yml>]
//          [--diag-only]        print the diagnostics, don't build/simulate
//          [--trace NET,NET,...] after the run, print every change of these nets
//                               (paths below the top, e.g. CNTRM8.COUT0 or
//                               CNTRM8.CNTR1.CNT; a top-level port is just CLK).
//                               Default for TST_CNTRM8: the CNT/COUT/LD chain.
//          [--until N]          trace window end, in clock periods (default 40)
//          [--dump-order PATH]  after building, print the evalOrder of the
//                               instance at PATH (e.g. CNTRM8.CNTR0) with each
//                               child's name and circuit=sync|async

func errPrint(_ msg: String) {
    let m = msg + "\n"
    _ = m.withCString { Glibc.write(2, $0, m.utf8.count) }
}

/// Unbuffered stdout: print() output still in the buffer is lost when the
/// precondition aborts the process.
func say(_ msg: String) {
    let m = msg + "\n"
    _ = m.withCString { Glibc.write(1, $0, m.utf8.count) }
}

func loadConfig(at path: String) throws -> ProjectConfig {
    let yaml = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    return try YAMLDecoder().decode(ProjectConfig.self, from: yaml)
}

// MARK: - CircuitLib diagnostics (plain YAML reading, independent of CircDef)

struct LibModule {
    let name: String
    let circuit: String?                  // module's own circuit= param
    let ports: [(name: String, dir: String)]
    let insts: [LibInst]
}

struct LibInst {
    let name: String
    let module: String
    let circuitOverride: String?
    let portNets: [[String]]              // per positional port: net names it touches
}

final class CircuitLib {
    let dir: String
    private var cache: [String: LibModule?] = [:]

    init(dir: String) { self.dir = dir.hasSuffix("/") ? dir : dir + "/" }

    func module(_ name: String) -> LibModule? {
        if let m = cache[name] { return m }
        let m = load(name)
        cache[name] = m
        return m
    }

    private func load(_ name: String) -> LibModule? {
        guard let text = try? String(contentsOfFile: dir + name + ".yml", encoding: .utf8),
              let doc = (try? Yams.load(yaml: text)) as? [String: Any] else { return nil }
        let ports: [(String, String)] = (doc["io_ports"] as? [[String: Any]] ?? []).map {
            (($0["name"] as? String) ?? "?", ($0["direct"] as? String) ?? "?")
        }
        var insts: [LibInst] = []
        for blk in doc["behav_blcks"] as? [[String: Any]] ?? [] {
            guard let kind = blk["kind"] as? String,
                  ["instance", "async", "sync", "subcirc"].contains(kind),
                  let iname = blk["name"] as? String, let mod = blk["module"] as? String else { continue }
            let nets = (blk["ports"] as? [[String: Any]] ?? []).map { netNames($0["node"]) }
            insts.append(LibInst(name: iname, module: mod,
                                 circuitOverride: circuitParam(blk["params"]), portNets: nets))
        }
        return LibModule(name: name, circuit: circuitParam(doc["params"]), ports: ports, insts: insts)
    }

    private func circuitParam(_ params: Any?) -> String? {
        for p in params as? [[String: Any]] ?? [] where (p["name"] as? String) == "circuit" {
            return p["value"] as? String
        }
        return nil
    }

    private func netNames(_ node: Any?) -> [String] {
        guard let n = node as? [String: Any] else { return [] }
        var out: [String] = []
        if let nm = n["name"] as? String { out.append(nm) }
        if (n["kind"] as? String) == "concat" {
            for s in n["sgmnts"] as? [Any] ?? [] { out += netNames(s) }
        }
        return out
    }

    /// circuit= value an instance ends up with: instance param, else module param.
    func effectiveCircuit(_ inst: LibInst) -> String {
        inst.circuitOverride ?? module(inst.module)?.circuit ?? "<missing>"
    }
}

func printTree(_ lib: CircuitLib, _ name: String, indent: String = "", seen: inout Set<String>) {
    guard let m = lib.module(name) else { say("\(indent)\(name)  <not in CircuitLib>"); return }
    for inst in m.insts {
        let child = lib.module(inst.module)
        let own = child?.circuit ?? "<missing>"
        let eff = lib.effectiveCircuit(inst)
        let note = inst.circuitOverride != nil && inst.circuitOverride != own ? "  (module says \(own))" : ""
        let leaf = (child?.insts.isEmpty ?? true) ? "" : "  [\(child!.insts.count) children]"
        say("\(indent)\(inst.name): \(inst.module)  circuit=\(eff)\(note)\(leaf)")
        if !seen.contains(inst.module) {
            seen.insert(inst.module)
            printTree(lib, inst.module, indent: indent + "    ", seen: &seen)
        }
    }
}

/// Feedback loops among a module's async children (sync children break edges,
/// as in initializeCmpCnts). Prints each strongly connected group of size > 1
/// or with a self-loop, with the nets that close it.
func printAsyncLoops(_ lib: CircuitLib, _ name: String) {
    guard let m = lib.module(name), !m.insts.isEmpty else { return }
    let n = m.insts.count
    let supplies: Set<String> = ["VDD", "VSS", "VDDA", "VSSA", "VDD_HI"]
    var drives: [String: [Int]] = [:]       // net -> async children driving it
    var sinks: [String: [Int]] = [:]        // net -> children reading it
    for (i, inst) in m.insts.enumerated() {
        guard let child = lib.module(inst.module) else { continue }
        let isSync = lib.effectiveCircuit(inst) == "sync"
        for (k, nets) in inst.portNets.enumerated() where k < child.ports.count {
            let dir = child.ports[k].dir
            let name = child.ports[k].name.uppercased()
            if supplies.contains(name) { continue }
            for net in nets where !supplies.contains(net.uppercased()) {
                if dir.hasPrefix("Output") && !isSync { drives[net, default: []].append(i) }
                if dir.hasPrefix("Input") { sinks[net, default: []].append(i) }
            }
        }
    }
    var adj = Array(repeating: Set<Int>(), count: n)
    var via: [String: [String]] = [:]       // "i->j" -> nets
    for (net, ds) in drives {
        for d in ds { for s in sinks[net] ?? [] {
            adj[d].insert(s)
            via["\(d)->\(s)", default: []].append(net)
        } }
    }
    // Tarjan SCC
    var index = 0, stack: [Int] = [], onStack = Set<Int>()
    var idx = [Int: Int](), low = [Int: Int](), sccs: [[Int]] = []
    func strong(_ v: Int) {
        idx[v] = index; low[v] = index; index += 1
        stack.append(v); onStack.insert(v)
        for w in adj[v] {
            if idx[w] == nil { strong(w); low[v] = min(low[v]!, low[w]!) }
            else if onStack.contains(w) { low[v] = min(low[v]!, idx[w]!) }
        }
        if low[v] == idx[v] {
            var comp: [Int] = []
            while let w = stack.popLast() { onStack.remove(w); comp.append(w); if w == v { break } }
            sccs.append(comp)
        }
    }
    for v in 0..<n where idx[v] == nil { strong(v) }
    // (TwosCmplt declares its own ||, so plain Bool logic is spelled out here.)
    let loops = sccs.filter { comp -> Bool in
        if comp.count > 1 { return true }
        return adj[comp[0]].contains(comp[0])
    }
    guard !loops.isEmpty else { return }
    say("\n\(name): async feedback loop(s) -- these children can never be ordered:")
    for comp in loops {
        let members = Set(comp)
        say("  { " + comp.map { "\(m.insts[$0].name):\(m.insts[$0].module)(\(lib.effectiveCircuit(m.insts[$0])))" }
                .joined(separator: ", ") + " }")
        for d in comp { for s in adj[d] where members.contains(s) {
            say("      \(m.insts[d].name) -> \(m.insts[s].name)  via \(via["\(d)->\(s)"]!.joined(separator: ","))")
        } }
    }
}

func diagnose(_ lib: CircuitLib, _ top: String) {
    say("=== CircuitLib instance tree of \(top) (\(lib.dir)) ===")
    var seen = Set<String>()
    printTree(lib, top, seen: &seen)
    for mod in [top] + seen.sorted() { printAsyncLoops(lib, mod) }
    say("=== end of diagnostics ===\n")
}

// MARK: - trace

let defaultTrace: [String: [String]] = [
    "TST_CNTRM8": ["CLK", "INIT",
                   "CNTRM8.CP", "CNTRM8.COUT0", "CNTRM8.COUT1", "CNTRM8.LD_N", "CNTRM8.LD",
                   "CNTRM8.CNTR0.CNT", "CNTRM8.CNTR0.COUT", "CNTRM8.CNTR0.L", "CNTRM8.CNTR0.QP",
                   "CNTRM8.CNTR1.CNT", "CNTRM8.CNTR1.COUT", "CNTRM8.CNTR1.L", "CNTRM8.CNTR1.QP"],
]

/// Every change of the traced nets up to `until` periods, from Glbls.nodeChngs
/// (the record saveNodeChngs() dumps), named through the run's own
/// <top>Map.json: circIndxs -> instance name, module node list -> node name.
func printTrace(top: String, nets: [String], per: Int, until: Double) {
    let mapPath = Glbls.configs.directories.dumpDir + top + "Map.json"
    guard let data = FileManager.default.contents(atPath: mapPath),
          let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        errSay("trace: can't read \(mapPath)")
        return
    }
    var instName: [[Int]: String] = [:]
    var instNodes: [[Int]: [String]] = [:]
    for (_, entry) in map {
        guard let e = entry as? [String: Any] else { continue }
        let nodes = (e["nodes"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "?" }
        for inst in e["instances"] as? [[String: Any]] ?? [] {
            guard let ci = inst["circIndxs"] as? [Int] else { continue }
            instName[ci] = inst["name"] as? String ?? "?"
            instNodes[ci] = nodes
        }
    }
    func path(_ ci: [Int]) -> String {       // top ([0]) is "", children "A.B"
        ci.count <= 1 ? "" : (1..<ci.count).map { instName[Array(ci[0...$0])] ?? "?" }.joined(separator: ".")
    }
    var want: [String: Int] = [:]           // net path -> column in `nets`
    for (i, n) in nets.enumerated() { want[n] = i }
    var found = Set<String>()
    say("\n=== Trace of \(nets.count) nets, 0..\(until) PER (PER = \(per)) ===")
    for ch in Glbls.nodeChngs {
        let t = Double(ch.updTm) / Double(per)
        if t > until { continue }
        guard let names = instNodes[ch.circIndxs], ch.nodeIndx < names.count else { continue }
        let p = path(ch.circIndxs)
        let net = p.isEmpty ? names[ch.nodeIndx] : p + "." + names[ch.nodeIndx]
        guard want[net] != nil else { continue }
        found.insert(net)
        let v = ch.nbits > 1 ? "0x" + String(ch.value, radix: 16) : String(ch.value)
        say(String(format: "  t=%8.3f  ", t) + net + " = " + v)
    }
    let missing = nets.filter { !found.contains($0) }
    if !missing.isEmpty { say("  never changed (or not a net): " + missing.joined(separator: ", ")) }
    say("=== end of trace ===")
}

func errSay(_ msg: String) {
    let m = msg + "\n"
    _ = m.withCString { Glibc.write(2, $0, m.utf8.count) }
}

// MARK: - evalOrder dump (internal fields, read through Mirror)

func field(_ obj: Any, _ label: String) -> Any? {
    Mirror(reflecting: obj).children.first { $0.label == label }?.value
}

func dumpOrder(_ top: Circuit, path: String) {
    var circ = top
    for part in path.split(separator: ".") {
        let kids = field(circ, "cCircs") as? [Circuit] ?? []
        guard let next = kids.first(where: { $0.name == part }) else {
            errSay("dump-order: no instance \(part) in \(circ.name)")
            return
        }
        circ = next
    }
    let kids = field(circ, "cCircs") as? [Circuit] ?? []
    let order = field(circ, "evalOrder") as? [Any] ?? []
    say("\n=== evalOrder of \(path) (\(circ.module)), \(order.count) entries ===")
    for (i, ref) in order.enumerated() {
        let kind = field(ref, "kind").map { "\($0)" } ?? "?"
        let idx = field(ref, "index") as? Int ?? -1
        var desc = "\(kind)[\(idx)]"
        // (TwosCmplt declares its own ||, so the test is spelled out.)
        let isChild = ["cCirc", "vCirc"].contains(kind)
        if isChild {
            if kids.indices.contains(idx) {
                let k = kids[idx]
                desc += "  \(k.name): \(k.module)  sync=\(field(k, "sync") as? Bool ?? false)"
            }
        }
        say("  \(i): " + desc)
    }
}

// MARK: - main

@main
struct CNTRM8 {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        func option(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            let v = args[i + 1]
            args.removeSubrange(i...(i + 1))
            return v
        }
        let diagOnly = args.contains("--diag-only")
        args.removeAll { $0 == "--diag-only" }
        let configPath = option("--config") ?? "Config.yaml"
        let specPath = option("--spec")
        let dumpPath = option("--dump-order")
        let traceArg = option("--trace")
        let until = Double(option("--until") ?? "40") ?? 40
        let circuitName = args.first ?? "TST_CNTRM8"

        do {
            Glbls.configs = try loadConfig(at: configPath)
        } catch {
            errPrint("CNTRM8: failed to load config '\(configPath)' (run from the package root): \(error)")
            exit(1)
        }

        diagnose(CircuitLib(dir: Glbls.configs.directories.circLib), circuitName)
        if diagOnly { exit(0) }

        guard var circDef = makeCircDef(circuitName) else {
            errPrint("CNTRM8: failed to build CircDef for '\(circuitName)'")
            exit(1)
        }
        say("Building \(circuitName) (toCircuit -> initializeCmpCnts per level)...")
        let circuit = circDef.toCircuit()       // <- crash site for TST_CNTRM8
        say("Built \(circuitName)")
        if let dumpPath { dumpOrder(circuit, path: dumpPath) }
        saveDefMap()

        let specs = specPath.map { loadSpecs(fromURL: URL(fileURLWithPath: $0)) }
            ?? loadSpecs(circuitName)
        let elapsed = ContinuousClock().measure {
            _ = simCircuit(circuit, per: specs.per, finishTm: specs.finishTm, tmSpcs: specs.tmSpcs)
        }
        say("Elapsed Time: \(elapsed)")
        saveNodeChngs()
        let nets = traceArg.map { $0.split(separator: ",").map(String.init) } ?? defaultTrace[circuitName] ?? []
        if !nets.isEmpty {
            printTrace(top: circuitName, nets: nets, per: specs.per, until: until)
        }
    }
}
