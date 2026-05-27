import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

func dbPrnt<T>(_ label: String, _ value: T?) {
    print("\(label): \(String(describing: value))")
}

extension Dictionary {
    func gt(_ key: Key) -> Value { self[key]! }
}

let inspectFlNm: @Sendable (String) -> (URL, URL, String, String) = {
    ( path ) in

    let url = URL(fileURLWithPath: path)
    let parentDir = url.deletingLastPathComponent() // URL("/dir")
    let fileName = url.lastPathComponent       // "file.txt"
    let suffix = url.pathExtension          // "txt"
    return (url, parentDir, fileName, suffix)

}

let incCnt: @Sendable (String, [String: Int]) -> [String: Int] = { (nd, ndsCnt) in
    var dict = ndsCnt
    dict[nd] = (dict[nd] ?? 0) + 1
    return dict
}

/**
 * an extension that first checks if element is in the array, and if
 * not appends it.
 *
 * - Parameter element: the element to append if its not in the array
 */
extension Array where Element: Equatable {
    mutating func appendIfNotExists(_ element: Element) {
        if !self.contains(element) {
            self.append(element)
        }
    }
}

/**
 * simFilter simulates a filter defined by a yaml file. Before it is called
 * the order of updates must be determined.
 *
 * - Parameter input: an array of Int values that is the input to the filter
 * - Parmaeter oprDct: a dictionary that defines the operation for producing every
 *   node value
 * - Parameter nds: a dictionary; each key is a node name, and each value is a TwoCmplt
 * - Parmaeter coeffs: a dictionary specifying the coefficient values as obtained from
 *   the yaml file
 * - Parameter execQue: an array of tuples ordered so execution proceeds according to 
 *   the first value of the tuple which a node name. The second value of the tuple is an
 *   array of nodes the first value depends on. This array is not used in this function
 *   and may be removed in the future.
 */
func simFilter(
    input: [Int],
    oprDct: [String: [String]],
    nds: inout [String: TwoCmplt],
    coeffs: [String: Int],
    execQue: [(String, [String])] ) {

    let defaultVal: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var inits: [(String, String)] = []
    let regex = /X(\d+)/

    for (key, value) in coeffs {
        nds[key] = TwoCmplt(value, nbits: 20, signed: true)
    }

    var ndNm: String
    nds["IN"] = TwoCmplt(input[0], nbits: 20, signed: true)
    for nd in execQue {
        ndNm = nd.0
        if let match = (ndNm).wholeMatch(of: regex) {
            let inNd = "XI\(match.1)"
            nds[ndNm] = (nds[inNd] ?? nil)
            inits.append((ndNm, inNd))
        } else {
            if !(ndNm == "IN") {
                break
            }
        }
    }

    for ndSpc in execQue {
        nds[ndSpc.0] = TwoCmplt(0, nbits: 20, signed: true)
    }

    var value3: TwoCmplt? = nil
    let outNd: [String] = oprDct["OUT", default: []]
    if !outNd.isEmpty {
        print("outNd: \(outNd)")
    }

    let N: Int = input.count
    var Out: [Int] = Array(repeating: 0, count: N)
    var States: [(Int, Int, Int)] = Array(repeating: ( 0, 0, 0), count: N)

    for i in 0..<N {
        nds["IN"] = TwoCmplt(input[i], nbits: 20, signed: true)
        for nd in inits {
            nds[nd.0] = nds[nd.1]
        }
        for nd in execQue {
            if nd.1.isEmpty {
                continue
            }
            let ndNm: String = nd.0

            var value1: TwoCmplt? = nil
            var value2: TwoCmplt? = nil

            let expr = oprDct[ndNm] ?? []
            if expr.count == 3 {
                value1 = nds[expr[1]]
                value2 = nds[expr[2]]
            } else if expr.count == 2 {
                value1 = nds[expr[1]]
                value2 = nil
            }

            switch expr[0] {
            case "+":
                nds[ndNm] = (value1 ?? defaultVal) + (value2 ?? defaultVal)
            case "-":
                nds[ndNm] = (value1 ?? defaultVal) - (value2 ?? defaultVal)
            case "x":
                nds[ndNm] = TwoCmplt.multN(lhs: (value1 ?? defaultVal), rhs: (value2 ?? defaultVal), rshift: 16)
            case "<=":
                nds[ndNm] = value1 ?? defaultVal
            case ">>":
                nds[ndNm] = (value1 ?? defaultVal) >> (value2 ?? defaultVal).value
            default:
                print("Operator not recognized")

            }
        }

        value3 = nds[outNd[1]]
        let outVal = value3?.toInt() ?? 0
        print("outVal: \(outVal)")

        Out[i] = nds.gt(outNd[1]).toInt()

        States[i] = ((nds.gt(inits[0].0)).toInt(),
                        nds.gt(inits[1].0).toInt(),
                        nds.gt(inits[2].0).toInt())

        print("i: \(i)")
        ()
    }

    print("Input.cnt: \(input.count), nds.count: \(nds.count)")
    dbPrnt("Out: ", nds[oprDct["OUT", default: []][1]])

    let path = "/home/Dropbox/programming/Swift/PlotResponse/fltr3d.dat"
    withFile(path, mode: "w") { fp in
        for val in Out {
            // Write the string and add a newline
            let line = "\(String(format: "%d", val))\n"
            fputs(line, fp)
        }
    }

    let path2 = "/home/Dropbox/programming/Swift/PlotResponse/states_3d.dat"
    withFile(path2, mode: "w") { fp in
        for val in States {
            // Write the string and add a newline
            let line = "\(String(format: "%d", val.0)) \(String(format: "%d", val.1)) \(String(format: "%d", val.2))\n"
            fputs(line, fp)
        }
    }
}

/**
 * A Third Order Filter with a Finite Zeror. F-3dB = 0.16*k1 (approximately)
 */
func Filter3D (_ fileNm: String, nsmpls: Int) {
    var In: [Int] = Array(repeating: 0, count: 1024)

    var yamlString: String = ""
    var oprDct: [String: [String]] = [:]
    var nodeKeys: [String] = []
    var nds: [String: TwoCmplt] = [:]
    var outNds: [String: [String]] = [:]
    var sortQue: [(String, [String])] = []
    var execQue: [(String, [String])] = []
    var coeffs: [String: Int] = [:]

    In[0] = (1<<18)
    nds["IN"] = TwoCmplt(In[0], nbits: 20, signed: true)

    do {
        yamlString = try String(contentsOfFile: fileNm, encoding: .utf8)
        print(yamlString)
    } catch {
        print("Could not read YAML file at \(fileNm): \(error)")
    }

    do {
        let parsed = try Yams.load(yaml: yamlString) as? [String: Any]
        for (key, value) in parsed ?? [:] {
            if let arrayValue = value as? [String] {
                oprDct[key] = arrayValue
                nodeKeys.append(key)
            } else if let dictValue = value as? [String: Int] {
                for (innerKey, innerArray) in dictValue {
                    coeffs[innerKey] = innerArray
                }
            } else {
                print("value not parsed: \(value)")
            }
        }
    } catch {
        print("Failed to parse YAML: \(error)")
    }

    /*
    do {
        if let parsed = try Yams.load(yaml: yamlString) as? [String: [String]] {
            oprDct = parsed
            nodeKeys = Array(oprDct.keys)
        } else {
            print("YAML root not a [String: [String]] dictionary.")
        }
    } catch {
        print("Failed to parse YAML: \(error)")
    }
    */

    var nodeCnt = Dictionary(uniqueKeysWithValues: nodeKeys.map { ($0, 0) })
    nodeCnt["OUT"] = nil

    var nodeHds: [String: [String]] = [:]
    for (nd, arry) in oprDct {
        if nd == "OUT" {
            continue
        }

        if arry[0] == "x" {
            if outNds[arry[1]] != nil {
                outNds[arry[1]]?.append(nd)
            } else {
                outNds[arry[1]] = [nd]
            }
            nodeCnt[nd] = 1
        } else if arry[0] == "<=" {
            nodeHds[arry[1], default: []].append(nd)
        } else {
            // outNds[] are the nodes that nd is dependent on 
            if outNds[arry[1]] != nil {
                outNds[arry[1]]?.append(nd)
            } else {
                outNds[arry[1]] = [nd]
                print("outNds: \(outNds)")
            }
            if outNds[arry[2]] != nil {
                outNds[arry[2]]?.append(nd)
           } else {
                outNds[arry[2]] = [nd]
            }
            nodeCnt[nd] = 2
        }
    }
    nodeCnt["IN"] = 0

    nodeKeys = Array(oprDct.keys)

    for key in nodeKeys {
        nodeHds[key] = []
    }

    for nd in outNds {
        for ancestor in nd.1 {
            nodeHds[ancestor, default: []].appendIfNotExists(nd.0)
        }
    }

    for key in nodeKeys {
        if nodeCnt[key] == nil {
            nodeCnt[key] = 0
        }
    }

    /*
    for node in nodeKeys {
        switch node.first {
        case "V":
            print("\(node) starts with V")
            varNds[node] = TwoCmplt(0, nbits: 20, signed: true)
            nds[node] = TwoCmplt(0, nbits: 20, signed: true)
        case "X":
            print("\(node) starts with X")
            dlyNds[node] = TwoCmplt(0, nbits: 20, signed: true)
            nds[node] = TwoCmplt(0, nbits: 20, signed: true)
        case "O":
            print("\(node) starts with O")
            out = oprDct[node]![1]
            print("out: \(out)")
        default:
            print("\(node) starts with something else")
        }
    }
    */

    // Initialize sortQue

    for (key, _) in outNds {
        if let count = nodeCnt[key] {
            if count == 0 {
                sortQue.append((key, nodeHds[key] ?? []))
            }
        }
    }

    print("sortQue: \(sortQue)")

    while !sortQue.isEmpty {
        let nd = sortQue.removeFirst()
        execQue.append(nd)
        var allZero = true
        for targ in (outNds[nd.0] ?? []) {
            if let count = nodeCnt[targ], count > 0 {
                nodeCnt[targ] = count - 1
            }
            if nodeCnt[targ] == 0 {
                let hd = (targ, nodeHds[targ] ?? [])
                sortQue.append(hd)
            } else {
                allZero = false
            }
        }
        print( "allZero: \(allZero)")

        // print("Hello")
    }
    // let coeffs: [String: Int] = ["k1": 0x4000]
    simFilter(input: In, oprDct: oprDct, nds: &nds, coeffs: coeffs, execQue: execQue)
}

@main
struct RunFilter3B {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            Filter3D("/home/Dropbox/programming/Swift/Filters/filt3b.yml", nsmpls: 1024)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
