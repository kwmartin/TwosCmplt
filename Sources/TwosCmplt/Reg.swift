import SharedTypes


public struct Reg {
    let kind: RegTyp
    var name: String = ""

    unowned var circuit: Circuit
    let inps: [Int]
    let outs: [Int]
    var index: Int = 0
    let delay: Int
    var state: Int = 0
    var clock: Int = 0
    let nit: Int
    let d0: Int
    let edge: Int

    public init(kind: RegTyp,
        name: String,
        ninps: Int,
        index: Int,
        circuit: Circuit,
        inps: [Int],
        outs: [Int],
        delay: Int
        ) {
        self.name = name
        self.circuit = circuit
        self.inps = inps
        self.outs = outs
        self.kind = kind
        self.delay = delay
        self.state = 0
        switch kind {
        case .dpf:
            edge = 0; nit=0; d0=0
        case .dpr:
            edge = 1; nit=0; d0=0
        case .dnf:
            edge = 0; nit=1; d0=0
        case .dnr:
            edge = 1; nit=1; d0=0
        case .d0pf:
            edge = 0; nit=0; d0=1
        case .d0pr:
            edge = 1; nit=0; d0=1
        case .d0nf:
            edge = 0; nit=1; d0=1
        case .d0nr:
            edge = 1; nit=1; d0=1
        }
        let clk: Int
        if d0 == 0 {
            clk = self.circuit.nodes[self.inps[2]].node.value
        } else {
            clk = self.circuit.nodes[self.inps[3]].node.value
        }
        self.clock = clk
   }

    mutating func updReg(_ d: Int, _ d0: Int, _ initial: Int, _ clk: Int) -> (Int, Int) {
        if (initial == 1 && nit == 0) ||  (initial == 0 && nit == 1){
            self.state = d0
            self.clock = clk
            return (d0, clk)
        } else if (self.clock == 1 && clk == 0 && edge == 0) || (self.clock == 0 && clk == 1 && edge == 1){
            self.state = d
            self.clock = clk
            return (d, clk)
        } else {
            self.clock = clk
            return (self.state, clk)
        }
    }

    mutating func eval(tm: Int) {
        let dNd: Nod
        let d: Int
        let d_0: Int
        let initial: Int
        let clk: Int
        var updTm: Int
        let clkNd: Nod
        if d0 == 0 {
            dNd = self.circuit.nodes[self.inps[0]]
            d = dNd.node.value
            initial = self.circuit.nodes[self.inps[1]].node.value
            clkNd = self.circuit.nodes[self.inps[2]]
            clk = clkNd.node.value
            d_0 = 0
        } else {
            dNd = self.circuit.nodes[self.inps[0]]
            d = dNd.node.value
            d_0 = self.circuit.nodes[self.inps[1]].node.value
            initial = self.circuit.nodes[self.inps[2]].node.value
            clkNd = self.circuit.nodes[self.inps[3]]
            clk = clkNd.node.value
        }

        // If this is a clock edge and D's update timestamp is after the clock edge,
        // D's new value propagated through combinational logic in the same eval sweep
        // but hasn't physically arrived yet — use the previously-stable D instead.
        let isEdge = (self.clock == 1 && clk == 0 && edge == 0) ||
                     (self.clock == 0 && clk == 1 && edge == 1)
        let sampledD = (isEdge && dNd.updTm > clkNd.updTm) ? dNd.prevValue : d

        (self.state, self.clock) = updReg(sampledD, d_0, initial, clk)

        let nd = circuit.nodes[self.outs[0]]
        updTm = clkNd.updTm > tm ? clkNd.updTm : tm
        if nd.node.value != self.state {
            print("Time: \(updTm + self.delay), reg_parent: \(self.circuit.name), name: \(name), "
            + "node: \(nd.name), value: \(self.state)")
            self.circuit.setNode(nd.name, val: self.state, tm: updTm + self.delay)
        }
    }
}
