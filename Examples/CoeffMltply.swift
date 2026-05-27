import TwosCmplt
import Glbls
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

let incCnt: @Sendable (String, [String: Int]) -> [String: Int] = { (nd, ndsCnt) in
    var dict = ndsCnt
    dict[nd] = (dict[nd] ?? 0) + 1
    return dict
}

extension Array where Element: Equatable {
    mutating func appendIfNotExists(_ element: Element) {
        if !self.contains(element) {
            self.append(element)
        }
    }
}

/**
 * A simple example of a second order oscillator using the Fixed Coefficient Multiplier
 *
 * - Parameter coeff: The coeff specifies the multiplication constant. It is a fraction between 0
 *   and 1. For a 16-bit signal path, the muliplication constant is taken coeff = K*65536 (i.e. 1<<16).
 *   The equation governing the frequency of oscillation is K = 2*sin(pi*f0) where f0 is a fraction; for
 *   example, if the oscillation period 16 clock cycles, take f0 = 1/16.
 */
func SimOsc (_ coeff: Int) {
    var M0: CoeffMlt = CoeffMlt(0x0, nbits: 20)
    var coeff: TwoCmplt = TwoCmplt(coeff, nbits: 20)
    let Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024 )
    var X0: TwoCmplt = TwoCmplt((1<<15) - 1, nbits: 20, signed: true)
    var XI0: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var X1: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var XI1: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    // var Cs: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    // var Sn: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    let F0: Double = 1.00/16.0
    var cs: Double
    var sn: Double
    // let deltPhi: Double = -Double.pi*0.0

    var deltPhi: Double = -Double.pi*0.37506

    var rl1 = 0.0, rl2 = 0.0, rl3 = 0.0
    var qd1 = 0.0, qd2 = 0.0, qd3 = 0.0
    var deltaCoeff: Int
    for i in 0..<0x10000 {

        // cs = 32767.0 * cos(Double(i)*2*Double.pi*F0 + deltPhi)
        // sn = 32767.0 * sin(Double(i)*2*Double.pi*F0 + deltPhi)
        cs = cos(Double(i)*2*Double.pi*F0)
        sn = sin(Double(i)*2*Double.pi*F0)
        M0.coeffUpdate(coeff)
        XI1 = X1 + X0 * M0
        XI0 = X0 - XI1 * M0
        X0 = XI0
        X1 = XI1
        // Out[i] = X0
        print("i: \(i), X0: \(X0.toInt()), X1: \(X1.toInt()), sync: \(M0.sync)")
        print("i: \(i), cs: \(String(format: "%7.5f", cs)), sn: \(String(format: "%7.5f", sn))")
        if i == 240 {
            M0.coeff = TwoCmplt(0x63e4, nbits: 20)
        }

        rl1 = (X0.toInt() > 0) ? rl1 + cs : rl1 - cs
        rl2 = (X1.toInt() > 0) ? rl2 + sn : rl2 - sn
        rl3 = (rl1 - rl2)/pow(2.0, 28)
        qd1 = (X0.toInt() > 0) ? qd1 + sn : qd1 - sn
        qd2 = (X1.toInt() > 0) ? qd2 + cs : qd2 - cs
        qd3 = (qd1 + qd2)/pow(2.0, 28)
        if i % 16 == 0 {
            print("i: \(i), rl3: \(String(format: "%7.5f", rl3)), qd3: \(String(format: "%7.5f", qd3)), coeff: \(coeff.toInt()), deltPhi: \(deltPhi)")
        }

        print("i: \(i), rl3: \(String(format: "%7.5f", rl3)), qd3: \(String(format: "%7.5f", qd3)), coeff: \(coeff.toInt()), deltPhi: \(deltPhi)")

        deltPhi = deltPhi + 0.0*1e-12*qd3
        deltaCoeff = Int(2.0e-12*qd3*pow(2,4.0).rounded())
        coeff = coeff + TwoCmplt(deltaCoeff, nbits: 20)

        ()
    }
    _ = Out
    print("\(Out[511])")
    ()
}

/**
 * A Third Order Filter with only shifts. F-3dB = 0.165*k1 (approximately)
 */
func SimFltr3A (_ coeff: Int){

    let k1Shift = 2
    var In: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var States: [(Int, Int, Int)] = Array(repeating: ( 0, 0, 0), count: 1024)
    var XI: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 3)
    var X: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 3)
    var V: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    /*
    for i in 1..<1024 {
        In[i].value = (1<<14)
    }
    */
    // let F0: Double = 1.00/128
    // var sn: Double
    // var Sn: Int
    In[0].value = (1<<14)
    for i in 0..<1024 {
        V[0] = In[i] - X[0]
        V[1] = V[0] >> k1Shift

        XI[0] = V[1] + X[0]

        V[2] = X[0] - X[2]
        V[3] = V[2]  >> k1Shift
        XI[1] = X[1] + V[3]

        V[4] = XI[1] - X[2]
        V[5] = V[4] >> k1Shift

        XI[2] = X[2] + V[5]

        Out[i] = X[2]
        X[0] = XI[0]
        X[1] = XI[1]
        X[2] = XI[2]

        States[i] = (X[0].toInt(), X[1].toInt(), X[2].toInt())
    }
    print("k1Shift: \(k1Shift)")

    let path = "/home/Dropbox/programming/Swift/TwosCmplt/tools/output.dat"

    let fp = fopen(path, "w")
    if fp != nil {
        for val in Out {
            // Write the string and add a newline
            let line = "\(String(format: "%d", val.toInt()))\n"
            fputs(line, fp)
        }
        fclose(fp)
    } else {
        print("Error opening file for writing.")
    }

    let path2 = "/home/Dropbox/programming/Swift/TwosCmplt/tools/states.dat"

    let fp2 = fopen(path2, "w")
    if fp2 != nil {
        for val in States {
            // Write the string and add a newline
            let line = "\(String(format: "%d", val.0)) \(String(format: "%d", val.1)) \(String(format: "%d", val.2))\n"
            fputs(line, fp)
        }
        fclose(fp2)
    } else {
        print("Error opening file for writing.")
    }
}

/**
 * A Third Order Filter with a Finite Zeror. F-3dB = 0.16*k1 (approximately)
 * Fzero = 2.8*F-3dB
 */
func SimFltr3B (_ coeff: Int){

    let k1Shift = 2
    let k2Shift = (0, 3)
    let k3Shift = 3
    var In: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var XI: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 3)
    var X: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 3)
    var V: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 7)
    /*
    for i in 1..<1024 {
        In[i].value = (1<<14)
    }
    */
    // let F0: Double = 1.00/128
    // var sn: Double
    // var Sn: Int
    In[0].value = (1<<14)
    for i in 0..<1024 {
        // Sn = Int((32767.0 * sin(Double(i)*2*Double.pi*F0)).rounded())
        V[0] = In[i] >> k3Shift
        // V[0] = TwoCmplt(Sn, nbits:20) >> k3Shift
        V[1] = V[0] + X[1]
        V[2] = (V[1] >> k2Shift.0) + (V[1] >> k2Shift.1)
        V[3] = In[i] - V[1]
        V[4] = X[0] + (V[3] >> k1Shift)
        V[5] = (V[4] - V[2]) >> k1Shift
        V[6] = (V[1] - X[2]) >> k1Shift

        XI[0] = V[4]
        XI[1] = X[1] + V[5]
        XI[2] = X[2] + V[6]

        Out[i] = X[2]
        X[0] = XI[0]
        X[1] = XI[1]
        X[2] = XI[2]
    }
    print("k2Shift: \(k2Shift)")

    let path = "/home/Dropbox/programming/Swift/TwosCmplt/tools/output.dat"
    withFile(path, mode: "w") { fp in
        for val in Out {
            let line = "\(val.toInt())\n"
            fputs(line, fp)
        }
    }

}

/**
 * A simple example of a first order filter having a coefficient specified by coeff
 */
func SimFltr (_ coeff: Int) {
    var M0: CoeffMlt = CoeffMlt(0x0, nbits: 20)
    let coeff: TwoCmplt = TwoCmplt(coeff, nbits: 20)
    var In: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    for i in 18..<1024 {
        In[i].value = (1<<14)
    }
    var X0: TwoCmplt = TwoCmplt(0, nbits: 20)
    var X1: TwoCmplt = TwoCmplt(0, nbits: 20)
    var X2: TwoCmplt = TwoCmplt(0, nbits: 20)
    // var X3: TwoCmplt = TwoCmplt(0, nbits: 20)
    for i in 0..<512 {
        M0.coeffUpdate(coeff)
        X0 = In[i] - X2
        X1 = X0 * M0
        X2 = X2 + X1
        // X0 = ((In[i] - X0) * M0) + X0
        Out[i] = X2
        print("X0: ", X0)
        print("X1: ", X1)
        print("X2: ", X2)
        print("Out: ", Out[i])
        print("i= ", i)
    }
    _ = In
    _ = Out
    print("\(Out[511])")
    ()
}

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
    let out: [String] = oprDct["OUT", default: []]
    if !out.isEmpty {
        print("out: \(out)")
    }

    let N: Int = input.count
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

        value3 = nds[out[1]]
        let outVal = value3?.toInt() ?? 0
        print("outVal: \(outVal)")

        print("Out: \(String(describing: nds["OUT"]))")
        print("i: \(i)")
        ()
    }

    print("Input.cnt: \(input.count), nds.count: \(nds.count)")
    dbPrnt("Out", nds[oprDct["OUT", default: []][1]])
}

/**
 * A Third Order Filter with a Finite Zeror. F-3dB = 0.16*k1 (approximately)
 * Fzero = 2.8*F-3dB
 */
func SimFltr3C (_ fileNm: String, nsmpls: Int) {
    var In: [Int] = Array(repeating: 0, count: 1024)

    var yamlString: String = ""
    var oprDct: [String: [String]] = [:]
    var nodeKeys: [String] = []
    var nmbV = 0, nmbX = 0
    var varNds: [String: TwoCmplt] = [:]
    var dlyNds: [String: TwoCmplt] = [:]
    var nds: [String: TwoCmplt] = [:]
    var out: String = ""
    var outNds: [String: [String]] = [:]
    var sortQue: [(String, [String])] = []
    var execQue: [(String, [String])] = []

    In[0] = (1<<14)
    nds["IN"] = TwoCmplt(In[0], nbits: 20, signed: true)

    do {
        yamlString = try String(contentsOfFile: fileNm, encoding: .utf8)
        print(yamlString)
    } catch {
        print("Could not read YAML file at \(fileNm): \(error)")
    }

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
    nmbV = varNds.count
    nmbX = dlyNds.count
    print("nmbV: \(nmbV), nmbX: \(nmbX)")

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


        print("Hello")
    }
    let coeffs: [String: Int] = ["k1": 0x4000]
    simFilter(input: In, oprDct: oprDct, nds: &nds, coeffs: coeffs, execQue: execQue)
}

@main
struct Demo {
    static func main() {
        let sgnbts: Int = 16
        // let val1: Int = Int((1<<sgnbts)/3)&((1<<sgnbts)-1)
        let val1: Int = 40502&((1<<sgnbts)-1)
        let In: TwoCmplt = TwoCmplt(value: 0x39e4, nbits: 20, signed: true)
        let M0 = CoeffMlt(val1, nbits: 20)
        let Out: TwoCmplt = In * M0
        print("Out from MltplyCoeff(signal: In):\(Out)  (\(Out.toInt()))")

        let val2: Int = Int(Double((1<<sgnbts))*0.28)&((1<<sgnbts)-1)
        let In2: TwoCmplt = -TwoCmplt(value: 0x5000, nbits: 20, signed: true)
        let M1: CoeffMlt = CoeffMlt(val2, nbits: 20) 
        print("In * M1: ", In * M1, " (\((In * M1).toInt()))")
        let Out2: TwoCmplt = In2 * M1
        print("Out2 from MltplyCoeff(signal: In2):\(Out2)  (\(Out2.toInt()))")

        // let M2 = CoeffMltply(Int(Double((1<<sgnbts))*0.175), nbits: 20)
        let M2  = CoeffMlt(Int(Double((1<<sgnbts))*0.175), nbits: 20) 
        let Out3: TwoCmplt = In2 * M2
        print("Out3 from In2 * M2:\n\t\(Out3) (\(Out3.toInt()))")

        // SimFltr(0x0A00)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            // SimOsc(0x63e4)
            // SimFltr3A(0x63e4)
            SimFltr3C("/home/Dropbox/programming/Swift/Filters/filt3b.yml", nsmpls: 1024)
        }
        print("Time: \(elapsed)")

        // SimFltr3B(0x63e4)
        // SimOsc(0x63e2)
        // SimFltr3C("/home/Dropbox/programming/Swift/Filters/filt3b.yml", nsmpls: 1024)
    }
}


