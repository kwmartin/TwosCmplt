import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

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

func loadYamlCod(at path: String = "Config.yaml") throws -> ProjectConfig {
    let url = URL(fileURLWithPath: path)
    let yamlString = try String(contentsOf: url, encoding: .utf8)
    return try YAMLDecoder().decode(ProjectConfig.self, from: yamlString)
}

func CircuitSim () {
    DbgLggr.shared.open()
    defer { DbgLggr.shared.close() }
    dbg("= Entered CircuitSim()")

    let config = try! loadYamlCod()
    print("\(config)")
    Glbls.configs = config
    // let and2 = Gate(kind: .and, ninps: 2)
    // print("\(and2)")

    // var parms: [Parm] = []

    var cDf1 = makeCircDef("TB_DVDR4") ?? nil
    let crc1 = cDf1!.toCircuit()
    let spcs1 = loadSpecs("TB_DVDR4")
    let rSpcs1 = simCircuit(crc1, per: spcs1.per, finishTm: spcs1.finishTm, tmSpcs: spcs1.tmSpcs)
    _ = rSpcs1

    var cDf6 = makeCircDef("DG_DFFCP_3X2") ?? nil
    let crc6 = cDf6!.toCircuit()
    let spcs6 = loadSpecs("DG_DFFCP_3X2")
    let rSpcs6 = simCircuit(crc6, per: spcs6.per, finishTm: spcs6.finishTm, tmSpcs: spcs6.tmSpcs)
    _ = rSpcs6

    let spcs0 = loadSpecs("TFF")
    print("Period: \(spcs0.per), Finish Time: \(spcs0.finishTm), tmSpcs count: \(spcs0.tmSpcs.count)")

    var cdfFaddr = makeCircDef("FADDR_3X2") ?? nil
    let crcFaddr = cdfFaddr!.toCircuit()
    _ = crcFaddr

    let spcs2 = loadSpecs("DVD2")
    print("Period: \(spcs2.per), Finish Time: \(spcs2.finishTm), tmSpcs count: \(spcs2.tmSpcs.count)")
    var cDf = makeCircDef("DVD2") ?? nil
    let crc = cDf!.toCircuit()
    let cdf1 = Glbls.circDef(for: "DG_DR_3X1")
    _ = cdf1
    let rSpcs = simCircuit(crc, per: spcs2.per, finishTm: spcs2.finishTm, tmSpcs: spcs2.tmSpcs)
    _ = rSpcs

    let circ5 = genCirc("DVD2")
    _ = circ5

    var crcDf3 = makeCircDef("DG_DR_3X1") ?? nil
    _ = crcDf3

    let circ3 = crcDf3!.toCircuit()
    _ = circ3

    // let circ5 = Circuit.make("DG_NAND3")

    let circ4 = Circuit.make("CNTR4") 
    dump(circ4)

    guard let yamlString = try? getCircYmlStr(named: "DG_DR_3X1")
    else { fatalError("Failed to read yamlString") }

    guard let ymlStr = try? getCircYmlStr(named: "DG_DR_3X1")
    else { fatalError("Failed to read ymlStr") }

    guard let circ0 = try? Circuit.make(fromSubcircYAML: ymlStr)
    else { fatalError("Failed to get circ0") }
    dump(circ0)

    /*
    let circ_df: CircDef
    do {
        circ_df = try YAMLDecoder().decode(CircDef.self, from: yamlString)
        print("Decoded CircDef OK")

        // put your inspection code here, e.g. the outer/inner if counts
        let alwaysBlock = circ_df.behav_blcks[3]
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

    } catch {
        print("DECODE ERROR:", error)
    }

    guard let circDf  = try? YAMLDecoder().decode(CircDef.self, from: yamlString)
    else { fatalError("Failed to read yamlString") }

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

    guard var circDef: CircDef = try? YAMLDecoder().decode(CircDef.self, from: yamlString)
    else { fatalError("Failed to load circDef") }

    // Build behavioral AST into circDef.behav
    _ = circDef.buildBehavAST()

    // Derive initBlcks / alwaysBlcks from behav.behav_blcks
    circDef.copyBehav()

    // Now generate code for init/always blocks
    var ctx = Context(circDef: circDef)
    generateCode(for: &circDef, ctx: &ctx)
    */

    guard let circ = try? Circuit.make(fromSubcircYAML: yamlString)
    else { fatalError("Failed to get circ") }
    dump(circ)

    let circDef: CircDef? = makeCircDef("DG_DR_3X1") ?? nil

    let block = circDef!.behav[3]

    switch block {
    case .alwaysblck(let always):
        let stmtIds = always.body.stmnts   // [StmtId]

        for stmtId in stmtIds {
            let stmt = circDef!.stmt(for: stmtId)   // or circDef.stmt(for: stmtId)

            switch stmt {
            case .ifst(let ifAst):
                print("ifst cmpr:", ifAst.cmpr)
                print("iftrue count:", ifAst.iftrue.stmnts.count)

            case .noblckst(let nb):
                print("non-blocking assignment to", nb.lvalue)

            default:
                break
            }
        }

    default:
        break
    }

    // cDf = makeCircDef("CNTR3") ?? nil
    // let cInst = cDf!.toCircuit()


    let circuit = Circuit.make("CNTR3")!
    circuit.name = "TopCircuit"
    Glbls.topCircuit = circuit
    let nds = circuit.nodes
    print("nds.count: \(nds.count)")
    // initializeCmpCnts(circuit)

    // let url  = URL(fileURLWithPath: "spec.yaml")

    let url = Glbls.simSpcsDir.file("CNTR3", ext: "yml")

    guard let spec = try? loadSpec(url: url) else {
        print("Failed to load spec")
        preconditionFailure("Failed to load spec")
    }

    print("Constants:", spec.constants)
    print("FinishTime: ", spec.finishTm)
    print("Clock:", spec.clock)
    print("TimeSpcs:", spec.timeSpcs)

    var tmSpcs = genClkChngs(spec)
    tmSpcs = mergeTimeSpcs(spec.timeSpcs, tmSpcs)

    guard let per = spec.constant(named: "PER") else {
        fatalError("Missing PER constant")
    }
    let finishTm = spec.finishTm
    let rtrnSpcs = simCircuit(circuit, per: per, finishTm: finishTm, tmSpcs: tmSpcs)
    let sigChanges = glblChngs2Vcd(circuit)
    print("sigChanges has \(sigChanges.count) elements")
    print("rtrnSpcs: \(rtrnSpcs)")
    print("sigTraces.count \(Glbls.sigTraces.count)")

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
