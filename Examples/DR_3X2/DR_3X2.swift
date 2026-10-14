import TwosCmplt
import Foundation
import Glibc
import Yams

// Debug harness for the TST_DR_3X2 crash:
//   Sim.swift:890: Fatal error: Unknown node name chngs
//
// DG_DR_3X2 (like DG_TDR_6X2, DG_TDER_6X2, ...) declares an activity counter
//     integer chngs;
//     initial  chngs = 0;
//     always @(...) if (...) chngs = chngs + 1;
// toNodesArryVal() (CircDef.swift) makes nodes only of Reg/Wire decls, so an
// Integer lives in Context.vars -- assignToLValue() (Sim.swift ~1055/1273)
// stores it there when the name isn't in nodeLU. But Circuit.eval() builds a
// fresh Context on every call (Circuit.swift ~1206), so the initial block's
// `chngs = 0` is gone by the time an always block runs `chngs = chngs + 1`,
// and readNode("chngs") (Sim.swift ~883) finds neither a node nor a var.
//
// This program runs the same steps as SimRun (Config.yaml -> makeCircDef ->
// toCircuit -> loadSpecs -> simCircuit -> saveNodeChngs) for one circuit and
// first prints, from Resources/CircuitLib, every integer variable in the
// hierarchy with the blocks that read or write it -- what a per-instance
// integer store has to cover.
//
// Breakpoints worth setting in VS Code ("Debug DR_3X2"):
//   Sim.swift   readNode(_:)  -- the fatalError("Unknown node name ...")
//   Sim.swift   assignToLValue / the always-block twin, `ctx.vars[name] = .int(val)`
//   Circuit.swift eval(async:tm:)  -- `ctx = Context(circDef: ...)`, where the
//               previous evaluation's vars are dropped
//
// Arguments (all optional):
//   DR_3X2 [<CircuitName>=TST_DR_3X2] [--config Config.yaml] [--spec <spec.yml>]
//          [--diag-only]        print the diagnostics, don't build/simulate

/// Unbuffered stdout: print() output still in the buffer is lost when the
/// fatalError aborts the process.
func say(_ msg: String) {
    let m = msg + "\n"
    _ = m.withCString { Glibc.write(1, $0, m.utf8.count) }
}

func errSay(_ msg: String) {
    let m = msg + "\n"
    _ = m.withCString { Glibc.write(2, $0, m.utf8.count) }
}

func loadConfig(at path: String) throws -> ProjectConfig {
    let yaml = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    return try YAMLDecoder().decode(ProjectConfig.self, from: yaml)
}

// MARK: - CircuitLib diagnostics (plain YAML reading, independent of CircDef)

func loadModule(_ dir: String, _ name: String) -> [String: Any]? {
    guard let text = try? String(contentsOfFile: dir + name + ".yml", encoding: .utf8) else { return nil }
    return (try? Yams.load(yaml: text)) as? [String: Any]
}

/// Integer declarations of a module: decls is a list of groups of decl dicts.
func integerDecls(_ doc: [String: Any]) -> [String] {
    var names: [String] = []
    for group in doc["decls"] as? [Any] ?? [] {
        for d in group as? [[String: Any]] ?? [] where (d["kind"] as? String) == "Integer" {
            if let nm = d["name"] as? String { names.append(nm) }
        }
    }
    return names
}

/// True if `name` appears anywhere in a parsed block (an ident, lvalue, ...).
func mentions(_ obj: Any, _ name: String) -> Bool {
    if let d = obj as? [String: Any] {
        if (d["name"] as? String) == name { return true }
        return d.values.contains { mentions($0, name) }
    }
    if let a = obj as? [Any] { return a.contains { mentions($0, name) } }
    return false
}

func diagnose(circLib: String, top: String) {
    let dir = circLib.hasSuffix("/") ? circLib : circLib + "/"
    say("=== Integer variables in the \(top) hierarchy (\(dir)) ===")
    var seen = Set<String>()
    var found = 0

    func walk(_ module: String, _ path: String) {
        guard let doc = loadModule(dir, module) else {
            say("  \(path): \(module) <not in CircuitLib>")
            return
        }
        let blocks = doc["behav_blcks"] as? [Any] ?? []
        if !seen.contains(module) {
            seen.insert(module)
            for v in integerDecls(doc) {
                found += 1
                let users = blocks.enumerated().compactMap { (i, b) -> String? in
                    guard mentions(b, v) else { return nil }
                    let kind = (b as? [String: Any])?["kind"] as? String ?? "?"
                    return "\(kind)#\(i)"
                }
                say("  \(module) (e.g. \(path)): integer \(v)  used in: \(users.joined(separator: ", "))")
            }
        }
        for b in blocks {
            guard let blk = b as? [String: Any],
                  let kind = blk["kind"] as? String,
                  ["instance", "async", "sync", "subcirc"].contains(kind),
                  let child = blk["module"] as? String, let inst = blk["name"] as? String else { continue }
            walk(child, path + "." + inst)
        }
    }
    walk(top, top)
    say(found == 0 ? "  (none)" : "  \(found) integer variable(s); none of them is a node, so each lives only in Context.vars")
    say("=== end of diagnostics ===\n")
}

/// After the run: every instance's persisted integer variables (Circuit.vars),
/// found by walking the hierarchy. cCircs is internal to TwosCmplt, so this
/// debug harness reads it through Mirror.
func reportVars(_ circ: Circuit, path: String) {
    if !circ.vars.isEmpty {
        let vals = circ.vars.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.asInt)" }
        say("  \(path): \(vals.joined(separator: ", "))")
    }
    for child in Mirror(reflecting: circ).children where child.label == "cCircs" {
        for c in child.value as? [Circuit] ?? [] {
            let name = Mirror(reflecting: c).children.first { $0.label == "name" }?.value as? String ?? "?"
            reportVars(c, path: path + "." + name)
        }
    }
}

// MARK: - main

@main
struct DR_3X2 {
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
        let circuitName = args.first ?? "TST_DR_3X2"

        do {
            Glbls.configs = try loadConfig(at: configPath)
        } catch {
            errSay("DR_3X2: failed to load config '\(configPath)' (run from the package root): \(error)")
            exit(1)
        }

        diagnose(circLib: Glbls.configs.directories.circLib, top: circuitName)
        if diagOnly { exit(0) }

        guard var circDef = makeCircDef(circuitName) else {
            errSay("DR_3X2: failed to build CircDef for '\(circuitName)'")
            exit(1)
        }
        say("Building \(circuitName)...")
        let circuit = circDef.toCircuit()
        say("Built \(circuitName); simulating (crash site: readNode of an integer var)...")
        saveDefMap()

        let specs = specPath.map { loadSpecs(fromURL: URL(fileURLWithPath: $0)) }
            ?? loadSpecs(circuitName)
        let elapsed = ContinuousClock().measure {
            _ = simCircuit(circuit, per: specs.per, finishTm: specs.finishTm, tmSpcs: specs.tmSpcs)
        }
        say("Elapsed Time: \(elapsed)")
        say("Integer variables at the end of the run:")
        reportVars(circuit, path: circuitName)
        saveNodeChngs()
    }
}
