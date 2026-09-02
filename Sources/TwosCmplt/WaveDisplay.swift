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

/// Write Glbls.nodeChngs to <dumpDir>/<module>Chngs.json when Glbls.saveChngs is
/// true. JSON, not YAML: large Chngs dumps (tens of thousands of entries) made
/// the previous hand-built-YAML-text version and its Python-side readers/writers
/// slow purely from serialization overhead -- see run_sim_ui.py's "Write Yaml"
/// Simulation-menu action for an on-demand human-readable export instead.
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
    let path = Glbls.configs.directories.dumpDir + "\(topCirc.module)Chngs.json"
    do {
        let data = try JSONEncoder().encode(Glbls.nodeChngs)
        try data.write(to: URL(fileURLWithPath: path))
        print("saveNodeChngs: wrote \(Glbls.nodeChngs.count) entries to \(path)")
    } catch {
        print("saveNodeChngs: failed to write \(path): \(error)")
    }
}

// Mirrors the map_data shape vcd2swift.py's build_map() produces on the Python
// side: {module: {instances: [{circIndxs, name}], nodes: [{name, nbits}]}}.
private struct MapInstanceJSON: Codable {
    let circIndxs: [Int]
    let name: String
}
private struct MapNodeJSON: Codable {
    let name: String
    let nbits: Int
}
private struct MapEntryJSON: Codable {
    let instances: [MapInstanceJSON]
    let nodes: [MapNodeJSON]
}

/// Write a module-keyed map to <dumpDir>/<module>Map.json when Glbls.saveDefMap
/// is true. Each entry lists circuit instances (circIndxs + name) and the node
/// names from the corresponding CircDef. JSON for the same reason as
/// saveNodeChngs above (Map.json is small, but the two files are always
/// produced/consumed together).
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

    // Group all circuit instances in the hierarchy by module name.
    var byModule: [String: [(circIndxs: [Int], name: String)]] = [:]
    for inst in collectInstances(topCirc) {
        byModule[inst.module, default: []].append((inst.circIndxs, inst.name))
    }

    var mapData: [String: MapEntryJSON] = [:]
    for (module, insts) in byModule {
        let instances = insts.map { MapInstanceJSON(circIndxs: $0.circIndxs, name: $0.name) }
        var nodes: [MapNodeJSON] = []
        if let def = Glbls.circDef(for: module) {
            nodes = def.nodes.map { MapNodeJSON(name: $0.name, nbits: $0.node.nbits) }
        }
        mapData[module] = MapEntryJSON(instances: instances, nodes: nodes)
    }

    let path = Glbls.configs.directories.dumpDir + "\(topCirc.module)Map.json"
    do {
        let data = try JSONEncoder().encode(mapData)
        try data.write(to: URL(fileURLWithPath: path))
        print("saveDefMap: wrote \(mapData.count) module(s) to \(path)")
    } catch {
        print("saveDefMap: failed to write \(path): \(error)")
    }
}
