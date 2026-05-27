import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams
import SwiftPrettyPrint

struct Constants: Codable {
    let PER: Int
}

struct ClockEntry: Codable {
    let clkNm: String
    let initVal: Int
    let per: String
    let delay: Int
}

struct TimeSpecEntry: Codable {
    let tm: String      // keep it simple for now (handles "PER", "2*PER", etc. as strings)
    let vls: [[String]] // each is like ["INIT", "1"]
}

struct Specs: Codable {
    let Constants: Constants
    let Clock: [ClockEntry]
    let TimeSpcs: [TimeSpecEntry]
}

func CircuitSim () {
    print("Hello")

    let config = try! ldYamlConfig()
    print("\(config)")
    Glbls.configs = config

    let cirfl = config.directories.circLib + "DG_DR_3X1.yml"

    guard let yamlString = try? getCircYmlStr(named: "DG_DR_3X1")
    else { fatalError("Failed to read yamlString") }

    guard let rtYaml: RootYAML = readYML(at: cirfl) else {
        fatalError("Could not load \(cirfl)")
    }
    let behavYaml = rtYaml.behav_blcks
    _ = behavYaml

    /*
    let behavAst: BehavAST = behavYaml.toAST()
    print("\(behavYaml) \(behavAst)")
    */

    let behav_blcks: [BehavBlckYAML] = rtYaml.behav_blcks
    print("\(behav_blcks)")

    guard var circDf: CircDef = try? YAMLDecoder().decode(CircDef.self, from: yamlString)
    else { fatalError("Failed to load circDf") }
    let behavAST = circDf.buildBehavAST()
    _ = behavAST

    let alwaysBlock = circDf.behav_blcks[3]

    if case .alwaysblck(let alwaysYAML) = alwaysBlock {
        if let firstStmt = alwaysYAML.stmnts.first,
        case .ifst(let ifYAML) = firstStmt {

            print("outer iftrue count:", ifYAML.iftrue.count)
            print("outer ifelse count:", ifYAML.ifelse.count)

            if let inner = ifYAML.ifelse.first,
            case .ifst(let innerIf) = inner {
                print("inner iftrue count:", innerIf.iftrue.count)
                print("inner ifelse count:", innerIf.ifelse.count)
            }
        }
    }

    let fl = URL(fileURLWithPath: config.directories.modDir + "DG_DR_3X1.mod")
    var cirYml = ""
    do {
       cirYml = try String(contentsOf: fl, encoding: .utf8)
    } catch {
        print("Whoops, an error occured: \(error)")
    }

    print("Length of cirYml: \(cirYml.count)")

    let root: JSONValue
    var json: JSON

    do {
        let decoder = YAMLDecoder()
        root = try decoder.decode(JSONValue.self, from: cirYml)
        print(root)
        let anyRoot = toAny(root)
        json = JSON(anyRoot)   // from DynamicJSON
    } catch {
        fatalError("Decoding failed: \(error)")
    }

    let delay = root["behav_blcks"]?[0]?["delay_expr"]?[0]?["value"]?.double
    let dstQP = root["behav_blcks"]?[0]?["dst_sgnls"]?[0]?["name"]?.string

    let delay2 = json.behav_blcks[0].delay_expr[0].value.double
    let dstQP2 = json.behav_blcks[0].dst_sgnls[0].name.string

    dmp(delay, dstQP, delay2, dstQP2)
    dump([
        "delay": delay as Any,
        "dstQP": dstQP as Any,
        "delay2": delay2 as Any,
        "dstQP2": dstQP2 as Any,
        ]) 

    print("delay =", delay2 as Any, "dstQP =", dstQP2 as Any)


//
    do {
        let rootObj = root.object
        let behavBlcks = root["behav_blcks"]?.array
        let firstBlock = behavBlcks?.first?.object
        let delayExprArray = firstBlock?["delay_expr"]?.array
        let firstDelayObj = delayExprArray?.first?.object
        let type = firstDelayObj?["type"]?.string
        let value = firstDelayObj?["value"]?.double

        if
            let dstSgnlsArray = firstBlock?["dst_sgnls"]?.array,
            let firstDst = dstSgnlsArray.first?.object,
            let dstName = firstDst["name"]?.string,
            let dstType = firstDst["type"]?.string
        {
            print("dst name = \(dstName), type = \(dstType)")
        }

        dmp(rootObj, type, value)

    }

    let rootObj = root.object
    dump(rootObj)

    let N = 16384
    let Xin: TwoCmplt = TwoCmplt(0x20000, nbits: 20, signed: true)
    var X0: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var X0in: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: N)
    let Xmin = TwoCmplt(0x80000, nbits: 20, signed: true)
    let Xmax = TwoCmplt(0x7FFFF, nbits: 20, signed: true)
    var Xlfs = TwoCmplt(0x19A26, nbits: 17, signed: true)
    var Xsum: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var Xavg = 0.0
    var x0 = 0
    var x1 = 0
    var x2 = 0

    for i in 0..<N {
        if X0 > 0 {
            if x2 == 1 {
                X0in = Xin - 0x40000
                if (X0in > Xin) {
                    X0in = Xmin
                }
                Out[i] = TwoCmplt(1, nbits: 20, signed: true)
            } else {
                X0in = Xin + 0x40000
                if (X0in < Xin) {
                    X0in = Xmax
                }
                Out[i] = TwoCmplt(-1, nbits: 20, signed: true)
            }
        } else {
            if x2 == 1 {
                X0in = Xin + 0x40000
                if (X0in < Xin) {
                    X0in = Xmax
                }
                Out[i] = TwoCmplt(-1, nbits: 20, signed: true)
            } else {
                X0in = Xin - 0x40000
                if (X0in > Xin) {
                    X0in = Xmin
                }
                Out[i] = TwoCmplt(1, nbits: 20, signed: true)
            }
        }
        Xsum += Out[i]
        Xavg = Double(Xsum.toInt())/Double(i)
        x0 = Xlfs.selBit(n:13)
        x1 = Xlfs.selBit(n:16)
        x2 = x0^x1
        Xlfs = (Xlfs << 1) | x2
        print("Xlfs: \(Xlfs.bin())")
        print("Out[i]: \(Out[i].toInt()), Xavg: \(Xavg)")
        X0 = X0in
    }

    let path = "/home/Dropbox/programming/Swift/TwosCmplt/PlotResponse/oversmpl.dat"
    withFile(path, mode: "w") { fp in
        for val in Out {
            let line = "\(val.toInt())\n"
            fputs(line, fp)
        }
    }
}

@main
struct RunCircuitSim {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            CircuitSim ()
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
