import Foundation

/// Opt-in log of out-of-order node writes: a write stamped earlier than the
/// node's latest change (Circuit.setNode, Circuit.mergeBits). Set
/// SWIFT_OOO_LOG=<file> to turn it on; off, each hook is one Bool test and
/// the simulation is unchanged. One YAML line per write: where it came from
/// (the cells being evaluated, the sweep pass) and the later-stamped change
/// it collides with. Investigation aid, branch ooo-trace (SIM_TIMING.md).
public enum OooLog {
    static let handle: FileHandle? = {
        guard var path = ProcessInfo.processInfo.environment["SWIFT_OOO_LOG"],
              !path.isEmpty else { return nil }
        // A directory: one file per run (sim_compare runs many testbenches).
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            path += "/ooo_\(ProcessInfo.processInfo.processIdentifier).yml"
        }
        _ = FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()
    @inline(__always) static var on: Bool { handle != nil }

    nonisolated(unsafe) static var tb = ""
    /// Half period (sweep) index, pass ("async", "sync", "early t=..",
    /// "init") and sweep time, set by simCircuit / evalEarlierInputs.
    nonisolated(unsafe) static var phase = ""
    /// What is being evaluated now, outermost first (cells, ports, blocks).
    nonisolated(unsafe) static var stack: [String] = []
    /// The latest recorded change of each node: (circuit, node) -> who/when.
    nonisolated(unsafe) static var last: [ObjectIdentifier: [Int: String]] = [:]
    nonisolated(unsafe) static var count = 0

    static func push(_ s: String) { if on { stack.append(s) } }
    static func pop() { if on && !stack.isEmpty { stack.removeLast() } }

    static func writer() -> String { stack.suffix(4).joined(separator: " / ") }

    /// A change of circ's node indx was recorded (saveChng).
    static func wrote(_ circ: Circuit, _ indx: Int, tm: Int, val: Int) {
        last[ObjectIdentifier(circ), default: [:]][indx] =
            "{tm: \(tm), val: \(val), writer: '\(writer())', phase: '\(phase)'}"
    }

    /// A write to circ's node indx at tm, earlier than its latest change.
    static func early(_ circ: Circuit, _ indx: Int, path: String, tm: Int, val: Int,
                      mask: Int = -1, effect: String) {
        guard let h = handle else { return }
        count += 1
        let nd = circ.nodes[indx]
        let prior = last[ObjectIdentifier(circ)]?[indx] ?? "null"
        let line = "- {n: \(count), tb: \(tb), phase: '\(phase)', node: \(makeNm(circ, nodeIndx: indx)), "
            + "path: \(path), mask: \(mask), new_tm: \(tm), new_val: \(val), "
            + "cur_tm: \(nd.updTm), cur_val: \(nd.node.value), effect: \(effect), "
            + "writer: '\(writer())', collides_with: \(prior)}\n"
        h.write(line.data(using: .utf8)!)
    }
}
