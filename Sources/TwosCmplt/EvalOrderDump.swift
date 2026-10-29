import Foundation

/// Opt-in record of each module's evaluation order, for comparing orders
/// before and after a change to the ordering rules.
///
/// `SIMRUN_ORDER_DUMP=<file>` appends one YAML line per module (its first
/// instance): the module, `hasLoop`, and `evalOrder` by name. Off unless set.
enum EvalOrderDump {
    static let path: String? = ProcessInfo.processInfo.environment["SIMRUN_ORDER_DUMP"]
    nonisolated(unsafe) static var seen = Set<String>()

    static func record(_ circ: Circuit) {
        guard let path = path, !seen.contains(circ.module) else { return }
        seen.insert(circ.module)
        let names: [String] = circ.evalOrder.compactMap { ref in
            switch ref.kind {
            case .aCirc:         return circ.aCircs[ref.index].name
            case .sCirc:         return circ.sCircs[ref.index].name
            case .vCirc, .cCirc: return circ.cCircs[ref.index].name
            case .oPrt:          return "out:" + circ.oPrts[ref.index].port
            case .assgnBlk:      return "assign[\(ref.index)]"
            case .iPrt, .none:   return nil
            }
        }
        let line = "- {module: \(circ.module), hasLoop: \(circ.hasLoop), order: [\(names.map { "'\($0)'" }.joined(separator: ", "))]}\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            h.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }
}
