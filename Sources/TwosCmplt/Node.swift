import SharedTypes

public struct Nod {
    public var name: String = ""
    public var node: TwoCmplt
    public var prevValue: Int = 0  // value before the most recent setNode update
    public var updTm: Int
    /// Earlier (time, value) pairs, oldest first: each value held from its
    /// time until the next entry (or updTm). Lets a clocked block read a node
    /// as it was at the clock edge even if it changed more than once later in
    /// the same sweep -- prevValue alone only remembers one change.
    public var hist: [(tm: Int, value: Int)] = []
    static let histDepth = 4
    public var nodeDrvr: CmpRef = .none
    public var nodeSinks: [CmpRef] = []
    public var capac: Int = 2
    public var kind: NdKind = .simple

    /// Set a new value at time tm, keeping prevValue and the history.
    public mutating func commit(_ val: Int, tm: Int) {
        hist.append((tm: updTm, value: node.value))
        if hist.count > Nod.histDepth { hist.removeFirst(hist.count - Nod.histDepth) }
        prevValue = node.value
        node.value = val
        updTm = tm
    }

    /// The node's value at time t: the latest change at or before t.
    public func value(at t: Int) -> Int {
        if updTm <= t { return node.value }
        for h in hist.reversed() where h.tm <= t { return h.value }
        return hist.first?.value ?? prevValue
    }

    /**
     * Initialize a Nod struct.
     *
     * - Parameter value: Initial value
     *
     */
    public init(_ value: Int) {
        self.node = TwoCmplt(value, nbits: 1)
        self.updTm = 0
    }

    public init(_ value: TwoCmplt) {
        self.node = value
        self.updTm = 0
    }

    public init(_ name: String) {
        self.node = TwoCmplt(0, nbits: 1)
        self.updTm = 0
        self.name = name
    }

    public init(_ name: String, nbits: Int) {
        self.node = TwoCmplt(0, nbits: nbits)
        self.updTm = 0
        self.name = name
    }

    public init(name: String, value: TwoCmplt) {
        self.name = name
        self.node = value
        self.updTm = 0
    }

    public mutating func upd(_ value: Int, time: Int) {
        self.node.value = value
        self.updTm = time
    }

    public mutating func addCapac(_ capac: Int) {
        self.capac += capac
    }
}

