// Glbls.swift
import Foundation
import SharedTypes


/*
@globalActor
public actor StatesActor {
    public static let shared = StatesActor()
}
*/

public struct DebugKey: Hashable, Sendable {
    public let file: String
    public let line: Int
}

public enum Tbl: Sendable, CustomStringConvertible {
    case tbl(int: Int)
    case tbls(ints: [Int])

    public var description: String {
        switch self {
        case .tbl(let int):
            return "Tbl.single(\(int))"
        case .tbls(let ints):
            return "Tbl.multiple(\(ints))"
        }
    }
}


// @StatesActor
public enum Glbl {
    nonisolated(unsafe) public static var a3_: [TwoCmplt] = []
    nonisolated(unsafe) public static var a2_: [TwoCmplt] = []
    nonisolated(unsafe) public static var a1_: [TwoCmplt] = []
    nonisolated(unsafe) public static var a0_: [TwoCmplt] = []
    nonisolated(unsafe) public static var arry: [TwoCmplt] = []
}

public struct Glbls {
    // Private backing store
    nonisolated(unsafe) private static var _circDefs: [String: CircDef] = [:]

    // Write API – used during build
    public static func register(_ def: CircDef) {
        _circDefs[def.module] = def
    }

    // Optional bulk fill, if you build them in one shot
    public static func registerAll(_ defs: [CircDef]) {
        for def in defs {
            _circDefs[def.kind] = def
        }
    }

    // Read API – used everywhere else
    public static func circDef(for kind: String) -> CircDef? {
        _circDefs[kind]
    }

    public static var allCircDefs: [CircDef] {
        Array(_circDefs.values)
    }

    // Read API – used everywhere else
    public static func circCnt() -> Int {
        _circDefs.count
    }

    nonisolated(unsafe) public static var cstmGt: [String: Tbl] = [:]
    nonisolated(unsafe) public static var mltTruncate: Bool = false
    nonisolated(unsafe) public static var topCircuit: Circuit? = nil
    nonisolated(unsafe) public static var nodeChngs: [NodeChng] = []
    nonisolated(unsafe) public static var configs: ProjectConfig!
    nonisolated(unsafe) public static var sigTraces: [String] = []
    nonisolated(unsafe) public static var allChngs: [(String, (Int, Int))] = []
    nonisolated(unsafe) public static var saveChngs: Bool = true
    nonisolated(unsafe) public static var saveDefMap: Bool = true
    nonisolated(unsafe) public static var buildNew: Bool = true
    nonisolated(unsafe) public static var yamlIndent: Int = 2
    nonisolated(unsafe) public static var debugOn: Bool = true
    nonisolated(unsafe) public static var debugTms: [DebugKey: Duration] = [:]
    nonisolated(unsafe) public static var period: Int = 0
    nonisolated(unsafe) public static var setupTm: Double = 0.25
    nonisolated(unsafe) public static var holdTm: Double = 0.05

    public static let projectRoot: URL = {
        let thisFile  = #filePath
        let srcDir    = URL(fileURLWithPath: thisFile).deletingLastPathComponent()
        let moduleDir = srcDir.deletingLastPathComponent()
        let project   = moduleDir.deletingLastPathComponent()
        return project
    }()

    public static let circLibDir: URL = {
        // Adjust the relative path components to match your layout
        Glbls.projectRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("CircuitLib", isDirectory: true)
    }()

    public static let logicLibDir: URL = {
        // Adjust the relative path components to match your layout
        Glbls.projectRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("LogicLib", isDirectory: true)
    }()

    public static let simSpcsDir: URL = {
        // Adjust the relative path components to match your layout
        Glbls.projectRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("SimSpcs", isDirectory: true)
    }()

    public static let memFilesDir: URL = {
        Glbls.projectRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("MemFiles", isDirectory: true)
    }()

}
