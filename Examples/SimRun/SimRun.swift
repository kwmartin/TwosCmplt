import TwosCmplt
import Foundation
import Glibc
import Yams

func errPrint(_ msg: String) {
    let m = msg + "\n"
    _ = m.withCString { Glibc.write(2, $0, m.utf8.count) }
}

func loadConfig(at path: String) throws -> ProjectConfig {
    let url = URL(fileURLWithPath: path)
    let yaml = try String(contentsOf: url, encoding: .utf8)
    return try YAMLDecoder().decode(ProjectConfig.self, from: yaml)
}

@main
struct SimRun {
    static func main() {
        var rawArgs     = CommandLine.arguments
        let rebuildOnly = rawArgs.contains("--rebuild")
        rawArgs = rawArgs.filter { $0 != "--rebuild" }

        // Extract optional --spec <path>
        var specPath: String? = nil
        if let idx = rawArgs.firstIndex(of: "--spec"), idx + 1 < rawArgs.count {
            specPath = rawArgs[idx + 1]
            rawArgs.removeSubrange(idx...(idx + 1))
        }

        guard rawArgs.count >= 2 else {
            errPrint("Usage: SimRun <CircuitName> [/path/to/Config.yaml] [--spec /path/to/spec.yml] [--rebuild]")
            exit(1)
        }
        let circuitName = rawArgs[1]
        let configPath  = rawArgs.count >= 3 ? rawArgs[2] : "Config.yaml"

        do {
            Glbls.configs = try loadConfig(at: configPath)
        } catch {
            errPrint("SimRun: failed to load config '\(configPath)': \(error)")
            exit(1)
        }

        guard var circDef = makeCircDef(circuitName) else {
            errPrint("SimRun: failed to build CircDef for '\(circuitName)'")
            exit(1)
        }

        let circuit = circDef.toCircuit()
        saveDefMap()

        if rebuildOnly {
            exit(0)
        }

        // Remove any TimeSpcs entries for nodes absent from this circuit.
        let permSpecURL = Glbls.simSpcsDir.file(circuitName, ext: "yml")
        cleanSpecFile(at: permSpecURL, knownNodes: Set(circuit.nodeLU.keys))

        let specs: (per: Int, finishTm: Int, tmSpcs: [TimeSpec])
        if let path = specPath {
            specs = loadSpecs(fromURL: URL(fileURLWithPath: path))
        } else {
            specs = loadSpecs(circuitName)
        }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = simCircuit(circuit, per: specs.per, finishTm: specs.finishTm, tmSpcs: specs.tmSpcs)
        }
        print("Elapsed Time: \(elapsed)")
        saveNodeChngs()
    }
}
