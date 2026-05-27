import Foundation

struct VCDSignal: Codable {
    let scope: String
    let name: String
    let type: String   // e.g. "wire", "integer"
    let size: Int
    let changes: [[Int]]  // [[time, value]]
}

struct VCDConfig: Codable {
    let out: String
    let timescale: String
    let signals: [VCDSignal]
}

func makeNm(_ circ: Circuit, key: VCDkey) -> String {
    var nm = ""
    let indxs = key.circIndxs.dropFirst()
    var cr = circ
    for indx in indxs {
        nm = nm + cr.name + "."
        cr = circ.cCircs[indx]
    }
    nm = nm + cr.name + "." + cr.nodes[key.nodeIndx].name
    return nm
}

func makeNm_(_ circ: Circuit, nodeIndx: Int) -> String {
    var nm = ""
    let indxs = circ.indexs
    var cr = circ
    for indx in indxs {
        nm = nm + cr.name + "."
        cr = circ.cCircs[indx]
    }
    nm = nm + cr.name + "." + cr.nodes[nodeIndx].name
    return nm
}

func makeNm(_ circ: Circuit, nodeIndx: Int) -> String {
    var nms = [circ.name]
    var cr = circ.parent
    while cr != nil {
        nms.append(cr!.name)
        cr = cr?.parent
    }
    nms.reverse()
    var name = ""
    for nm in nms {
        name += nm + "."
    }
    name += circ.nodes[nodeIndx].name
    return name
}


func splitOnLastDot(_ s: String) -> (prefix: String, suffix: String)? {
    guard let idx = s.lastIndex(of: ".") else {
        return nil  // no dot present
    }
    let prefix = String(s[..<idx])
    let suffix = String(s[s.index(after: idx)...])
    return (prefix, suffix)
}

public func glblChngs2Vcd(_ topCirc: Circuit) -> [String: [[Int]]] {
    let chngs = Glbls.nodeChngs
    var sigChanges: [String: [[Int]]] = [:]
    var sigNms: [VCDkey: String] = [:]
    var sigNbits: [String: Int] = [:]
    var sigTraces: [String] = []
    for (i, chng) in chngs.enumerated() {
        let ky = VCDkey(circIndxs: chng.circIndxs, nodeIndx: chng.nodeIndx)
        if let nm = sigNms[ky] {
            // print("Node: \(nm) already encountered")
            sigChanges[nm, default: []].append([chng.updTm, chng.value])
        } else {
            let nm = makeNm(topCirc, key: ky)
            // print("Just made name: \(nm) for VCDkey: \(ky)")
            sigNms[ky] = nm
            sigNbits[nm] = chng.nbits
            sigChanges[nm, default: []].append([chng.updTm, chng.value])
            let chngStr = "\(i): time: \(chng.updTm), name: \(nm), value: \(chng.value)"
            print(chngStr)
            sigTraces.append(chngStr)
        }
    }
    print("sigChanges keys:", Array(sigChanges.keys))
    Glbls.sigTraces = sigTraces

    var signals: [VCDSignal] = []
    for (ky, chngs) in sigChanges {
        let (head, tail) = splitOnLastDot(ky)!
        let sgnl = VCDSignal(
            scope: head,
            name: tail,
            type: "logic",
            size: sigNbits[ky]!,
            changes: chngs
        )
        signals.append(sgnl)
    }

    let cfg = VCDConfig(
        out: Glbls.configs.directories.vcdDir + topCirc.name + ".vcd",
        timescale: "1 ps",
        signals: signals
    )

    do {
        try writeVCD(baseName: topCirc.name, with: cfg, scriptPath: Glbls.configs.fileNames.vcdScript)
        print("VCD written to \(topCirc.name).vcd")
    } catch {
        print("Failed to write VCD: \(error)")
    }

    return sigChanges
}

func writeVCD(baseName: String,
              with config: VCDConfig,
              python: String = Glbls.configs.fileNames.python,
              scriptPath: String) throws {
    let dumpPath = Glbls.configs.directories.dumpDir + baseName + ".json"
    let encoder = JSONEncoder()
    let jsonData = try encoder.encode(config)
    try jsonData.write(to: URL(fileURLWithPath: dumpPath))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: python)
    process.arguments = [scriptPath, baseName]

    let stderrPipe = Pipe()
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        throw NSError(domain: "VCDWriterError",
                      code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: errStr])
    }
}

func showChgs(_ tm1: Int, _ tm2: Int) -> String {
    var chngStr = ""
    let chngs = Glbls.allChngs.filter { $0.1.0 >= tm1 && $0.1.1 <= tm2}
    for chng in chngs {
        chngStr += "\(chng.1.0): \(chng.0): \(chng.1.1)\n"
    }
    return chngStr
}