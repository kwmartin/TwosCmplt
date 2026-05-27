// In TwosCmplt/Operators.swift
import SharedTypes


infix operator >> : BitwiseShiftPrecedence
infix operator << : BitwiseShiftPrecedence
infix operator * : MultiplicationPrecedence
infix operator + : AdditionPrecedence
infix operator - : AdditionPrecedence
infix operator == : ComparisonPrecedence
infix operator < : ComparisonPrecedence
infix operator > : ComparisonPrecedence
infix operator <= : ComparisonPrecedence
infix operator >= : ComparisonPrecedence
infix operator && : LogicalConjunctionPrecedence
infix operator || : LogicalConjunctionPrecedence
infix operator += : AssignmentPrecedence
infix operator -= : AssignmentPrecedence

prefix operator &&
prefix operator |
prefix operator ^
prefix operator -

// extension TwoCmplt: Comparable {

/**
 * Check if lhs is equal to rhs after aligning both arguments to 
 * have the same precision. The arguments can have different nbits
 * and still return true as long as the values are the same.
 *
 * - Parameter lhs: TwoCmplt argument.
 * - Parameter rhs: The other TwoCmplt argument.
 *
 * - Returns: Return true if both have the same value, else return false.
 */
public func == (lhs: TwoCmplt, rhs: TwoCmplt) -> Bool {
    /*
    First align to equivalent precision, then check comparison
    */
    let lval, rval: Int
    if lhs.prec > rhs.prec {
        rval = rhs.toInt() << (lhs.prec - rhs.prec)
        lval = lhs.toInt()
    } else if lhs.prec < rhs.prec {
        rval = rhs.toInt()
        lval = lhs.toInt() << (rhs.prec - lhs.prec)
    } else {
        rval = rhs.toInt()
        lval = lhs.toInt()
    }
    var rtrn = lval == rval ? true : false
    rtrn = rhs.nbits != lhs.nbits ? false : rtrn
    return rtrn
}

/**
 * Check if lhs is <= rhs after aligning to 
 * have the same precision.
 *
 * - Returns: true if lhs <= rhs, else false
*/
public func < (lhs: TwoCmplt, rhs: TwoCmplt) -> Bool {
    /*
    First align to equivalent precision, then check comparison
    */
    let lval, rval: Int
    if lhs.prec > rhs.prec {
        rval = rhs.toInt() << (lhs.prec - rhs.prec)
        lval = lhs.toInt()
    } else if lhs.prec < rhs.prec {
        rval = rhs.toInt()
        lval = lhs.toInt() << (rhs.prec - lhs.prec)
    } else {
        rval = rhs.toInt()
        lval = lhs.toInt()
    }
    let rtrn = lval < rval ? true : false
    return rtrn
}

/**
 * Overload < to check if lhs is < rhs after aligning both arguments 
 * to have the same precision.
 *
 * - Parameter lhs: TwoCmplt argument.
 * - Parameter rhs: The other TwoCmplt argument.
 *
 * - Returns Bool: true if lhs < rhs, else false
 */
public func < (lhs: TwoCmplt, rhs: Int) -> Bool {
    /*
    First align to equivalent precision, then check comparison
    */
    let lval, rval: Int
    if lhs.prec > 0 {
        rval = rhs << lhs.prec
        lval = lhs.toInt()
    } else {
        rval = rhs
        lval = lhs.toInt()
    }
    let rtrn = lval < rval ? true : false
    return rtrn
}

// }

/**
 * Overload + to add two TwoCmplt values. 
 * The prec is the larger prec of the two arguments. The other prec is adjusted to match.
 * The nbits is the larger nbits of the two arguments after adjusting for prec.
 * If either argument is signed, the output is signed
 * The crry and ovflw are set if there is a carry or an overflow.
 * The default for States.addMode is .overflow and allows for overflows.
 * If States.addMode = .saturate, then in the case of overflow, the values
 * stored are the maximum or minimum possible values.
 *
 * - Parameter lhs: TwoCmplt argument.
 * - Parameter rhs: The other TwoCmplt argument.
 *
 * - Returns Bool: true if lhs < rhs, else false
*/
public func + (lhs: TwoCmplt, rhs: TwoCmplt) -> TwoCmplt {
    // Perform two’s complement addition
    var lval = lhs.toInt()
    var rval = rhs.toInt()
    var oprec, rbts, lbts: Int
    if lhs.prec > rhs.prec {
        oprec = lhs.prec
        rval = rval << (lhs.prec - rhs.prec)
        rbts = rhs.nbits + (lhs.prec - rhs.prec)
        lbts = lhs.nbits
    } else if lhs.prec < rhs.prec {
        oprec = rhs.prec
        lval = lval << (rhs.prec - lhs.prec)
        lbts = lhs.nbits + (rhs.prec - lhs.prec)
        rbts = rhs.nbits
    } else {
        lbts = lhs.nbits
        rbts = rhs.nbits
        oprec = lhs.prec
    }
    let nbits = (lbts < rbts) ? rbts : lbts
    let val = lval + rval
    let crry = (val&(1<<nbits)) != 0
    let signed = (lhs.signed || rhs.signed) ? true : false
    var oval: Int
    if crry && (States.addMode == .saturate) {
        if signed {
            oval = 1<<(nbits-1)
        } else {
            oval = (1<<nbits)-1
        }
    } else {
        oval = val&((1<<nbits)-1)
    }
    var ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    ocmplt.crry = crry
    ocmplt.ovflw = (oval < val) ? true : false
    return ocmplt
}

/**
 * Overload + to add a TwoCmplt variable to an Int.
 * The nbits is equal to lhs.nbits. The prec is equal to lhs.prec.
 * The crry and ovflw are set if there is a carry or an overflow.
 * The default for States.addMode is .overflow and allows for overflows.
 * If States.addMode = .saturate, then in the case of overflow, the values
 * stored are the maximum or minimum possible values.
 *
 * - Parameter lhs: TwoCmplt
 * - Parameter rhs: Int
 *
 * - Returns: A new TwoCmplt struct having nbits and prec the same as that of lhs.
 */
public func + (lhs: TwoCmplt, rhs: Int) -> TwoCmplt {
    // Perform two’s complement addition
    let lval = lhs.toInt()
    let oprec: Int = lhs.prec // match lhs.prec in case it's not 0
    let nbits = lhs.nbits
    let rval = rhs << lhs.prec
    let val = lval + rval
    let crry = (val&(1<<nbits)) != 0
    var oval: Int = val&((1<<nbits)-1)
    let signed = lhs.signed
    if crry && (States.addMode == .saturate) {
        if signed {
            oval = 1<<(nbits-1)
        } else {
            oval = 1<<((nbits-1)-1)
        }
    } else {
        oval = val&((1<<nbits)-1)
    }
    var ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    ocmplt.crry = crry
    ocmplt.ovflw = (oval < val) ? true : false
    return ocmplt
}

/**
 * Overload * function to multiply lhs by rhs. The default when multiplying
 * two TwoCmplt values is to return a product that has nbits equal to the 
 * sum of the nbits of the two arguments; the precision (prec) is also equal
 * to the sum of the prec's of the two arguments. This can be changed later using >>
 * and TwoCmplt.setPrec. However, for filters, sometimes one always wants the prec
 * to be equal to the prec of the lhs argument. This option can be configured by using:
 * States.multiplyMode = .truncate. To return to default operation, use States.multiplyMode = .full.
 *
 * - Parameter lhs: TwoCmplt argument to be "multiplied"
 * - Parameter rhs: The other TwoCmplt argument to be "multiplied"
 *
 * - Returns TwoCmplt: having nbits = lhs.nbits + rhs.nbits, and prec = lhs.prec + rhs.prec.
 */

public func * (lhs: TwoCmplt, rhs: TwoCmplt) -> TwoCmplt {
    /*
    Default mode for multiply is return full size that
    can be truncated seperately as needed. When using Glbls.mltTruncate mode,
    it is the user's responsibility that Glbls.mltTruncate is set in a thread-safe manner
    Glbls.mltTruncate mode is often used for filters where lhs is signal value, and
    rhs is coefficient. The coefficient would often be specified as having both nbits
    and prec having the same value. This means the coefficients are necessarilly
    less than 1, and in this case the values should always be set using hex with all bits
    specified for clarity (although the msb's might be 0's) 
    */
    let nbits: Int
    let prec: Int
    let signed: Bool
    let val: Int
    let shift: Int

    signed = (lhs.signed || rhs.signed) ? true: false

    if States.multiplyMode == .truncate {
        shift = rhs.nbits
        nbits = lhs.nbits
        prec = lhs.prec
        val = (lhs.value * rhs.value) >> shift
    } else {
        nbits = lhs.nbits + rhs.nbits
        prec = lhs.prec + rhs.prec
        val = lhs.value * rhs.value
    }
    let ocmplt = TwoCmplt(value: val, nbits: nbits, prec: prec, signed: signed)
    return ocmplt
}

/**
 * Overload += to add two two's complement integers
 * The prec is the larger prec of the two arguments. The other prec is
 * adjusted to match before doing the addition.
 * The nbits is the larger nbits of the two arguments after adjusting for prec.
 * If either argument is signed, the output is signed
 * The crry and ovflw are set if there is a carry or an overflow.
 * The default for States.addMode is .overflow and allows for overflows.
 * If States.addMode = .saturate, then in the case of overflow, the values
 * stored are the maximum or minimum possible values.
 *
 * - Parameter lhs: TwoCmplt
 * - Parameter rhs: Int
 *
 */
public func += (lhs: inout TwoCmplt, rhs: TwoCmplt) {
    // Perform two’s complement addition
    var lval = lhs.toInt()
    var rval = rhs.toInt()
    var oprec, rbts, lbts: Int
    if lhs.prec > rhs.prec {
        oprec = lhs.prec
        rval = rval << (lhs.prec - rhs.prec)
        rbts = rhs.nbits + (lhs.prec - rhs.prec)
        lbts = lhs.nbits
    } else if lhs.prec < rhs.prec {
        oprec = rhs.prec
        lval = lval << (rhs.prec - lhs.prec)
        lbts = lhs.nbits + (rhs.prec - lhs.prec)
        rbts = rhs.nbits
    } else {
        lbts = lhs.nbits
        rbts = rhs.nbits
        oprec = lhs.prec
    }
    let nbits = (lbts < rbts) ? rbts : lbts
    let val = lval + rval
    let crry = (val&(1<<nbits)) != 0
    var oval: Int = val&((1<<nbits)-1)
    let signed = (lhs.signed || rhs.signed) ? true : false
    if crry && (States.addMode == .saturate) {
        if signed {
            oval = 1<<(nbits-1)
        } else {
            oval = 1<<((nbits-1)-1)
        }
    } else {
        oval = val&((1<<nbits)-1)
    }
    var ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    ocmplt.crry = crry
    ocmplt.ovflw = (oval < val) ? true : false
    lhs = ocmplt
}

/**
 * Overload += to add a TwoCmplt variable to an Int.
 * The nbits is equal to lhs.nbits. The prec is equal to lhs.prec.
 * The crry and ovflw are set if there is a carry or an overflow.
 * The default for States.addMode is .overflow and allows for overflows.
 * If States.addMode = .saturate, then in the case of overflow, the values
 * stored are the maximum or minimum possible values.
 *
 * - Parameter lhs: TwoCmplt
 * - Parameter rhs: Int
 *
 */
public func += (lhs: inout TwoCmplt, rhs: Int) {
    // Perform two’s complement addition
    let lval = lhs.toInt()
    let oprec: Int = lhs.prec // match lhs.prec in case it's not 0
    let nbits = lhs.nbits
    let rval = rhs << lhs.prec
    let val = lval + rval
    let crry = (val&(1<<nbits)) != 0
    var oval: Int = val&((1<<nbits)-1)
    let signed = lhs.signed
    if crry && (States.addMode == .saturate) {
        if signed {
            oval = 1<<(nbits-1)
        } else {
            oval = 1<<((nbits-1)-1)
        }
    } else {
        oval = val&((1<<nbits)-1)
    }
    var ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    ocmplt.crry = crry
    ocmplt.ovflw = (oval < val) ? true : false
    lhs = ocmplt
}

/**
 * Overload - to subract rhs two's complement integer from lhs two's complement integer.
 * The prec is the larger prec of the two arguments. The other prec is adjusted to match.
 * The nbits is the larger nbits of the two arguments after adjusting.
 * If either argument is signed, the output is signed.
 * The crry and ovflw are set if there is a carry or an overflow.
 * The default for States.addMode is .overflow and allows for overflows.
 * If States.addMode = .saturate, then in the case of overflow, the values
 * stored are the maximum or minimum possible values.
 *
 * - Returns: A new TwoCmplt output.
 */
public func - (lhs: TwoCmplt, rhs: TwoCmplt) -> TwoCmplt {
    // Perform two’s complement subtraction
    var lval = lhs.toInt()
    var rval = rhs.toInt()
    var oprec, rbts, lbts: Int
    if lhs.prec > rhs.prec {
        oprec = lhs.prec
        rval = rval << (lhs.prec - rhs.prec)
        rbts = rhs.nbits + (lhs.prec - rhs.prec)
        lbts = lhs.nbits
    } else if lhs.prec < rhs.prec {
        oprec = rhs.prec
        lval = lval << (rhs.prec - lhs.prec)
        lbts = lhs.nbits + (rhs.prec - lhs.prec)
        rbts = rhs.nbits
    } else {
        lbts = lhs.nbits
        rbts = rhs.nbits
        oprec = lhs.prec
    }
    let nbits = (lbts < rbts) ? rbts : lbts
    let val = lval - rval
    let crry = (val&(1<<nbits)) != 0
    var oval: Int = val&((1<<nbits)-1)
    let signed = (lhs.signed || rhs.signed || val < 0) ? true : false
    if crry && (States.addMode == .saturate) {
        if signed {
            oval = 1<<(nbits-1)
        } else {
            oval = 1<<((nbits-1)-1)
        }
    } else {
        oval = val&((1<<nbits)-1)
    }
    var ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    ocmplt.crry = crry
    ocmplt.ovflw = (oval < val) ? true : false
    return ocmplt
}

/**
 * Overload - to subtract an Int from a TwoCmplt value. 
 * The prec and signed are inherited from the lhs.
 * The nbits is also that of the lhs.
 * The crry and ovflw are set if there is a carry or an overflow.
 * The default for States.addMode is .overflow and allows for overflows.
 * If States.addMode = .saturate, then in the case of overflow, the values
 * stored are the maximum or minimum possible values.
 *
 * - Parameter lhs: TwoCmplt argument.
 * - Parameter rhs: Int.
 *
 * - Returns TwoCmplt: lhs - rhs
*/
public func - (lhs: TwoCmplt, rhs: Int) -> TwoCmplt {
    // Perform two’s complement addition with rhs being Int
    let lval = lhs.toInt()
    let rval = rhs << lhs.prec
    var oprec, lbts: Int
    lbts = lhs.nbits
    oprec = lhs.prec

    let nbits = lbts
    let val = lval - rval
    let crry = (val&(1<<nbits)) != 0
    let signed = lhs.signed
    var oval: Int
    if crry && (States.addMode == .saturate) {
        if signed {
            oval = 1<<(nbits-1)
        } else {
            oval = 1<<((nbits-1)-1)
        }
    } else {
        oval = val&((1<<nbits)-1)
    }
    var ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    ocmplt.crry = crry
    ocmplt.ovflw = (oval < val) ? true : false
    return ocmplt
}

/**
 * Overload -= to subract rhs two's complement integer from lhs two's complement integer.
 * The prec is the larger prec of the two arguments. The other prec is adjusted to match.
 * The nbits is the larger nbits of the two arguments after adjusting.
 * If either argument is signed, the output is signed.
 * The crry and ovflw are set if there is a carry or an overflow.
 * The default for States.addMode is .overflow and allows for overflows.
 * If States.addMode = .saturate, then in the case of overflow, the values
 * stored are the maximum or minimum possible values.
 *
 */
public func -= (lhs: inout TwoCmplt, rhs: TwoCmplt) {
    var lval = lhs.toInt()
    var rval = rhs.toInt()
    var oprec, rbts, lbts: Int
    if lhs.prec > rhs.prec {
        oprec = lhs.prec
        rval = rval << (lhs.prec - rhs.prec)
        rbts = rhs.nbits + (lhs.prec - rhs.prec)
        lbts = lhs.nbits
    } else if lhs.prec < rhs.prec {
        oprec = rhs.prec
        lval = lval << (rhs.prec - lhs.prec)
        lbts = lhs.nbits + (rhs.prec - lhs.prec)
        rbts = rhs.nbits
    } else {
        lbts = lhs.nbits
        rbts = rhs.nbits
        oprec = lhs.prec
    }
    let nbits = (lbts < rbts) ? rbts : lbts
    let val = lval - rval
    let crry = (val&(1<<nbits)) != 0
    var oval: Int = val&((1<<nbits)-1)
    let signed = (lhs.signed || rhs.signed || val < 0) ? true : false
    if crry && (States.addMode == .saturate) {
        if signed {
            oval = 1<<(nbits-1)
        } else {
            oval = 1<<((nbits-1)-1)
        }
    } else {
        oval = val&((1<<nbits)-1)
    }
    var ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    ocmplt.crry = crry
    ocmplt.ovflw = (oval < val) ? true : false
    lhs = ocmplt
}

/**
 * Overload - to subtract an Int from a TwoCmplt variable.
 * The nbits is equal to lhs.nbits. The prec is equal to lhs.prec.
 * The crry and ovflw are set if there is a carry or an overflow.
 * The default for States.addMode is .overflow and allows for overflows.
 * If States.addMode = .saturate, then in the case of overflow, the values
 * stored are the maximum or minimum possible values.
 *
 * - Parameter lhs: TwoCmplt
 * - Parameter rhs: Int
 *
 */
public func -= (lhs: inout TwoCmplt, rhs: Int) {
    // Perform two’s complement addition
    let lval = lhs.toInt()
    let oprec: Int = lhs.prec
    let rval = rhs << lhs.prec
    let nbits = lhs.nbits
    let val = lval - rval
    let crry = (val&(1<<nbits)) != 0
    var oval: Int = val&((1<<nbits)-1)
    let signed = lhs.signed
    if crry && (States.addMode == .saturate) {
        if signed {
            oval = 1<<(nbits-1)
        } else {
            oval = 1<<((nbits-1)-1)
        }
    } else {
        oval = val&((1<<nbits)-1)
    }
    var ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    ocmplt.crry = crry
    ocmplt.ovflw = (oval < val) ? true : false
    lhs = ocmplt
}

/**
 * Overload the unary - operator to negate a TwoCmplt integer.
 *
 * - Returns: A new TwoCmplt struct.
 */
public prefix func - (reg: TwoCmplt) -> TwoCmplt {
    let val = -reg.value
    let ocmplt = TwoCmplt(value: val, nbits: reg.nbits, prec: reg.prec, signed: true)
    return ocmplt
}

/**
 * absolute value of self.value
 *
 *
 * - Returns TwoCmplt: were value is always positive
public func abs(_ reg: TwoCmplt) -> TwoCmplt {
    let ocmplt = (reg.toInt() < 0) ? -reg : reg
    return ocmplt
}
 */

/**
 * Overload != to check if lhs is not equal to rhs after aligning so 
 * both parameters have the same precision (prec).
 *
 * - Returns: false if both have the same value, else true
 */
public func != (lhs: TwoCmplt, rhs: TwoCmplt) -> Bool {
    /*
    First align to equivalent precision, then check comparison
    */
    let lval, rval: Int
    if lhs.prec > rhs.prec {
        rval = rhs.toInt() << (lhs.prec - rhs.prec)
        lval = lhs.toInt()
    } else if lhs.prec < rhs.prec {
        rval = rhs.toInt()
        lval = lhs.toInt() << (rhs.prec - lhs.prec)
    } else {
        rval = rhs.toInt()
        lval = lhs.toInt()
    }
    let rtrn = lval != rval ? true : false
    return rtrn
}

/**
 * Check if lhs is <= rhs after aligning to 
 * have the same precision.
 *
 * - Returns: true if lhs <= rhs, else false
*/
public func <= (lhs: TwoCmplt, rhs: TwoCmplt) -> Bool {
    /*
    First align to equivalent precision, then check comparison
    */
    let lval, rval: Int
    if lhs.prec > rhs.prec {
        rval = rhs.toInt() << (lhs.prec - rhs.prec)
        lval = lhs.toInt()
    } else if lhs.prec < rhs.prec {
        rval = rhs.toInt()
        lval = lhs.toInt() << (rhs.prec - lhs.prec)
    } else {
        rval = rhs.toInt()
        lval = lhs.toInt()
    }
    let rtrn = lval <= rval ? true : false
    return rtrn
}

/**
 * Check if lhs is <= rhs after aligning to 
 * have the same precision.
 *
 * - Returns: true if lhs <= rhs, else false
*/
public func <= (lhs: TwoCmplt, rhs: Int) -> Bool {
    /*
    First align to equivalent precision, then check comparison
    */
    let lval, rval: Int
    if lhs.prec > 0 {
        rval = rhs << lhs.prec
        lval = lhs.toInt()
    } else {
        rval = rhs
        lval = lhs.toInt()
    }
    let rtrn = lval <= rval ? true : false
    return rtrn
}

/**
 * Check if lhs is > rhs after aligning to 
 * have the same precision.
 *
 * - Returns: true if lhs <= rhs, else false
*/
public func > (lhs: TwoCmplt, rhs: TwoCmplt) -> Bool {
    /*
    First align to equivalent precision, then check comparison
    */
    let lval, rval: Int
    if lhs.prec > rhs.prec {
        rval = rhs.toInt() << (lhs.prec - rhs.prec)
        lval = lhs.toInt()
    } else if lhs.prec < rhs.prec {
        rval = rhs.toInt()
        lval = lhs.toInt() << (rhs.prec - lhs.prec)
    } else {
        rval = rhs.toInt()
        lval = lhs.toInt()
    }
    let rtrn = lval > rval ? true : false
    return rtrn
}

/**
 * Check if lhs is > rhs after aligning to 
 * have the same precision.
 *
 * - Returns: true if lhs <= rhs, else false
*/
public func > (lhs: TwoCmplt, rhs: Int) -> Bool {
    /*
    First align to equivalent precision, then check comparison
    */
    let lval, rval: Int
    if lhs.prec > 0 {
        rval = rhs << lhs.prec
        lval = lhs.toInt()
    } else {
        rval = rhs
        lval = lhs.toInt()
    }
    let rtrn = lval > rval ? true : false
    return rtrn
}

/**
 * Check if lhs is >= rhs after aligning to 
 * have the same precision.
 *
 * - Returns: true if lhs <= rhs, else false
*/
public func >= (lhs: TwoCmplt, rhs: TwoCmplt) -> Bool {
    /*
    First align to equivalent precision, then check comparison
    */
    let lval, rval: Int
    if lhs.prec > rhs.prec {
        rval = rhs.toInt() << (lhs.prec - rhs.prec)
        lval = lhs.toInt()
    } else if lhs.prec < rhs.prec {
        rval = rhs.toInt()
        lval = lhs.toInt() << (rhs.prec - lhs.prec)
    } else {
        rval = rhs.toInt()
        lval = lhs.toInt()
    }
    let rtrn = lval >= rval ? true : false
    return rtrn
}

/**
 * Check if lhs is >= rhs after aligning to 
 * have the same precision.
 *
 * - Returns: true if lhs <= rhs, else false
*/
public func >= (lhs: TwoCmplt, rhs: Int) -> Bool {
    /*
    First align to equivalent precision, then check comparison
    */
    let lval, rval: Int
    if lhs.prec > 0 {
        rval = rhs << lhs.prec
        lval = lhs.toInt()
    } else {
        rval = rhs
        lval = lhs.toInt()
    }
    let rtrn = lval >= rval ? true : false
    return rtrn
}

/**
 * Overloads << to do a logic shift left; the operation could truncate most significant bits 
 * which sets ovflw true for the returned TwoCmplt struct
 *.
 * - Returns new: TwoCmplt after shift
 */
public func << (lhs: TwoCmplt, shift: Int) -> TwoCmplt {
    let mask = (1 << lhs.nbits) - 1
    let masked = lhs.value & mask
    let shifted = masked << shift
    let shftMsk = ((1<<shift)-1)<<lhs.nbits
    let overFlow = (lhs.signed && ((shftMsk & shifted) != shftMsk))
        || (!lhs.signed && ((shftMsk & shifted) != 0))
        ? true : false
    let val = shifted & mask  // truncate to lhs.nbits
    var ocmplt = TwoCmplt(value: val, nbits: lhs.nbits, prec: lhs.prec,
        signed: lhs.signed)
    if overFlow { ocmplt.ovflw = true }
    return ocmplt
    }

/**
 * Overloads >> arithmetic shift right.
 * The operations extends sign bits if lhs is signed and negative
 * similar to the >>> operator in verilog.
 *
 * - Returns new: TwoCmplt after shift
 */
public func >> (lhs: TwoCmplt, shift: Int) -> TwoCmplt {
    // Perform right shift with sign extensio if signed and MSB==1
    let mask = (1 << lhs.nbits) - 1
    let signBit = 1 << (lhs.nbits - 1)
    let masked = lhs.value & mask
    let shifted = masked >> shift
    let val: Int
    if lhs.signed && ((masked & signBit) != 0) {
        // Sign bit was set, so fill the upper 'shift' bits with ones
        let fill = ((1 << shift) - 1) << (lhs.nbits - shift)
        val = (shifted | fill) & mask
    } else {
        // Sign bit not set, upper bits remain zeros
        val = shifted
    }
    let ocmplt = TwoCmplt(value: val, nbits: lhs.nbits, prec: lhs.prec, signed: lhs.signed)
    return ocmplt
}

/**
 * Overload * function to multiply lhs by rhs when the rhs is an Int.
 * The nbits of the returned product will be the same as lhs.nbits.
 * The prec of the product is equal to lhs.prec
 *
 * - Parameter lhs: TwoCmplt argument to be "multiplied"
 * - Parameter rhs: The other TwoCmplt argument to be "multiplies"
 *
 * - Returns TwoCmplt: having nbits and prec the same as lhs
 */

public func * (lhs: TwoCmplt, rhs: Int) -> TwoCmplt {
    // Perform two’s complement addition
    let lval = lhs.toInt()
    let rval = rhs
    let rbitcnt = rhs.bitWidth - rhs.leadingZeroBitCount
    let nbits = lhs.nbits + rbitcnt
    let oprec = lhs.prec
    let val = lval * rval
    let oval: Int = val&((1<<nbits)-1)
    let signed = lhs.signed
    let ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    return ocmplt
}

/**
 * Overload / function to divide lhs by rhs when the rhs is an Int.
 * The nbits of the returned product will be the same as lhs.nbits.
 * The prec of the product is equal to lhs.prec
 *
 * - Parameter lhs: TwoCmplt argument to be "divided"
 * - Parameter rhs: The other TwoCmplt argument to be the divisor
 *
 * - Returns TwoCmplt: having nbits and prec the same as lhs
 */

public func / (lhs: TwoCmplt, rhs: TwoCmplt) -> TwoCmplt {
    // Perform two’s complement addition
    let lval = lhs.toInt()
    let rval = rhs.toInt()
    let nbits = lhs.nbits
    let oprec = lhs.prec
    let val: Int
    if rval == 0 {
        if lhs.signed {
            val = lhs > 0 ? (1<<(lhs.nbits - 1)) - 1 : -(1<<(lhs.nbits - 1))
        } else {
            val = (1<<lhs.nbits) - 1
        }
    } else {
        val = lval / rval
    }
    let oval: Int = val&((1<<nbits)-1)
    let signed = lhs.signed
    let ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    return ocmplt
}

/**
 * Overload & function to module divide lhs by rhs when the rhs is an Int.
 * The nbits of the returned product will be the same as lhs.nbits.
 * The prec of the product is equal to lhs.prec
 *
 * - Parameter lhs: TwoCmplt argument to be the divisor"
 * - Parameter rhs: The other TwoCmplt argument to be "multiplies"
 *
 * - Returns TwoCmplt: having nbits and prec the same as lhs
 */

public func % (lhs: TwoCmplt, rhs: TwoCmplt) -> TwoCmplt {
    // Perform two’s complement addition
    let lval = lhs.toInt()
    let rval = rhs.toInt()
    let nbits = lhs.nbits
    let oprec = lhs.prec
    let val: Int
    val = lval % rval
    let oval: Int = val&((1<<nbits)-1)
    let signed = lhs.signed
    let ocmplt = TwoCmplt(value: oval, nbits: nbits, prec: oprec, signed: signed)
    return ocmplt
}

/**
 * Overload unary ~ operator which inverts all the bits of the reg argument.
 *
 * - Parameter reg: contains the bits to be inverted
 *
 * - Returns TwoCmplt: with inverted bits
 */
public prefix func ~ (reg: TwoCmplt) -> TwoCmplt {
    let msk = (1 << reg.nbits) - 1
    let val = (~reg.value) & msk
    let ocmplt = TwoCmplt(value: val, nbits: reg.nbits, prec: reg.prec, signed: reg.signed)
    return ocmplt
}

/**
 * Overload  & function to do "and" of bits of lhs and rhs.
 * Generally lhs and rhs will be the same size. It's up to the user
 * to ensure equal sizes; it's not enforced. 
 *
 * - Parameter lhs: TwoCmplt arguments to "anded"
 * - Parameter rhs: The other TwoCmplt value to be "anded"
 *
 *   Normally, it should be ensured that rhs.nbits == lhs.nbits; not checked
 *
 * - Returns TwoCmplt: having nbits and prec the same as lhs
 */
public func & (lhs: TwoCmplt, rhs: TwoCmplt) -> TwoCmplt {
    let val = lhs.value & rhs.value
    let ocmplt = TwoCmplt(value: val, nbits: lhs.nbits, prec: lhs.prec, signed: lhs.signed)
    return ocmplt
}

/**
 * Overload  & function to do "and" of bits of lhs and rhs where rhs is Int.
 *
 * - Parameter lhs: TwoCmplt arguments to "anded"
 * - Parameter rhs: An Int value to be "anded"
 *
 * - Returns TwoCmplt: having nbits and prec the same as lhs
 */
public func & (lhs: TwoCmplt, rhs: Int) -> TwoCmplt {
    let val = lhs.value & rhs
    let ocmplt = TwoCmplt(value: val, nbits: lhs.nbits, prec: lhs.prec, signed: lhs.signed)
    return ocmplt
}

/**
 * overload  | function to do "or" of bits of lhs and rhs
 * generally lhs and rhs will be the same size. It's up to the user
 * to ensure this; it's not enforced. 
 *
 * - Parameter lhs: TwoCmplt argument to be "ored"
 * - Parameter rhs: The other TwoCmplt value to be "ored"
 *
 * - Returns TwoCmplt: having nbits and prec the same as lhs
 */
public func | (lhs: TwoCmplt, rhs: TwoCmplt) -> TwoCmplt {
    let val = lhs.value | rhs.value
    let ocmplt = TwoCmplt(value: val, nbits: lhs.nbits, prec: lhs.prec, signed: lhs.signed)
    return ocmplt
}

/**
 * Overload  | function to do "or" of bits of lhs and rhs where rhs is Int.
 *
 * - Parameter lhs: TwoCmplt arguments to "ored"
 * - Parameter rhs: An Int value to be "ored"
 *
 * - Returns TwoCmplt: having nbits and prec the same as lhs
 */
public func | (lhs: TwoCmplt, rhs: Int) -> TwoCmplt {
    let val = lhs.value | rhs
    let ocmplt = TwoCmplt(value: val, nbits: lhs.nbits, prec: lhs.prec, signed: lhs.signed)
    return ocmplt
}

/**
 * overload  ^ function to do "exor" of bits of lhs and rhs
 * generally lhs and rhs will be the same size. It's up to the user
 * to ensure this; it's not enforced. 
 *
 * - Parameter lhs: TwoCmplt argument to be "exored"
 * - Parameter rhs: The other TwoCmplt argument to be "exored"
 *
 * - Returns TwoCmplt: having nbits and prec the same as lhs
 */
public func ^ (lhs: TwoCmplt, rhs: TwoCmplt) -> TwoCmplt {
    let val = lhs.value ^ rhs.value
    let ocmplt = TwoCmplt(value: val, nbits: lhs.nbits, prec: lhs.prec, signed: lhs.signed)
    return ocmplt
}

/**
 * Overload  ^ function to do "exor" of bits of lhs and rhs where rhs is Int.
 *
 * - Parameter lhs: TwoCmplt arguments to "exored"
 * - Parameter rhs: An Int value to be "exored"
 *
 * - Returns TwoCmplt: having nbits and prec the same as lhs
 */
public func ^ (lhs: TwoCmplt, rhs: Int) -> TwoCmplt {
    let val = lhs.value ^ rhs
    let ocmplt = TwoCmplt(value: val, nbits: lhs.nbits, prec: lhs.prec, signed: lhs.signed)
    return ocmplt
}

/**
 * This is a unary operator to do an "and" reduction of bits of parameter reg.
 * The preferred symbol "&" could not be used as it is used in Swift for inout
 * parameters.
 *
 * - Parameter reg: contains the bits to be "anded"
 *
 * - Returns Int:
 */
public prefix func && (reg: TwoCmplt) -> Int {
    // Note we can't use the preferred '&' as it is used for inout arguments of funcs
    let mask = (1<<reg.nbits) - 1
    let rtrn = (reg.value & mask) == mask ? 1 : 0
    return rtrn
}

/**
 * Overload | unary operator to do an "or" reduction of the bits of reg argument.
 *
 * - Parameter reg: contains the bits to be "ored"
 *
 * - Returns Int:
 */
public prefix func | (reg: TwoCmplt) -> Int {
    let rtrn = reg.value == 0 ? 0 : 1
    return rtrn
}

/**
 * Overload unary ^ operator to do an "exor" reduction of bits of reg
 * returns a 1 if there are an odd number of 1's in reg
 *
 * - Parameter reg: contains the bits to be "anded"
 *
 * - Returns Int:
 */
public prefix func ^ (reg: TwoCmplt) -> Int {
    let nones = reg.value.nonzeroBitCount
    let rtrn = (nones % 2) == 0 ? 0 : 1
    return rtrn
}


