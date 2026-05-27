import SharedTypes


/*
 * busConcat constructs a TwoCmplt from a Node struct
 *
 * - Paramater nodes: an array of Bus enums defined in Bus.swift
 *
 * -returns: TwoCmplt formed Bus enum; usually 1 or a few bits from Bus enum
 */
public func busConcat(_ nodes: BussArray) -> TwoCmplt {
    var out: TwoCmplt = TwoCmplt(0, nbits:0)
    for bus in nodes {
        switch bus {
        case .int(let bit):
            out.nbits += 1
            out = (out<<1) | bit
            // print("out \(out.value)")
        case .uint(let uint):
            let sz = uint.1
            out.nbits += sz
            out = (out<<sz) | uint.0
            // print("out \(out.value)")
        case .twoCmplt(let node):
            let sz = node.nbits
            out.nbits += sz
            out = (out<<sz) | node
            // print("out \(out.value)")
        case .twoBit(let bit):
            let bt = (bit.0.value>>bit.1) & 1
            out.nbits += 1
            out = (out<<1) | bt
            // print("out \(out.value)")
        case .twoSlice(let slice):
            let sz = slice.1 - slice.2 + 1
            out.nbits += sz
            out = (out<<sz) | (slice.0.value>>slice.2) & ((1<<sz) - 1)
            // print("out \(out.value)")
        }
    }
    return out
}

public struct Gate {
    let kind: Kind
    var name: String = ""

    // One-time, lazy load of all truth tables from YAML
    private static let store: [GateConfig.Key: Tbl] = {
        GateConfig.loadFromYAML()
    }()
    private let table: Tbl?   // <- now optional

    unowned var circuit: Circuit
    let inps: [Int]
    let outs: [Int]
    var index: Int = 0
    let delay: Int
    var state: Int? = nil   // only non-nil for .reg
    var clock: Int? = nil   // only non-nil for .reg
    var seg: (Int, Int)?    // only non-nil for .seg

    static func table(for kind: Kind, ninps: Int) -> Tbl? {
        let key = GateConfig.Key(kind: kind, ninps: ninps)
        return store[key]    // return nil when no table present
    }

    public init(
        seg: (Int, Int),
        circuit: Circuit,
        inps: [Int],
        outs: [Int]
    ) {
        self.circuit = circuit
        self.inps = inps
        self.outs = outs
        self.kind = .seg
        self.delay = 1
        self.seg = seg
        self.table = Gate.table(for: .seg, ninps: inps.count)
    }

    public init(
        kind: Kind,
        name: String,
        ninps: Int,
        index: Int,
        circuit: Circuit,
        inps: [Int],
        outs: [Int],
        delay: Int
    ) {
        self.name = name
        self.index = index
        self.circuit = circuit
        self.inps = inps
        self.outs = outs
        self.kind = kind
        self.delay = delay
        self.seg = nil

        // For table-based gates, look up the table.
        // For table-less gates (e.g. .join), this will be nil.
        self.table = Gate.table(for: kind, ninps: ninps)

        if kind == .reg {
            self.state = 0
            let clk = self.circuit.nodes[self.inps[2]].node.value
            self.clock = clk
        }
    }

    mutating func updReg(_ d: Int, _ nit: Int, _ clk: Int) -> (Int, Int) {
        if nit == 1 {
            self.state = 0
            self.clock = clk
            return (0, clk)
        } else if self.clock == 1 && clk == 0 {
            self.state = d
            self.clock = clk
            return (d, clk)
        } else {
            self.clock = clk
            return (self.state!, clk)
        }
    }

    mutating func eval(tm: Int) {
        var updTm = tm
        var outNd: Nod

        switch kind {
        case .reg:
            let d = self.circuit.nodes[self.inps[0]].node.value
            let nit = self.circuit.nodes[self.inps[1]].node.value
            let clk = self.circuit.nodes[self.inps[2]].node.value
            (self.state, self.clock) = updReg(d, nit, clk)
            outNd = self.circuit.nodes[self.outs[0]]
            if outNd.node.value != self.state! {
                self.circuit.setNode(outNd.name, val: self.state!, tm: updTm + self.delay)
            }
            return

        case .seg:
            let bs = self.circuit.nodes[self.inps[0]]
            var outVal = 0
            let nd = bs.node
            updTm = bs.updTm > updTm ? bs.updTm : updTm
            for i in 0..<nd.nbits {
                outVal = (outVal << 1) | ((nd.value >> i) & 1)
            }
            outNd = self.circuit.nodes[self.outs[0]]
            if outNd.node.value != outVal {
                self.circuit.setNode(outNd.name, val: outVal, tm: updTm + self.delay)
            }
            return

        case .join:
            // Concatenate all inputs into a wider integer
            var outVal: Int = 0
            for indx in self.inps {
                let nd = self.circuit.nodes[indx]
                let nbits = nd.node.nbits
                updTm = nd.updTm > updTm ? nd.updTm : updTm
                outVal = (outVal << nbits) | nd.node.value
            }
            outNd = self.circuit.nodes[self.outs[0]]
            if outNd.node.value != outVal {
                self.circuit.setNode(outNd.name, val: outVal, tm: updTm + self.delay)
            }
            return

        default:
            break
        }

        // Table-based evaluation (unchanged, but now guards table being nil)
        var tblindx = 0
        for indx in self.inps {
            let nd = self.circuit.nodes[indx]
            let val = nd.node.value
            updTm = nd.updTm > updTm ? nd.updTm : updTm
            tblindx = (tblindx << 1) | (val & 1)
        }

        guard let table = self.table else {
            preconditionFailure("Missing truth table for gate \(kind) with inputs \(inps.count)")
        }

        switch table {
        case .tbl(let int):
            let outval = (int >> tblindx) & 1
            self.circuit.setNode(self.circuit.nodes[self.outs[0]].name,
                                val: outval,
                                tm: updTm + self.delay)

        case .tbls(let ints):
            for i in ints.indices {
                let outval = (ints[i] >> tblindx) & 1
                if self.circuit.nodes[self.outs[i]].node.value != outval {
                    // print("Time: \(updTm + self.delay), parent: \(self.circuit.name), name: \(name), "
                    //     + "node: \(self.circuit.nodes[self.outs[i]].name), value: \(outval)")
                    self.circuit.setNode(self.circuit.nodes[self.outs[i]].name,
                                        val: outval,
                                        tm: updTm + self.delay)
                }
            }
        }
    }
}
