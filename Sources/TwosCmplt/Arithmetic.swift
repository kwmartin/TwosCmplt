import Foundation
import SharedTypes

// MARK: - Arithmetic

/*

func vAdd(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a),  .int(b)):   return .int(a + b)
    case let (.real(a), .real(b)):  return .real(a + b)
    case let (.two(a),  .two(b)):   return .two(a + b)      // implement + on TwoCmplt
    default:
        fatalError("type mismatch for +")
    }
}

func vSub(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a),  .int(b)):   return .int(a - b)
    case let (.real(a), .real(b)):  return .real(a - b)
    case let (.two(a),  .two(b)):   return .two(a - b)      // implement - on TwoCmplt
    default:
        fatalError("type mismatch for -")
    }
}

func vMul(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a),  .int(b)):   return .int(a * b)
    case let (.real(a), .real(b)):  return .real(a * b)
    case let (.two(a),  .two(b)):   return .two(a * b)      // implement * on TwoCmplt
    default:
        fatalError("type mismatch for *")
    }
}

func vDiv(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a),  .int(b)):   return .int(a / b)      // decide your div semantics
    case let (.real(a), .real(b)):  return .real(a / b)
    case let (.two(a),  .two(b)):   return .two(a / b)      // implement / on TwoCmplt
    default:
        fatalError("type mismatch for /")
    }
}

func vMod(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a),  .int(b)):   return .int(a % b)
    case let (.two(a),  .two(b)):   return .two(TwoCmplt(a.toInt() % b.toInt()))      // implement % on TwoCmplt
    default:
        fatalError("type mismatch for %")
    }
}

// MARK: - Comparisons

func vLessThan(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a),  .int(b)):   return .bool(a < b)
    case let (.real(a), .real(b)):  return .bool(a < b)
    case let (.two(a),  .two(b)):   return .bool(a < b)     // implement < on TwoCmplt
    default:
        fatalError("type mismatch for <")
    }
}

func vLessEq(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a),  .int(b)):   return .bool(a <= b)
    case let (.real(a), .real(b)):  return .bool(a <= b)
    case let (.two(a),  .two(b)):   return .bool(a <= b)
    default:
        fatalError("type mismatch for <=")
    }
}

func vGreaterThan(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a),  .int(b)):   return .bool(a > b)
    case let (.real(a), .real(b)):  return .bool(a > b)
    case let (.two(a),  .two(b)):   return .bool(a > b)
    default:
        fatalError("type mismatch for >")
    }
}

func vGreaterEq(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a),  .int(b)):   return .bool(a >= b)
    case let (.real(a), .real(b)):  return .bool(a >= b)
    case let (.two(a),  .two(b)):   return .bool(a >= b)
    default:
        fatalError("type mismatch for >=")
    }
}

func vEq(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a),  .int(b)):   return .bool(a == b)
    case let (.real(a), .real(b)):  return .bool(a == b)
    case let (.bool(a), .bool(b)):  return .bool(a == b)
    case let (.two(a),  .two(b)):   return .bool(a == b)
    default:
        fatalError("type mismatch for ==")
    }
}

func vNotEq(_ lhs: Value, _ rhs: Value) -> Value {
    switch vEq(lhs, rhs) {
    case .bool(let b): return .bool(!b)
    default:
        fatalError("== did not return bool")
    }
}

// MARK: - Logical (short-circuit not modeled, just boolean algebra)

func vLogicalOr(_ lhs: Value, _ rhs: Value) -> Value {
    guard case let .bool(a) = lhs,
          case let .bool(b) = rhs else {
        fatalError("type mismatch for logical ||")
    }
    return .bool(a || b)
}

func vLogicalAnd(_ lhs: Value, _ rhs: Value) -> Value {
    guard case let .bool(a) = lhs,
          case let .bool(b) = rhs else {
        fatalError("type mismatch for logical &&")
    }
    return .bool(a && b)
}

// MARK: - Bitwise ops (int / TwoCmplt)

func vBitAnd(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a), .int(b)):    return .int(a & b)
    case let (.two(a), .two(b)):    return .two(a & b)      // & on TwoCmplt
    default:
        fatalError("type mismatch for &")
    }
}

func vBitOr(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a), .int(b)):    return .int(a | b)
    case let (.two(a), .two(b)):    return .two(a | b)
    default:
        fatalError("type mismatch for |")
    }
}

func vBitXor(_ lhs: Value, _ rhs: Value) -> Value {
    switch (lhs, rhs) {
    case let (.int(a), .int(b)):    return .int(a ^ b)
    case let (.two(a), .two(b)):    return .two(a ^ b)
    default:
        fatalError("type mismatch for ^")
    }
}

// You can define NAND/NOR/XNOR in terms of AND/OR/XOR:

func vNand(_ lhs: Value, _ rhs: Value) -> Value {
    switch vBitAnd(lhs, rhs) {
    case let .int(x): return .int(~x)
    case let .two(x): return .two(~x)
    default:
        fatalError("type mismatch for NAND")
    }
}

func vNor(_ lhs: Value, _ rhs: Value) -> Value {
    switch vBitOr(lhs, rhs) {
    case let .int(x): return .int(~x)
    case let .two(x): return .two(~x)
    default:
        fatalError("type mismatch for NOR")
    }
}

func vXnor(_ lhs: Value, _ rhs: Value) -> Value {
    switch vBitXor(lhs, rhs) {
    case let .int(x): return .int(~x)
    case let .two(x): return .two(~x)
    default:
        fatalError("type mismatch for XNOR")
    }
}

// MARK: - Shifts (you decide semantics on TwoCmplt)

func vShiftLeftLogical(_ lhs: Value, _ rhs: Value) -> Value {
    guard let amount = rhs.int else {
        fatalError("shift amount must be int")
    }
    switch lhs {
    case let .int(x): return .int(x << amount)
    case let .two(x): return .two(x << amount)   // SLL on TwoCmplt
    default:
        fatalError("type mismatch for SLL")
    }
}

func vShiftRightLogical(_ lhs: Value, _ rhs: Value) -> Value {
    guard let amount = rhs.int else {
        fatalError("shift amount must be int")
    }
    switch lhs {
    case let .int(x): return .int(x >> amount)       // note: arithmetic on Swift Int
    case let .two(x): return .two(x >> amount)      // SRL on TwoCmplt (logical)
    default:
        fatalError("type mismatch for SRL")
    }
}

// Arithmetic left/right shifts, if distinct for TwoCmplt:
func vShiftLeftArithmetic(_ lhs: Value, _ rhs: Value) -> Value {
    guard let amount = rhs.int else {
        fatalError("shift amount must be int")
    }
    switch lhs {
    case let .int(x): return .int(x << amount)
    case let .two(x): return .two(x << amount)     // SLA
    default:
        fatalError("type mismatch for SLA")
    }
}

func vShiftRightArithmetic(_ lhs: Value, _ rhs: Value) -> Value {
    guard let amount = rhs.int else {
        fatalError("shift amount must be int")
    }
    switch lhs {
    case let .int(x): return .int(x >> amount)     // Int is two’s complement
    case let .two(x): return .two(x >> amount)     // SRA
    default:
        fatalError("type mismatch for SRA")
    }
}

// +x
func vUnaryPlus(_ operand: Value) -> Value {
    return operand
}

// -x
func vUnaryMinus(_ operand: Value) -> Value {
    switch operand {
    case .int(let a):
        return .int(-a)
    case .real(let a):
        return .real(-a)
    case .bool(let a):
        return .bool(!a)
    case .two(let a):
        return .two(-a)   // relies on prefix - for TwoCmplt [file:1]
    }
}

// comparison result: conventionally .int(0/1) or similar
func vUnaryCompare(_ op: UOp, _ operand: Value) -> Value {
    // You probably want a “compare to 0” semantic; here’s a sketch using Int.
    let intVal: Int
    switch operand {
    case .int(let a):
        intVal = a
    case .real(let a):
        intVal = Int(a)
    case .bool(let a):
        intVal = a ? 1 : 0
    case .two(let a):
        intVal = a.toInt()   // existing method [file:1]
    }

    let result: Bool
    switch op {
    case .lt:  result = intVal < 0
    case .lte: result = intVal <= 0
    case .gt:  result = intVal > 0
    case .gte: result = intVal >= 0
    case .eq:  result = intVal == 0
    case .neq: result = intVal != 0
    default:
        fatalError("vUnaryCompare: invalid op \(op)")
    }

    return .int(result ? 1 : 0)
}

// logical !
func vLogicalNot(_ operand: Value) -> Value {
    let isZero: Bool
    switch operand {
    case .int(let a):
        isZero = (a == 0)
    case .real(let a):
        isZero = (a == 0)
    case .bool(let a):
        isZero = (a == false)
    case .two(let a):
        isZero = (a.toInt() == 0)  // [file:1]
    }
    return .int(isZero ? 1 : 0)
}

// bitwise ~
func vBitNot(_ operand: Value) -> Value {
    switch operand {
    case .int(let a):
        return .int(~a)
    case .real(let a):
        return .real(Double(~(Int(a))))
    case .bool(let a):
        return a ? .bool(false) : .bool(true)
    case .two(let a):
        return .two(~a)      // you’ll need prefix ~ for TwoCmplt
    }
}

*/
