import SharedTypes

public struct Nod {
    public var name: String = ""
    public var node: TwoCmplt
    public var prevValue: Int = 0  // value before the most recent setNode update
    public var updTm: Int
    public var nodeDrvr: CmpRef = .none
    public var nodeSinks: [CmpRef] = []
    public var capac: Int = 2

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

