import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

func GateSim () {
    print("Hello")
    /*


    // let and2 = Gate(kind: .and, ninps: 2)
    // print("\(and2)")

    let x = TwosCmplt.GetCircDict
    let circuit = GetCircDict("CNTR3")!
    let nds = circuit.nodes
    print("nds.count: \(nds.count)")

    guard let dict = yamlLoad("/home/Dropbox/programming/Swift/TwosCmplt/Resources/CircuitLib/CNTR3.yml") else {
        print("val is nil")
        return
    }

    guard let nodesVal = dict["nodes"] else {
        print("no nodes entry")
        return
    }

    guard case let .nodes(nodesArray) = nodesVal else {
        print("nodes entry is not .nodes")
        return
    }

    for (i, node) in nodesArray.enumerated() {
        switch node {
        case .name(let s):
            print("plain name: \(s)")

        case .def(let def):
            print("def name: \(def.name), nbits: \(def.nbits)")
        }
    }

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
    */
}

@main
struct RunGateSim {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            GateSim ()
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
