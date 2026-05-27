public enum ArryElem {
    case string(String)
    case int(Int)
    case object([String: ArryElem]) // or a different type if you want
    case array([ArryElem])

    public init?(from any: Any) {
        switch any {
        case let s as String:
            self = .string(s)
        case let i as Int:
            self = .int(i)
        case let d as [String: Any]:
            // recursively wrap dictionary values
            var wrapped: [String: ArryElem] = [:]
            for (k, v) in d {
                guard let val = ArryElem(from: v) else { return nil }
                wrapped[k] = val
            }
            self = .object(wrapped)
        default:
            return nil
        }
    }
}

public enum ArryVal {
    case str(String)
    case arry([ArryElem])
    case cmps([Cmp])
    case nodes([NodeEnum])
    case prms([Parm])
    case sens(Sens)
    case delay(Delay)
}
