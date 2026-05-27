import Foundation
import Yams
import SwiftPrettyPrint
import Glibc

/// A recursive representation of any JSON-like value.
public enum JSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try each possible representation in order of "most specific" /
        // least likely to conflict.
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            // This is where recursion happens for arrays:
            // each element is decoded as JSONValue, which calls this init again.
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            // And recursion for objects / dictionaries.
            self = .object(value)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported JSON/YAML value for JSONValue"
                )
            )
        }
    }
}

public extension JSONValue {
    var object: [String: JSONValue]? {
        if case let .object(o) = self { return o }
        return nil
    }

    var array: [JSONValue]? {
        if case let .array(a) = self { return a }
        return nil
    }

    var string: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    var int: Int? {
        if case let .int(i) = self { return i }
        return nil
    }
    var double: Double? {
        if case let .double(d) = self { return d }
        return nil
    }
}

public extension JSONValue {
    subscript(_ key: String) -> JSONValue? {
        object?[key]
    }

    subscript(_ index: Int) -> JSONValue? {
        guard let arr = array, index >= 0, index < arr.count else { return nil }
        return arr[index]
    }

    var arrayValue: [JSONValue] {
        array ?? []
    }
}

public func toAny(_ v: JSONValue) -> Any {
    switch v {
    case .string(let s): return s
    case .int(let i):    return i
    case .double(let d): return d
    case .bool(let b):   return b
    case .array(let a):  return a.map(toAny)
    case .object(let o): return o.mapValues(toAny)
    case .null:          return NSNull()
    }
}

// Example usage with JSONDecoder.
// Replace this part with YAMLDecoder().decode(JSONValue.self, from: yamlString)
// if you're using Yams for YAML.

/*
let json = """
{
  "module": "DG_DR_3X1",
  "params": [
    { "type": "Int", "name": "delay", "value": 5 }
  ],
  "io_ports": [
    { "name": "D" },
    { "name": "R" }
  ],
  "nested": {
    "numbers": [1, 2, 3],
    "flag": true,
    "nullValue": null
  }
}
"""

if let data = json.data(using: .utf8) {
    let decoder = JSONDecoder()
    let root = try decoder.decode(JSONValue.self, from: data)
    print(root)
}
*/

public func ldYamlConfig(at path: String = "Config.yaml") throws -> ProjectConfig {
    let url = URL(fileURLWithPath: path)
    let yamlString = try String(contentsOf: url, encoding: .utf8)
    return try YAMLDecoder().decode(ProjectConfig.self, from: yamlString)
}

public func rdFile(at path: String) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let text = String(data: data, encoding: .utf8) else {
        return nil
    }
    return text
}

public func readFile(at path: String) -> String? {
    try? String(contentsOfFile: path, encoding: .utf8)
}

/*
if let text = readFile(at: "/path/to/file.txt") {
    print(text)
} else {
    print("Couldn't read file.")
}
*/

public func rdYAML<T: Decodable>(at path: String) throws -> T {
    let url = URL(fileURLWithPath: path)
    let yamlString = try String(contentsOf: url, encoding: .utf8)
    return try YAMLDecoder().decode(T.self, from: yamlString)
}

public func rdYML<T: Decodable>(at path: String) -> T? {
    guard let yamlString = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return try? YAMLDecoder().decode(T.self, from: yamlString)
}

public func readYML_<T: Decodable>(at path: String) -> T? {
    guard let yamlString = try? String(contentsOfFile: path, encoding: .utf8) else {
        return nil
    }
    return try? YAMLDecoder().decode(T.self, from: yamlString)
}

public func readYML<T: Decodable>(at path: String) -> T? {
    do {
        let yamlString = try String(contentsOfFile: path, encoding: .utf8)
        return try YAMLDecoder().decode(T.self, from: yamlString)
    } catch {
        print("YAML decoding failed: \(error)")
        return nil
    }
}


// MARK: - Generic YAML Saver
public func writeYML<T: Encodable>(_ object: T, to path: String) -> Bool {
    do {
        let yamlString = try YAMLEncoder().encode(object)
        try yamlString.write(toFile: path, atomically: true, encoding: .utf8)
        return true
    } catch {
        return false
    }
}

/*
let config: ProjectConfig = try! loadYAMLConfig(at: "Config.yaml")

let config: ProjectConfig

do {
    config = try loadYAMLConfig(at: "Config.yaml")
} catch {
    fatalError("Failed to load configuration: \(error)")
}

guard let config: ProjectConfig = readYAMLConfig(at: "Config.yaml") else {
    fatalError("Configuration file could not be loaded.")
}

// Load
guard let config: ProjectConfig = readYML(at: "Config.yaml") else {
    fatalError("Could not load Config.yaml")
}

// Modify
var updated = config
updated.optimized = true

// Save
if !writeYML(updated, to: "Config.yaml") {
    print("Failed to save configuration.")
}


*/

public func fileNames(in directory: URL) throws -> [URL] {
    return try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]   // or [] if you want hidden items too
    )
}

public func fileURLs(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
}

public extension Dictionary {
    subscript(required key: Key) -> Value {
        guard let value = self[key] else {
            fatalError("Missing required key \(key)")
        }
        return value
    }
}

extension Dictionary {
    /// Lookup that must succeed; crashes with a clear message otherwise.
    func fnd(_ key: Key, file: StaticString = #fileID, line: UInt = #line) -> Value {
        guard let value = self[key] else {
            fatalError("Missing key \(key) in dictionary", file: file, line: line)
        }
        return value
    }
}

public extension String.StringInterpolation {
    mutating func appendInterpolation<T: BinaryInteger>(
        _ value: T,
        asSignedHex width: Int = 0,
        uppercase: Bool = true
    ) {
        // Separate sign and magnitude.
        let isNegative = value < 0
        let magnitude = value.magnitude   // Unsigned

        var hex = String(magnitude, radix: 16, uppercase: uppercase)

        // Pad the hex magnitude only.
        if width > 0 {
            hex = String(repeating: "0", count: max(0, width - hex.count)) + hex
        }

        let sign = isNegative ? "-" : ""
        appendLiteral("\(sign)0x\(hex)")
    }
}

public func sgndHx<T: BinaryInteger>(_ value: T, width: Int = 0, uppercase: Bool = true) -> String {
    let isNegative = value < 0
    let magnitude = value.magnitude

    var hex = String(magnitude, radix: 16, uppercase: uppercase)
    if width > 0 {
        hex = String(repeating: "0", count: max(0, width - hex.count)) + hex
    }

    let sign = isNegative ? "-" : ""
    return "\(sign)0x\(hex)"
}

/*
public extension String.StringInterpolation {
    mutating func appendInterpolation<T>(
        debugging value: T, asHex width: Int = 0
    ) {
        print("T is \(T.self)")
        appendLiteral("x")
    }
}
*/

@discardableResult
public func dmp(_ values: Any?...) -> [Any?] {
    for v in values {
        dump(v)
    }
    return values
}

public func eprint(_ message: String) {
    let msg = message + "\n"
    if let data = msg.data(using: .utf8) {
        try? FileHandle.standardError.write(contentsOf: data)
    }
}

public func withFile(
    _ path: String,
    mode: String = "w",
    body: (UnsafeMutablePointer<FILE>) -> Void
) {
    guard let fp = fopen(path, mode) else {
        eprint("open failed: \(path)")
        return
    }
    defer { fclose(fp) }
    body(fp)
}

public func baseName(_ node: String) -> String {
    if let bracketIndex = node.firstIndex(of: "[") {
        return String(node[..<bracketIndex])
    }
    return node
}

// Returns the bit index for names like "QD_[15]". Returns nil for ranges like "QD_[17:0]"
// or plain names without brackets.
public func parseSingleBitIndex(_ node: String) -> Int? {
    guard let lo = node.firstIndex(of: "["),
          let hi = node.lastIndex(of: "]"),
          lo < hi else { return nil }
    let inner = String(node[node.index(after: lo)..<hi])
    guard !inner.contains(":"), let bit = Int(inner) else { return nil }
    return bit
}

extension URL {
    public func file(_ name: String, ext: String) -> URL {
        self.appendingPathComponent(name).appendingPathExtension(ext)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array {
    mutating func popFirst() -> Element? {
        self.isEmpty ? nil : removeFirst()
    }
}

func measure(_ label: String, _ block: () -> Void) {
    let start = ProcessInfo.processInfo.systemUptime
    block()
    let end = ProcessInfo.processInfo.systemUptime
    print("\(label): \(end - start) seconds")
}

public func rdNds(_ path: String) -> String {
    let names = path.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
    guard !names.isEmpty else { return "" }
    guard let top = Glbls.topCircuit, top.name == names[0] else {
        return "rdNds: top circuit '\(names.first ?? "")' not found"
    }
    var current = top
    for name in names.dropFirst() {
        guard let next = current.cCircs.first(where: { $0.name == name }) else {
            return "rdNds: circuit '\(name)' not found in '\(current.name)'"
        }
        current = next
    }
    return current.nodes.map { "\($0.name): \($0.node.value)" }.joined(separator: "\n")
}

private func fmtVal(_ val: Int, nbits: Int, frmt: String) -> String {
    let mask: Int = nbits < Int.bitWidth ? (1 << nbits) - 1 : -1
    let bits = val & mask
    switch frmt {
    case "dec":
        return String(UInt(bitPattern: bits))
    case "sdec":
        return String(val)
    case "bin":
        let s = String(UInt(bitPattern: bits), radix: 2)
        return "0b" + String(repeating: "0", count: max(0, nbits - s.count)) + s
    default:  // "hex"
        let digits = (nbits + 3) / 4
        return String(format: "0x%0\(digits)X", UInt(bitPattern: bits))
    }
}

private func emitChngs(_ matches: [(Int, String)], frmt: String, to filename: String) {
    withFile(filename) { fp in
        for (i, nm) in matches {
            let ndChng = Glbls.nodeChngs[i]
            let line = "t=\(ndChng.updTm)  \(nm)  \(fmtVal(ndChng.value, nbits: ndChng.nbits, frmt: frmt))"
            print(line)
            fputs(line + "\n", fp)
        }
        fflush(fp)
    }
}

public func shw_chngs(_ circPath: String, frmt: String = "hex") {
    let prefix = circPath + "."
    let matches: [(Int, String)] = Glbls.allChngs.enumerated().compactMap { i, entry in
        let nm = entry.0
        guard nm.hasPrefix(prefix) else { return nil }
        let nodePart = String(nm.dropFirst(prefix.count))
        guard !nodePart.contains(".") else { return nil }
        return (i, nm)
    }
    guard !matches.isEmpty else {
        print("shw_chngs: no changes found for '\(circPath)'"); return
    }
    emitChngs(matches, frmt: frmt, to: "chngs.out")
}

public func shw_outs(_ circPath: String, frmt: String = "hex") {
    let names = circPath.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
    guard !names.isEmpty else { print("shw_outs: empty path"); return }
    guard let top = Glbls.topCircuit, top.name == names[0] else {
        print("shw_outs: top circuit '\(names.first ?? "")' not found"); return
    }
    var current = top
    for name in names.dropFirst() {
        guard let next = current.cCircs.first(where: { $0.name == name }) else {
            print("shw_outs: circuit '\(name)' not found in '\(current.name)'"); return
        }
        current = next
    }
    let outNodeNames = Set(current.oPrts.map { current.nodes[$0.intlIndx].name })
    let prefix = circPath + "."
    let matches: [(Int, String)] = Glbls.allChngs.enumerated().compactMap { i, entry in
        let nm = entry.0
        guard nm.hasPrefix(prefix) else { return nil }
        let nodePart = String(nm.dropFirst(prefix.count))
        guard outNodeNames.contains(nodePart) else { return nil }
        return (i, nm)
    }
    guard !matches.isEmpty else {
        print("shw_outs: no output changes found for '\(circPath)'"); return
    }
    emitChngs(matches, frmt: frmt, to: "chngs.out")
}

public func chk_stpHld() {
    guard let top = Glbls.topCircuit else {
        print("chk_stpHld: no top circuit"); return
    }
    guard Glbls.period > 0 else {
        print("chk_stpHld: Glbls.period not set"); return
    }
    var violations: [String] = []
    walkForTiming(top, path: top.name, violations: &violations)
    for v in violations { print(v) }
    if violations.isEmpty { print("chk_stpHld: no violations found") }
    withFile("timing.out") { fp in
        for v in violations { fputs(v + "\n", fp) }
        fflush(fp)
    }
}

private func walkForTiming(_ circ: Circuit, path: String, violations: inout [String]) {
    let clkPorts = circ.iPrts.filter { $0.port.lowercased().hasPrefix("clk") }
    if !clkPorts.isEmpty && circ.kind == "sync" {
        checkSyncTiming(circ, path: path, clkPorts: clkPorts, violations: &violations)
    }
    for sub in circ.cCircs {
        walkForTiming(sub, path: path + "." + sub.name, violations: &violations)
    }
    for sub in circ.vCircs {
        walkForTiming(sub, path: path + "." + sub.name, violations: &violations)
    }
}

private func checkSyncTiming(
    _ circ: Circuit, path: String,
    clkPorts: [PortDef], violations: inout [String]
) {
    let period = Glbls.period
    let setupThresh = Int(Glbls.setupTm * Double(period))
    let holdThresh  = Int(Glbls.holdTm  * Double(period))
    let prefix = path + "."

    // Collect all direct-child node changes for this circuit
    let circChngs: [(nodeName: String, time: Int)] = Glbls.allChngs.compactMap { entry in
        let nm = entry.0
        guard nm.hasPrefix(prefix) else { return nil }
        let nodePart = String(nm.dropFirst(prefix.count))
        guard !nodePart.contains(".") else { return nil }
        return (nodePart, entry.1.0)
    }

    // Resolve node names for clk and non-clk inputs;
    // intlIndx is 1_000_000 when unresolved, fall back to prt.node.
    func nodeName(for prt: PortDef) -> String {
        if prt.intlIndx < 1_000_000, let nd = circ.nodes[safe: prt.intlIndx] { return nd.name }
        return prt.node
    }

    let clkNodeNames     = Set(clkPorts.map { nodeName(for: $0) })
    let nonClkInputNames = Set(circ.iPrts
        .filter { !$0.port.lowercased().hasPrefix("clk") }
        .map    { nodeName(for: $0) }
    )

    let clkTimes = circChngs
        .filter { clkNodeNames.contains($0.nodeName) }
        .map    { $0.time }
        .sorted()

    guard !clkTimes.isEmpty else { return }

    let nonClkChngs = circChngs.filter { nonClkInputNames.contains($0.nodeName) }

    for chng in nonClkChngs {
        let tm = chng.time
        // Setup: non-clk input changes too close before the next clock edge
        if let nextClk = clkTimes.first(where: { $0 > tm }), nextClk - tm < setupThresh {
            violations.append(
                "Possible Setup Violation: t=\(tm), \(circ.module), \(circ.name), \(chng.nodeName)"
            )
        }
        // Hold: non-clk input changes too close after the previous clock edge
        if let prevClk = clkTimes.last(where: { $0 < tm }), tm - prevClk < holdThresh {
            violations.append(
                "Possible Hold Violation: t=\(tm), \(circ.module), \(circ.name), \(chng.nodeName)"
            )
        }
    }
}

public func shw_ordr(_ hierarchicalName: String) {
    let names = hierarchicalName.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
    guard !names.isEmpty else { print("shw_ordr: empty path"); return }
    guard let top = Glbls.topCircuit, top.name == names[0] else {
        print("shw_ordr: top circuit '\(names.first ?? "")' not found"); return
    }
    var current = top
    for name in names.dropFirst() {
        guard let next = current.cCircs.first(where: { $0.name == name }) else {
            print("shw_ordr: circuit '\(name)' not found in '\(current.name)'"); return
        }
        current = next
    }
    let lines: [String] = current.evalOrder.compactMap { ref in
        switch ref.kind {
        case .aCirc:        return current.aCircs[ref.index].name
        case .sCirc:        return current.sCircs[ref.index].name
        case .vCirc, .cCirc: return current.cCircs[ref.index].name
        case .oPrt:         return current.oPrts[ref.index].port
        case .iPrt, .none:  return nil
        }
    }
    withFile("order.out") { fp in
        for line in lines {
            print(line)
            fputs(line + "\n", fp)
        }
        fflush(fp)
    }
}
