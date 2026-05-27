import Foundation
import Yams
import SharedTypes

public func yamlLoad(_ yamlString: String) -> [String: ArryVal]? {
    var parsed: [String: Any] = [:]

    do {
        guard let loaded = try Yams.load(yaml: yamlString) as? [String: Any]
        else {
            print("YAML parsing failed")
            return [:]
        }
        parsed = loaded
    } catch {
        print("Failed to parse YAML: \(error)")
    }

    var result: [String: ArryVal] = [:]

    if let prms = parsed["params"] as? [String: Any] {
        print("We caught a 'params': \(prms)")
        var params: [Parm] = []
        var vl: ParmEnum
        for (k, v) in prms {
            switch v {
                case let s as String:
                   vl = .str(s)
                case let int as Int:
                    vl = .int(int)
                default:
                    print("Ignoring unsupported param \(k): \(type(of: v))")
                    continue
                    
            }
            params.append(Parm(name: k, value: vl))
        }
        result["params"] = .prms(params)
    }

    if let sens = parsed["sense"] as? [String: Any] {
        print("We caught a 'sens': \(sens)")

        if let edgeStr = sens["edge"] as? String,
           let portStr = sens["port"] as? String {

            let edg: SEdge = edgeStr == "rise" ? .rise : .fall
            let sns = Sens(port: portStr, edge: edg)

            result["sense"] = .sens(sns)
        } else {
            print("Invalid sense object: \(sens)")
            // just ignore; no return
        }
    }

    // make sure we have a ["nodes": [Any]] or abort parsing cCircs
    guard let nodesAny = parsed["nodes"] as? [Any] else {
        print("YAML: cCircs nodes missing; skipping")
        return nil
    }

    // We have ["nodes": [Any]] so now make sure Any matches NodeEnum
    // NodeEnum is either a single String or an object having [name: String, nbits: Int]
    var nodes: [NodeEnum] = []
    for nd in nodesAny {
        // Case 1: nd is just a String
        if let nodeNm = nd as? String {
            nodes.append(.name(nodeNm))
            continue
        }

        // Case 2: nd is a [String: Any] with name + nbits
        guard let obj = nd as? [String: Any] else {
            print("YAML: cCircs nodes entry is not an object or string; skipping")
            continue
        }

        guard let name  = obj["name"]  as? String,
              let nbits = obj["nbits"] as? Int else {
            print("YAML: cCircs has invalid node object; skipping")
            continue
        }

        nodes.append(.def(NodeDef(name: name, nbits: nbits)))
    }
    result["nodes"] = .nodes(nodes)

    if let sCircsAny = parsed["sCircs"] as? [Any] {
        var sCircs: [Cmp] = []

        for objAny in sCircsAny {
            guard let obj = objAny as? [String: Any] else {
                print("YAML: sCircs element is not a mapping; skipping")
                continue
            }

            guard let name = obj["name"] as? String,
                  let kind = obj["kind"] as? String else {
                print("YAML: sCircs element missing name/kind; skipping")
                continue
            }

            var params: [Param] = []
            if let paramsAny = obj["params"] as? [Any] {
                for pAny in paramsAny {
                    guard let p = pAny as? [String: Any],
                        let name = p["name"] as? String,
                        let value = p["value"] as? Int else {
                        print("YAML: invalid params entry; skipping")
                        continue
                    }
                    params.append(Param(name: name, value: value))
                }
            } else {
                print("YAML: sCircs doesn't contain params")
                // continue
            }

            guard let inPrtsAny = obj["inPrts"] as? [Any] else {
                print("YAML: sCircs element missing inPrts; skipping")
                continue
            }

            var inPorts: [Port] = []

            // Try to interpret this inPrts as a BusArray

            let rawArray = inPrtsAny  // already [Any]

            let elems: [BusElem] = rawArray.compactMap { any in
                if let name = any as? String {
                    return .bus(name)
                }
                if let pair = any as? [Any],
                   pair.count == 2,
                   let name = pair[0] as? String,
                   let idx  = pair[1] as? Int {
                    return .bit((name, idx))
                }
                if let triple = any as? [Any],
                   triple.count == 3,
                   let name = triple[0] as? String,
                   let lo   = triple[1] as? Int,
                   let hi   = triple[2] as? Int {
                    return .slc((name, lo, hi))
                }
                return nil
            }

            if !elems.isEmpty {
                inPorts.append(.bus(elems))
                // if this Cmp’s inPrts is *only* a bus form, you can return/continue here
            } else {
                print("YAML: falling back to node/segmented parse")
                // fall through to your existing per-entry parsing if desired
            }

            for pAny in inPrtsAny {
                guard let p = pAny as? [String: Any],
                      let port = p["port"] as? String
                else {
                    print("YAML: invalid inPrts entry; skipping")
                    continue
                }

                if let nodeName = p["node"] as? String {
                    inPorts.append(.node(port: port, node: .name(nodeName)))
                    continue
                }

                if let nodeDict = p["node"] as? [String: Any],
                   let supply = nodeDict["supply"] as? Int {
                    inPorts.append(.node(port: port, node: .supply(supply)))
                    continue
                }

                if let segArr = p["segments"] as? [[String: Any]] {
                    let segments: [Sgmnt] = segArr.compactMap { sAny in
                        guard let node = sAny["node"] as? String,
                            let w = sAny["width"] as? [Int],
                            w.count == 2
                        else { return nil }
                        return Sgmnt(node: node, width: (w[0], w[1]))
                    }

                    if !segments.isEmpty {
                        inPorts.append(.segmented(port: port, segments: segments))
                        continue
                    }
                }
                print("YAML: invalid node entry; skipping")
            }

            var outPort: OutPort
            if let val = obj["outPrts"] {
                print("outPrts dynamic type:", type(of: val))
            }
            if let single = obj["outPrts"] as? String {
                // Case 1: scalar, e.g. "T1"
                outPort = .node(single)
            } else if let arr = obj["outPrts"] as? [String] {
                // Case 2: array, e.g. ["T1", "T2"]
                outPort = .arry(arr)
            } else if let arr = obj["outPrts"] as? [[String: Any]],
                    let oprt = arr.first {
                // Case 3: array of {port,node} mappings; take the first
                guard let port = oprt["port"] as? String,
                    let node = oprt["node"] as? String
                else {
                    print("YAML: invalid first outPrts element: \(oprt)")
                    continue
                }
                outPort = .port(port: port, node: node)
            } else {
                print("YAML: sCircs element missing or invalid outPrts; skipping")
                continue
            }

            sCircs.append(Cmp(name: name, kind: kind, params: params, inPorts: inPorts, outPorts: [outPort], delay: 20))
            result["sCircs"] = .cmps(sCircs)
        }
    }

    if let aCircsAny = parsed["aCircs"] as? [Any] {
        var aCircs: [Cmp] = []

        for objAny in aCircsAny {
            guard let obj = objAny as? [String: Any] else {
                print("YAML: aCircs element is not a mapping; skipping")
                continue
            }

            guard let name = obj["name"] as? String,
                  let kind = obj["kind"] as? String else {
                print("YAML: aCircs element missing name/kind; skipping")
                continue
            }

            var params: [Param] = []
            if let paramsAny = obj["params"] as? [Any] {
                for pAny in paramsAny {
                    guard let p = pAny as? [String: Any],
                        let name = p["name"] as? String,
                        let value = p["value"] as? Int else {
                        print("YAML: invalid params entry; skipping")
                        continue
                    }
                    params.append(Param(name: name, value: value))
                }
            } else {
                print("YAML: aCircs doesn't contain params")
                // continue
            }

            var delay: Int = 12
            if let delayAny = obj["delay"] as? Int {
                delay = delayAny
            } else {
                print("YAML: aCircs doesn't contain delay")
                // continue
            }

            guard let inPrtsAny = obj["inPrts"] as? [Any] else {
                print("YAML: aCircs element missing inPrts; skipping")
                continue
            }

            var inPorts: [Port] = []

            // Try to interpret this inPrts as a BusArray

            let rawArray = inPrtsAny  // already [Any]

            let elems: [BusElem] = rawArray.compactMap { any in
                if let name = any as? String {
                    return .bus(name)
                }
                if let pair = any as? [Any],
                   pair.count == 2,
                   let name = pair[0] as? String,
                   let idx  = pair[1] as? Int {
                    return .bit((name, idx))
                }
                if let triple = any as? [Any],
                   triple.count == 3,
                   let name = triple[0] as? String,
                   let lo   = triple[1] as? Int,
                   let hi   = triple[2] as? Int {
                    return .slc((name, lo, hi))
                }
                return nil
            }

            if !elems.isEmpty {
                inPorts.append(.bus(elems))
                // if this Cmp’s inPrts is *only* a bus form, you can return/continue here
            } else {
                print("YAML: falling back to node/segmented parse")
                // fall through to your existing per-entry parsing if desired
            }

            for pAny in inPrtsAny {
                guard let p = pAny as? [String: Any],
                      let port = p["port"] as? String
                else {
                    print("YAML: invalid inPrts entry; skipping")
                    continue
                }

                if let nodeName = p["node"] as? String {
                    inPorts.append(.node(port: port, node: .name(nodeName)))
                    continue
                }

                if let nodeDict = p["node"] as? [String: Any],
                   let supply = nodeDict["supply"] as? Int {
                    inPorts.append(.node(port: port, node: .supply(supply)))
                    continue
                }

                if let segArr = p["segments"] as? [[String: Any]] {
                    let segments: [Sgmnt] = segArr.compactMap { sAny in
                        guard let node = sAny["node"] as? String,
                            let w = sAny["width"] as? [Int],
                            w.count == 2
                        else { return nil }
                        return Sgmnt(node: node, width: (w[0], w[1]))
                    }

                    if !segments.isEmpty {
                        inPorts.append(.segmented(port: port, segments: segments))
                        continue
                    }
                }
                print("YAML: invalid node entry; skipping")
            }


            var outPort: OutPort
            if let val = obj["outPrts"] {
                print("outPrts dynamic type:", type(of: val))
            }
            if let single = obj["outPrts"] as? String {
                // Case 1: scalar, e.g. "T1"
                outPort = .node(single)
            } else if let arr = obj["outPrts"] as? [String] {
                // Case 2: array, e.g. ["T1", "T2"]
                outPort = .arry(arr)
            } else if let arr = obj["outPrts"] as? [[String: Any]],
                    let oprt = arr.first {
                // Case 3: array of {port,node} mappings; take the first
                guard let port = oprt["port"] as? String,
                    let node = oprt["node"] as? String
                else {
                    print("YAML: invalid first outPrts element: \(oprt)")
                    continue
                }
                outPort = .port(port: port, node: node)
            } else {
                print("YAML: aCircs element missing or invalid outPrts; skipping")
                continue
            }
            // Note: aCircs have a single outPort although it can multiple bits
            aCircs.append(Cmp(name: name, kind: kind, params: params, inPorts: inPorts, outPorts: [outPort], delay: delay))
            result["aCircs"] = .cmps(aCircs)
        }
    }

    if let vCircsAny = parsed["vCircs"] as? [Any] {
        var vCircs: [Cmp] = []

        for objAny in vCircsAny {
            guard let obj = objAny as? [String: Any] else {
                print("YAML: vCircs element is not a mapping; skipping")
                continue
            }

            guard let name = obj["name"] as? String,
                  let kind = obj["kind"] as? String else {
                print("YAML: vCircs element missing name/kind; skipping")
                continue
            }

            var params: [Param] = []
            if let paramsAny = obj["params"] as? [Any] {
                for pAny in paramsAny {
                    guard let p = pAny as? [String: Any],
                        let name = p["name"] as? String,
                        let value = p["value"] as? Int else {
                        print("YAML: invalid params entry; skipping")
                        continue
                    }
                    params.append(Param(name: name, value: value))
                }
            } else {
                print("YAML: vCircs doesn't contain params")
                // continue
            }

            guard let inPrtsAny = obj["inPrts"] as? [Any] else {
                print("YAML: vCircs element missing inPrts; skipping")
                continue
            }

            var inPorts: [Port] = []
            for pAny in inPrtsAny {
                guard let p = pAny as? [String: Any],
                      let port = p["port"] as? String
                else {
                    print("YAML: invalid inPrts entry; skipping")
                    continue
                }

                if let nodeName = p["node"] as? String {
                    inPorts.append(.node(port: port, node: .name(nodeName)))
                    continue
                }

                if let val = p["node"] as? Int {
                    inPorts.append(.node(port: port, node: .supply(val)))
                    continue
                }

                if let nodeDict = p["node"] as? [String: Any],
                   let supply = nodeDict["supply"] as? Int {
                    inPorts.append(.node(port: port, node: .supply(supply)))
                    continue
                }

                if let segArr = p["segments"] as? [[String: Any]] {
                    let segments: [Sgmnt] = segArr.compactMap { sAny in
                        guard let node = sAny["node"] as? String,
                            let w = sAny["width"] as? [Int],
                            w.count == 2
                        else { return nil }
                        return Sgmnt(node: node, width: (w[0], w[1]))
                    }

                    if !segments.isEmpty {
                        inPorts.append(.segmented(port: port, segments: segments))
                        continue
                    }
                }
                print("YAML: invalid node entry; skipping")
            }

            var outPort: OutPort
            var outPorts: [OutPort] = []

            if let single = obj["outPrts"] as? String {
                // Case 1: scalar, e.g. "T1"
                outPort = .node(single)
                vCircs.append(Cmp(name: name, kind: kind, params: params, inPorts: inPorts, outPorts: [outPort], delay: 40))
                continue
            } else if let arr = obj["outPrts"] as? [String] {
                // Case 2: array, e.g. ["T1", "T2"]
                outPort = .arry(arr)
                vCircs.append(Cmp(name: name, kind: kind, params: params, inPorts: inPorts, outPorts: [outPort], delay: 40))
                continue
            } else {
                print("YAML: vCircs doesn't have outPrts as simple Bus names")
                // continue
            }

            guard let outPrtsAny = obj["outPrts"] as? [Any] else {
                print("YAML: vCircs element missing outPrts; skipping")
                continue
            }

            for pAny in outPrtsAny {
                guard let p = pAny as? [String: Any],
                      let port = p["port"] as? String
                else {
                    print("YAML: invalid inPrts entry; skipping")
                    continue
                }

                if let nodeName = p["node"] as? String {
                    outPorts.append(.port(port: port, node: nodeName))
                    continue
                }

                print("YAML: outPorts not parsed for vCirc; skipping")
            }

            vCircs.append(Cmp(name: name, kind: kind, params: params, inPorts: inPorts, outPorts: outPorts, delay: 40))
        }
        result["vCircs"] = .cmps(vCircs)
    }

    if let cCircsAny = parsed["cCircs"] as? [Any] {
        var cCircs: [Cmp] = []

        for objAny in cCircsAny {
            guard let obj = objAny as? [String: Any] else {
                print("YAML: cCircs element is not a mapping; skipping")
                continue
            }

            guard let name = obj["name"] as? String,
                  let kind = obj["kind"] as? String else {
                print("YAML: cCircs element missing name/kind; skipping")
                continue
            }

            var params: [Param] = []
            if let paramsAny = obj["params"] as? [Any] {
                for pAny in paramsAny {
                    guard let p = pAny as? [String: Any],
                        let name = p["name"] as? String,
                        let value = p["value"] as? Int else {
                        print("YAML: invalid params entry; skipping")
                        continue
                    }
                    params.append(Param(name: name, value: value))
                }
            } else {
                print("YAML: cCircs doesn't contain params")
                // continue
            }

            guard let inPrtsAny = obj["inPrts"] as? [Any] else {
                print("YAML: cCircs element missing inPrts; skipping")
                continue
            }

            var inPorts: [Port] = []
            for pAny in inPrtsAny {
                guard let p = pAny as? [String: Any],
                      let port = p["port"] as? String
                else {
                    print("YAML: invalid inPrts entry; skipping")
                    continue
                }

                if let nodeName = p["node"] as? String {
                    inPorts.append(.node(port: port, node: .name(nodeName)))
                    continue
                }

                if let nodeDict = p["node"] as? [String: Any],
                   let supply = nodeDict["supply"] as? Int {
                    inPorts.append(.node(port: port, node: .supply(supply)))
                    continue
                }

                if let segArr = p["segments"] as? [[String: Any]] {
                    let segments: [Sgmnt] = segArr.compactMap { sAny in
                        guard let node = sAny["node"] as? String,
                            let w = sAny["width"] as? [Int],
                            w.count == 2
                        else { return nil }
                        return Sgmnt(node: node, width: (w[0], w[1]))
                    }

                    if !segments.isEmpty {
                        inPorts.append(.segmented(port: port, segments: segments))
                        continue
                    }
                }
                print("YAML: invalid node entry; skipping")
            }

            var outPort: OutPort
            var outPorts: [OutPort] = []

            if let single = obj["outPrts"] as? String {
                // Case 1: scalar, e.g. "T1"
                outPort = .node(single)
                cCircs.append(Cmp(name: name, kind: kind, params: params, inPorts: inPorts, outPorts: [outPort], delay: 40))
                continue
            } else if let arr = obj["outPrts"] as? [String] {
                // Case 2: array, e.g. ["T1", "T2"]
                outPort = .arry(arr)
                cCircs.append(Cmp(name: name, kind: kind, params: params, inPorts: inPorts, outPorts: [outPort], delay: 40))
                continue
            } else {
                print("YAML: cCircs doesn't have outPrts as simple Bus names")
                // continue
            }

            guard let outPrtsAny = obj["outPrts"] as? [Any] else {
                print("YAML: cCircs element missing outPrts; skipping")
                continue
            }

            for pAny in outPrtsAny {
                guard let p = pAny as? [String: Any],
                      let port = p["port"] as? String
                else {
                    print("YAML: invalid inPrts entry; skipping")
                    continue
                }

                if let nodeName = p["node"] as? String {
                    outPorts.append(.port(port: port, node: nodeName))
                    continue
                }

                print("YAML: outPorts not parsed for cCirc; skipping")
            }

            cCircs.append(Cmp(name: name, kind: kind, params: params, inPorts: inPorts, outPorts: outPorts, delay: 40))
        }
        result["cCircs"] = .cmps(cCircs)
    }

    for (k, v) in parsed {
    if k == "nodes" || k == "aCircs" || k == "sCircs" || k == "vCircs" || k == "cCircs" {
        continue
    }
        switch v {
        case let s as String:
            // Simple scalar string
            result[k] = .str(s)

        case let arr as [Any]:
            // Empty array: treat as empty
            guard let first = arr.first else {
                print("YAML: empty array for key \(k); storing empty list")
                result[k] = .arry([])
                continue
            }

            // First element must be representable as ArryElem
            guard let firstWrapped = ArryElem(from: first) else {
                print("YAML: skipping key \(k) in parsing loop")
                continue
            }

            // Enforce homogeneity; on mismatch, skip key or fall back
            var elements: [ArryElem] = [firstWrapped]
            var heterogeneous = false

            for e in arr.dropFirst() {
                guard let wrapped = ArryElem(from: e) else {
                    print("YAML: invalid element in array for key \(k); skipping key")
                    heterogeneous = true
                    break
                }

                if type(of: wrapped) != type(of: firstWrapped) {
                    print("YAML: heterogeneous array for key \(k); skipping key")
                    heterogeneous = true
                    break
                }

                elements.append(wrapped)
            }

            if heterogeneous {
                // Decide policy: skip, or store empty/default
                // Here: skip the key entirely
                continue
            }

            result[k] = .arry(elements)

        default:
            // Unsupported scalar / mapping type
            print("YAML: unsupported value type for key \(k); skipping key")
            continue
        }
    }
    return result
}