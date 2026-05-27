// WaveDisplay.swift
import Foundation

// Walk the circuit hierarchy and collect every instance as (circIndxs, module, name).
private func collectInstances(_ circ: Circuit) -> [(circIndxs: [Int], module: String, name: String)] {
    var result = [(circIndxs: circ.indexs, module: circ.module, name: circ.name)]
    for child in circ.cCircs {
        result += collectInstances(child)
    }
    return result
}

/// Write Glbls.nodeChngs to <dumpDir>/<module>Chngs.yml when Glbls.saveChngs is true.
/// Indentation width is controlled by Glbls.yamlIndent.
public func saveNodeChngs() {
    guard Glbls.saveChngs else { return }
    guard Glbls.configs != nil else {
        print("saveNodeChngs: Glbls.configs not set")
        return
    }
    guard let topCirc = Glbls.topCircuit else {
        print("saveNodeChngs: Glbls.topCircuit is nil")
        return
    }
    let ind = String(repeating: " ", count: Glbls.yamlIndent)
    var lines: [String] = []
    for chng in Glbls.nodeChngs {
        let indxsStr = "[" + chng.circIndxs.map { String($0) }.joined(separator: ", ") + "]"
        lines.append("- circIndxs: \(indxsStr)")
        lines.append("\(ind)nodeIndx: \(chng.nodeIndx)")
        lines.append("\(ind)value: \(chng.value)")
        lines.append("\(ind)updTm: \(chng.updTm)")
        lines.append("\(ind)nbits: \(chng.nbits)")
        lines.append("\(ind)capac: \(chng.capac)")
    }
    let yaml = lines.joined(separator: "\n") + "\n"
    let path = Glbls.configs.directories.dumpDir + "\(topCirc.module)Chngs.yml"
    do {
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
        print("saveNodeChngs: wrote \(Glbls.nodeChngs.count) entries to \(path)")
    } catch {
        print("saveNodeChngs: failed to write \(path): \(error)")
    }
}

/// Write a module-keyed map to <dumpDir>/<module>Map.yml when Glbls.saveDefMap is true.
/// Each entry lists circuit instances (circIndxs + name) and the node names from
/// the corresponding CircDef. Indentation width is controlled by Glbls.yamlIndent.
public func saveDefMap() {
    guard Glbls.saveDefMap else { return }
    guard Glbls.configs != nil else {
        print("saveDefMap: Glbls.configs not set")
        return
    }
    guard let topCirc = Glbls.topCircuit else {
        print("saveDefMap: Glbls.topCircuit is nil")
        return
    }
    let ind = String(repeating: " ", count: Glbls.yamlIndent)

    // Group all circuit instances in the hierarchy by module name.
    var byModule: [String: [(circIndxs: [Int], name: String)]] = [:]
    for inst in collectInstances(topCirc) {
        byModule[inst.module, default: []].append((inst.circIndxs, inst.name))
    }

    var lines: [String] = []
    for module in byModule.keys.sorted() {
        lines.append("\(module):")
        lines.append("\(ind)instances:")
        for inst in byModule[module]! {
            let indxsStr = "[" + inst.circIndxs.map { String($0) }.joined(separator: ", ") + "]"
            lines.append("\(ind)- circIndxs: \(indxsStr)")
            lines.append("\(ind)  name: \(inst.name)")
        }
        lines.append("\(ind)nodes:")
        if let def = Glbls.circDef(for: module) {
            for nod in def.nodes {
                lines.append("\(ind)- name: \(nod.name)")
                lines.append("\(ind)  nbits: \(nod.node.nbits)")
            }
        }
    }
    let yaml = lines.joined(separator: "\n") + "\n"
    let path = Glbls.configs.directories.dumpDir + "\(topCirc.module)Map.yml"
    do {
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
        print("saveDefMap: wrote \(byModule.count) module(s) to \(path)")
    } catch {
        print("saveDefMap: failed to write \(path): \(error)")
    }
}
