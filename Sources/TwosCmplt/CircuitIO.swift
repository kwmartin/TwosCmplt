import Foundation
import Yams

import SharedTypes

// Uses your existing Glbls.circLibDir
func yamlURL(for fileName: String) -> URL {
    Glbls.circLibDir
        .appendingPathComponent(fileName)
        .appendingPathExtension("yml")
}

func loadCircuitYAML(named fileName: String) -> String? {
    let url = yamlURL(for: fileName)

    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        print("Warning: failed to read YAML at \(url): \(error)")
        return nil
    }
}

func addSeg(name: String, seg: (Int, Int), circuit: Circuit) -> Int {

    let nbits = seg.0 - seg.1 + 1
    let value = TwoCmplt(0, nbits: nbits)
    let indx = circuit.nodes.count
    let ndNm = name + "_\(indx)"
    let outNd = Nod(name: ndNm, value:value)
    circuit.nodes.append(outNd)
    let inNd = circuit.nodeLU[name]!
    let segGt = Gate(
        seg: seg,
        circuit: circuit,
        inps: [inNd],
        outs: [indx]
        )
    circuit.aCircs.append(segGt)
    return indx
}

func circSeg(name: String, seg: (Int, Int), circuit: Circuit) -> (Int, Int) {

    let nbits = seg.0 - seg.1 + 1
    let value = TwoCmplt(0, nbits: nbits)
    let indx = circuit.nodes.count
    let ndNm = name + "_\(indx)"
    let outNd = Nod(name: ndNm, value:value)
    circuit.nodes.append(outNd)
    let inNd = circuit.nodeLU[name]!
    let segGt = Gate(
        seg: seg,
        circuit: circuit,
        inps: [inNd],
        outs: [indx]
        )
    circuit.aCircs.append(segGt)
    return (indx, nbits)
}

func inPort2Indxs(port: Port, circuit: Circuit) -> [Int] {
    switch port {

    case let .node(_, nodeRef):
        switch nodeRef {
        case let .name(name):
            return [circuit.nodeLU[name]!]
        case let .supply(val):
            switch val {
            case 0: return [1000000]
            case 1: return [1000001]
            default: preconditionFailure("Invalid supply value: \(val)")
            }
        }

    case let .segmented(_, segments):
        return segments.map { seg in
            addSeg(name: seg.node, seg: seg.width, circuit: circuit)
        }

    case let .arry(strArray):
        // Assuming StrArray == [String] and you want [Int]
        return strArray.map { circuit.nodeLU[$0]! }

    case let .bus(busArray):
        // BusArray: [BusElem]
        return busArray.map { elem in
            switch elem {
            case let .bus(name):
                guard let node = circuit.nodeLU[name] else {
                    fatalError("Node \(name) is not in circuit.nodeLU")
                }
                return node
            case let .bit((name, bit)):
                return addSeg(name: name, seg: (bit, bit), circuit: circuit)
            case let .slc((name, n1, n2)):
                return addSeg(name: name, seg: (n1, n2), circuit: circuit)
            }
        }
    }
}

func outPort2Indxs(port: OutPort, circuit: Circuit) -> [Int] {
    switch port {

    case let .node(nd):
        let idx = circuit.nodeLU.lu(for: nd)
        return [idx]

    case let .arry(strArray):
        return strArray.map { circuit.nodeLU[$0]! }

    case let .port(_, nd):
        return [circuit.nodeLU[nd]!]
    }
}

public func MakeCircuit(_ circModule: String, circDct: [String: ArryVal], circuit: Circuit) {

    // Only reset to 0 if not pre-set (e.g. by toCircuit before wireFromDict)
    if circuit.index < 0 { circuit.index = 0 }

    if let paramsVal = circDct["params"],
    case let .prms(prms) = paramsVal {
        circuit.parms = prms
    }

    if let circuitParm = circuit.parms.first(where: { $0.name == "circuit" }) {
        if case let .str(mode) = circuitParm.value {
            if mode == "sync" {
                circuit.sync = true
            }
        }
    }
    if let circuitParm = circuit.parms.first(where: { $0.name == "delay" }) {
        if case let .int(dly) = circuitParm.value {
            circuit.delay = Delay(fixed: dly, outcap: circuit.delay.outcap)
        }
        if case let .real(dly) = circuitParm.value {
            circuit.delay = Delay(fixed: Int(dly), outcap: circuit.delay.outcap)
        }
    }

    if let sensVal = circDct["sense"],
    case let .sens(sns) = sensVal {
        circuit.sens = sns
    }


    if let delayVal = circDct["delay"],
    case let .delay(dly) = delayVal {
        circuit.delay = dly
    }

    // Note inPrts, outPrts, and nodes are required, aCircs, sCircs, and cCircs are optional
    guard let inPrts = circDct["inPrts"] else {
    preconditionFailure("No 'inPrts' entry for circuit \(circModule)")
    }

    guard let outPrts = circDct["outPrts"] else {
        preconditionFailure("No 'outPrts' entry for circuit \(circModule)")
    }

    guard let nodesVal = circDct["nodes"] else {
        preconditionFailure("No 'nodes' entry for circuit \(circModule)")
    }

    guard case let .nodes(nodesArray) = nodesVal else {
        preconditionFailure("nodes entry is not .nodes for circuit \(circModule)")
    }

    var nodeLU: [String:Int] = [:]
    var Nodes: [Nod] = []

    for (i, node) in nodesArray.enumerated() {
        switch node {
        case .name(let s):
            // print("plain name: \(s)")
            nodeLU[s] = i
            Nodes.append(Nod(s))

        case .def(let def):
            // print("def name: \(def.name), nbits: \(def.nbits)")
            nodeLU[def.name] = i
            Nodes.append(Nod(def.name, nbits: def.nbits))
        }
    }

    circuit.nodes = Nodes

    guard case let .arry(inPrtsArry) = inPrts else {
        preconditionFailure("inPrts entry is not .arry for circuit \(circModule)")
    }

    var iprtDefs : [PortDef] = []
    for (prtIndx, prt) in inPrtsArry.enumerated() {

        switch prt {
        case let .string(name):
            if let intlIndx = nodeLU[name] {
                // print("Port: \(name), node index: \(intlIndx)")
                let extlIndx = circuit.nodeLU[name]!

                let prtDef = PortDef(
                    port: name,
                    node: name,
                    nbits: 1,
                    intlIndx: extlIndx,
                    extlIndx: intlIndx,
                    sgmnts: []
                    )

                circuit.nodes[intlIndx].nodeDrvr = CmpRef(kind: .iPrt, index: prtIndx)
                iprtDefs.append(prtDef)
                continue
            } else {
                print("Unknown node name: \(name)")
            }

        case let .object(obj):

            if case let .string(name)? = obj["name"],
               case let .int(nbits)?  = obj["nbits"] {
                if let intlIndx = nodeLU[name] {
                    // print("Port: \(name), nbits: \(nbits), node index: \(intlIndx)")

                    let extlIndx = circuit.nodeLU[name]!

                    let prtDef = PortDef(
                        port: name,
                        node: name,
                        nbits: nbits,
                        intlIndx: intlIndx,
                        extlIndx: extlIndx,
                        sgmnts: []
                        )

                    circuit.nodes[intlIndx].nodeDrvr = CmpRef(kind: .iPrt, index: prtIndx)
                    iprtDefs.append(prtDef)
                    continue
                } else {
                    print("Unknown node name: \(name)")
                }
            }

            if case let .string(port)? = obj["port"] {
                if let intlIndx = nodeLU[port] {
                    // print("Port: \(port), nbits: 1, node index: \(intlIndx)")

                    let extlIndx = circuit.nodeLU[port]!

                    let prtDef = PortDef(
                        port: port,
                        node: port,
                        nbits: 1,
                        intlIndx: intlIndx,
                        extlIndx: extlIndx,
                        sgmnts: []
                        )

                    circuit.nodes[intlIndx].nodeDrvr = CmpRef(kind: .iPrt, index: prtIndx)
                    iprtDefs.append(prtDef)
                    continue
                } else {
                    print("Unknown node name: \(port)")
                }
            }

            print("Unsupported object shape: \(obj)")

        case let .array(nested):
            // handle nested structure; to be done to allow hierarchical ports
            print("\(nested)")

        default:
            print("Unsupported port value: \(prt)")
        }
    }
    circuit.iPrts = iprtDefs
    // print("#inPrts: \(iprtDefs.count)")

    guard case let .arry(outPrtsArry) = outPrts else {
        preconditionFailure("outPrts entry is not .arry for circuit \(circModule)")
    }

    var oprtDefs: [PortDef] = []
    for prt in outPrtsArry {
        switch prt {
        case let .string(name):
            if let intlIndx = nodeLU[name] {
                // print("Port: \(name), node index: \(intlIndx)")

                let extlIndx = circuit.nodeLU[name]!

                let prtDef = PortDef(
                    port: name,
                    node: name,
                    nbits: 1,
                    intlIndx: intlIndx,
                    extlIndx: extlIndx,
                    sgmnts: []
                    )

                oprtDefs.append(prtDef)
                continue
            } else {
                print("Unknown node name: \(name)")
            }

        case let .object(obj):
            if case let .string(name)? = obj["name"],
               case let .int(nbits)?  = obj["nbits"] {
                if let intlIndx = nodeLU[name] {
                    // print("Port: \(name), nbits: \(nbits), node index: \(intlIndx)")

                    let extlIndx = circuit.nodeLU[name]!

                    let prtDef = PortDef(
                        port: name,
                        node: name,
                        nbits: nbits,
                        intlIndx: intlIndx,
                        extlIndx: extlIndx,
                        sgmnts: []
                        )

                    oprtDefs.append(prtDef)
                    continue
                } else {
                    print("Unknown node name: \(name)")
                }
            }

            if case let .string(port)? = obj["port"] {
                if let intlIndx = nodeLU[port] {
                    // print("Port: \(port), nbits: 1, node index: \(intlIndx)")


                    let extlIndx = circuit.nodeLU[port]!

                    let prtDef = PortDef(
                        port: port,
                        node: port,
                        nbits: 1,
                        intlIndx: intlIndx,
                        extlIndx: extlIndx,
                        sgmnts: []
                        )

                    oprtDefs.append(prtDef)
                    continue
                } else {
                    print("Unknown node name: \(port)")
                }
            }

            print("Unsupported object shape: \(obj)")

        case let .array(nested):
            // handle nested structure; to be done to allow hierarchical ports
            print("\(nested)")

        default:
            print("Unsupported port value: \(prt)")
        }
    }
    circuit.oPrts = oprtDefs
    // print("#outPrts: \(oprtDefs.count)")

    let aCircsVal = circDct["aCircs"]

    if let aCircsVal {

        guard case let .cmps(cmps) = aCircsVal else {
            print("aCircs is not an array")
            fatalError("Invalid circuit")
        }

        for (aindx, cmp) in cmps.enumerated() {

            let iPrts = cmp.inPorts.flatMap { port in
                inPort2Indxs(port: port, circuit: circuit)
                }

            let oPrts = cmp.outPorts.flatMap { port in
                outPort2Indxs(port: port, circuit: circuit)
                }

            let gate = Gate(
                kind: Kind(rawValue: cmp.kind)!,
                name: cmp.name,
                ninps: cmp.inPorts[0].busCount,
                index: aindx,
                circuit: circuit,
                inps: iPrts,
                outs: oPrts,
                delay: cmp.delay
                )
 
            circuit.aCircs.append(gate)
            for idx in iPrts {
                circuit.nodes[idx].nodeSinks.append(CmpRef(kind: .aCirc, index: aindx))
            }

            for idx in oPrts {
                circuit.nodes[idx].nodeDrvr = (CmpRef(kind: .aCirc, index: aindx))
            }
        }
    }

    let sCircsVal = circDct["sCircs"]

    if let sCircsVal {

        guard case let .cmps(cmps) = sCircsVal else {
            print("sCircs is not an array")
            fatalError("Invalid circuit")
        }

        for (sindx, cmp) in cmps.enumerated() {

            let iPrts = cmp.inPorts.flatMap { port in
                inPort2Indxs(port: port, circuit: circuit)
                }
            let oPrts = cmp.outPorts.flatMap { port in
                outPort2Indxs(port: port, circuit: circuit)
                }

            let knd: RegTyp
            switch cmp.kind {
            case "dpf":
                knd = .dpf
            case "dpr":
                knd = .dpr
            case "dnf":
                knd = .dnf
            case "dnr":
                knd = .dnr
            case "d0pf":
                knd = .d0pf
            case "d0pr":
                knd = .d0pr
            case "d0nf":
                knd = .d0nf
            case "d0nr":
                knd = .d0nr
            default:
                preconditionFailure("Can't happen")
            }

            let delay = 20

            let reg = Reg(
                kind: knd,
                name: cmp.name,
                ninps: cmp.inPorts.count,
                index: sindx,
                circuit: circuit,
                inps: iPrts,
                outs: oPrts,
                delay: delay
                )

            circuit.sCircs.append(reg)
            for idx in iPrts {
                circuit.nodes[idx].nodeSinks.append(CmpRef(kind: .sCirc, index: sindx))
            }

            for idx in oPrts {
                circuit.nodes[idx].nodeDrvr = (CmpRef(kind: .sCirc, index: sindx))
            }
        }
    }

    let vCircsVal = circDct["vCircs"]

    if let vCircsVal {

        guard case let .cmps(cmps) = vCircsVal else {
            print("vCircs is not an array")
            fatalError("Invalid circuit")
        }

        for (index, cmp) in cmps.enumerated() {

            let circDF = makeCircDef(cmp.kind) ?? nil
            _ = circDF
            if let def = Glbls.circDef(for: "DG_DR_3X1") {
                print("def.kind: \(def.kind)")
            }

            guard let ymlStr = try? getCircYmlStr(named: cmp.kind)
            else { fatalError("Failed to read \(cmp.kind)") }
             guard let circ = try? Circuit.make(fromSubcircYAML: ymlStr)
            else { fatalError("Failed to get circ0") }

            // let circ = Circuit(module: cmp.kind, name: cmp.name)!

            let iPrts = cmp.inPorts.map { port in
                return circ.resolveCircPort(port: port, circuit: circuit)
                }
            let oPrts = cmp.outPorts.map { port in
                return circ.resolveCircPort(port: port, circuit: circuit)
                }

            circ.kind = "verilog"
            circ.module = cmp.kind
            circ.params = cmp.params
            circ.parent = circuit
            circ.iPrts = iPrts
            circ.oPrts = oPrts

            if circ.evalOrder.isEmpty {
                initializeCmpCnts(circ)
            }

            // print("Circ ID: \(ObjectIdentifier(circ))")

            circ.index = index + circuit.cCircs.count
            circ.indexs = getIndxs(circ)
            circuit.cCircs.append(circ)
            // let index = circuit.vCircs.count

            for prtDef in iPrts {
                if prtDef.port == "VDD" || prtDef.port == "VSS" {
                    continue
                }
                circuit.nodes[prtDef.extlIndx].nodeSinks.append(CmpRef(kind: .vCirc, index: index - 1))
            }

            for (indx, prtDef) in oPrts.enumerated() {
                var extnd = circuit.nodes[prtDef.extlIndx]
                extnd.nodeDrvr = (CmpRef(kind: .vCirc, index: index - 1))
                extnd.capac += circ.delay.outcap
                let ref = CmpRef(kind: .oPrt, index: indx)
                if !circ.nodes[prtDef.intlIndx].nodeSinks.contains(ref) {
                    circ.nodes[prtDef.intlIndx].nodeSinks.append(ref)
                } else {
                    print("Ref: \(ref) has already been included in node: \(circ.nodes[prtDef.intlIndx].name)")
                }
            }
        }
    }

    let cCircsVal = circDct["cCircs"]

    if let cCircsVal {

        guard case let .cmps(cmps) = cCircsVal else {
            print("cCircs is not an array")
            fatalError("Invalid circuit")
        }

        for (index, cmp) in cmps.enumerated() {

            let circ = Circuit(module: cmp.kind, name: cmp.name)!

            let iPrts = cmp.inPorts.map { port in
                return circ.resolveCircPort(port: port, circuit: circuit)
                }
            let oPrts = cmp.outPorts.map { port in
                return circ.resolveCircPort(port: port, circuit: circuit)
                }

            circ.kind = "subcirc"
            circ.module = cmp.kind
            circ.params = cmp.params
            circ.parent =  circuit
            circ.iPrts = iPrts
            circ.oPrts = oPrts

            if circ.evalOrder.isEmpty {
                initializeCmpCnts(circ)
            }

            // print("Circ ID: \(ObjectIdentifier(circ))")

            // Fill in the hierarchy
            for i in circ.aCircs.indices {
                if !(circ.aCircs[i].circuit === circ) {
                    // print("aCirc ID: \(ObjectIdentifier(circ.aCircs[i].circuit))")
                    circ.aCircs[i].circuit = circ
                    // print("aCirc ID: \(ObjectIdentifier(circ.aCircs[i].circuit))")
                }
            }

            for i in circ.sCircs.indices {
                if !(circ.sCircs[i].circuit === circ) {
                    // print("sCirc ID: \(ObjectIdentifier(circ.sCircs[i].circuit))")
                    circ.sCircs[i].circuit = circ
                    // print("sCirc ID: \(ObjectIdentifier(circ.sCircs[i].circuit))")
                }
            }

            for child in circ.vCircs {
                if child.parent !== circ {
                    child.parent = circ
                }
            }

            circ.index = index
            circ.indexs = getIndxs(circ)
            circuit.cCircs.append(circ)
            let index = circuit.cCircs.count
            circ.parent = circuit

            for prtDef in iPrts {
                circuit.nodes[prtDef.extlIndx].nodeSinks.append(CmpRef(kind: .cCirc, index: index - 1))
                // circ.nodes[prtDef.intlIndx].nodeDrvr = CmpRef(kind: .iPrt, index: indx) // already done
            }

            for (indx, prtDef) in oPrts.enumerated() {
                var extnd = circuit.nodes[prtDef.extlIndx]
                extnd.nodeDrvr = (CmpRef(kind: .cCirc, index: index - 1))
                extnd.capac += circ.delay.outcap
                circuit.nodes[prtDef.extlIndx] = extnd
                let ref = CmpRef(kind: .oPrt, index: indx)
                if !circ.nodes[prtDef.intlIndx].nodeSinks.contains(ref) {
                    circ.nodes[prtDef.intlIndx].nodeSinks.append(ref)
                } else {
                    print("Ref: \(ref) has already been included in node: \(circ.nodes[prtDef.intlIndx].name)")
                }
            }
        }
    }

    // let circuit: Circuit = Circuit(iPrts: iprtDefs, oPrts: oprtDefs, nodes: Nodes, nodeLU: nodeLU)

    // return circuit
}

public func FillCircuit(_ circModule: String, circDct: [String: ArryVal]) -> Circuit? {

    guard let nodesVal = circDct["nodes"] else {
        print("no nodes entry")
        return nil
    }

    guard case let .nodes(nodesArray) = nodesVal else {
        print("nodes entry is not .nodes")
        return nil
    }

    var nodeLU: [String:Int] = [:]
    var Nodes: [Nod] = []

    for (i, node) in nodesArray.enumerated() {
        switch node {
        case .name(let s):
            // print("plain name: \(s)")
            nodeLU[s] = i
            Nodes.append(Nod(s))

        case .def(let def):
            // print("def name: \(def.name), nbits: \(def.nbits)")
            nodeLU[def.name] = i
            Nodes.append(Nod(def.name))
        }
    }

    let TopCircuit: Circuit = Circuit(nodes: Nodes, nodeLU: nodeLU, cmpRefs: [], evalOrder: [])

    let defs: [NodeDef] = nodesArray.compactMap { node in
        if case let .def(def) = node { return def }
        return nil
    }

    let allNames: [String] = nodesArray.map { node in
        switch node {
        case .name(let s):         return s
        case .def(let def):        return def.name
        }
    }

    dump(defs)
    dump(allNames)

    return TopCircuit
}

public func getInpSpcsStr(named fileName: String) throws -> String {
    let url = Glbls.simSpcsDir
        .appendingPathComponent(fileName)
        .appendingPathExtension("yml")

    return try String(contentsOf: url, encoding: .utf8)
}

public func getCircYmlStr(named fileName: String) throws -> String {
    let url = Glbls.circLibDir
        .appendingPathComponent(fileName)
        .appendingPathExtension("yml")

    return try String(contentsOf: url, encoding: .utf8)
}

public func GetCircDict(_ circModule: String) -> Circuit? {
    let ymlStr = try! getCircYmlStr(named: circModule)

    guard let dict = yamlLoad(ymlStr) else {
        print("Failed to load YAML for circuit \(circModule), ymlStr: \(ymlStr)")
        return nil
    }

    var circuit = Circuit(circModule)

    if let built = FillCircuit(circModule, circDct: dict) {
        circuit = built
    } else {
        print("Warning: FillCircuit returned nil; using empty Circuit()")
    }
    return circuit
}
