// Sources/Shared/TwosCmplt.swift

/**
 * @file  TwosCmplt.swift
 * A library for using Two's Complement Arithmetic Using a Swift struct.
 *
 * This file contains the TwoCmplt struct that includes most properties
 * for implementing two's complement arithmetic.
 *
 * @author  Kenneth Martin
 * @date    2025-10-21
 * @version 0.1
 */

import Foundation

@inlinable
public func msk_(_ n: Int) -> Int {
    (1 << n) - 1
}

/** 
 * struct TwoCmplt
 * Contains a two's complement integer.
 * - Parameter value: The exact bits for the integer; might be less than nbits.
 * - Parameter nbits: The number of bits used for the two's complement integer.
 * - Parameter prec: The number of lsbs having weightings less than 1
 * - Parameter signed: true if integer is signed.
 * - Parameter ovflw: true if an ovflw occured.
 * - Parameter crry: true if the operation generated an output crry
 */
public struct TwoCmplt: CustomStringConvertible, Equatable {
    nonisolated(unsafe) public static var glblStates: States?
    public var value: Int = 0  // always the two's complement value
    public var nbits: Int = 16 // should always be set
    public var prec: Int = 0 // often defaults to 0
    public var signed: Bool = false // effects carry extension
    public var ovflw: Bool = false // not necessarily cleared; for now clear if using
    public var crry: Bool = false // not usually set to 0 when no crry
    public var repr: String = ""

    /**
     * initialize two's complement variable setting the value using value:.
     *
     * - Parameter value: the initial value, can be specified in decimal, hex, binary, etc.
     * - Parameter nbits: the size of the two's complement integer
     * - Parameter prec: the precision of the interger, defaults to 0
     * - Parameter signed: defaults to false or unsigned
     * - Returns string: currently in hex format including leading 0's.
     */
    public init(value: Int, nbits: Int = 16, prec: Int = 0, signed: Bool = false) {
        /*
            value is always nbits long or less and is the two's complement value
            when value is less than zero, it's msb is a '1' and it is exactly n-bits long
            when value is unsigned or signed and positive, it
            might be less than nbits long
        */
        self.signed = signed
        if value < 0 {
           self.value = ((1 << nbits) + value)&((1<<nbits)-1)
           self.signed = true
        } else {
            self.value = value&((1<<nbits)-1)
        }

        self.nbits = nbits
        self.ovflw = false
        self.crry = false

        if !(prec == 0) {
            self.prec = prec
        } else {
            if !(States.precMode == .none) {
                switch States.precMode {
                case .oneNbl:
                    self.prec = 4
                case .twoNbl:
                    self.prec = 8
                default:
                    print("States.precMode: \(States.precMode)")
                }
            }
        }
    }

    /**
     * Initialize two's complement variable by specifying a Double, which is normally rounded
     * to an Int
     *
     * - Parameter value: the initial value, allows to be specified using double rounded to int
     * - Parameter nbits: the size of the two's complement integer
     * - Parameter prec: the precision of the interger, defaults to 0
     * - Parameter signed: defaults to false or unsigned
     * - Parameter rnd: if set to false uses truncation, default is true
     * - Returns string: currently in hex format including leading 0's.
     */
    public init(value: Double, nbits: Int = 16, prec: Int = 0, signed: Bool = false, rnd: Bool = true) {
        let val1 = value * Double(1<<prec)
        let var1 = (rnd == true) ? Int(val1.rounded()) : Int(val1)

        self.signed = signed
        if var1 < 0 {
           self.value = ((1<<nbits) + var1)&((1<<nbits)-1)
           self.signed = true
        } else {
            self.value = var1&((1<<nbits)-1)
        }

        self.nbits = nbits
        self.ovflw = false
        self.crry = false
        if !(prec == 0) {
            self.prec = prec
        } else {
            if !(States.precMode == .none) {
                switch States.precMode {
                case .oneNbl:
                    self.prec = 4
                case .twoNbl:
                    self.prec = 8
                default:
                    print("States.precMode: \(States.precMode)")
                }
            }
        }
    }

    /**
     * Initialize two's complement variable with the first argument being an Int without a label.
     *
     * - Parameter value: allows for specifying value without label
     * - Parameter nbits: is still needed unless default of 16 is okay, specified using a label
     * - Parameter prec: the number of LSB cosidered to have weighting less than 1
     * - Parameter signed: true if TwoCmplt.value is considered negative whein it MSB is 1
     */
    public init(_ value: Int, nbits: Int = 16, prec: Int = 0, signed: Bool = false) {
        self.init(value: value, nbits: nbits, prec: prec, signed: signed)
    }

    /**
     * @fn description
     * description of two's complement variable.
     *
     * - Parameter none:.
     * - Returns string: currently in hex format including leading 0's.
     */
    public var description: String {
        let hex = String(self.value, radix: 16)
        let width = self.nbits
        let newHex = String(repeating: "0", count: ((width + 3)/4 - hex.count)) + hex
        let strng = "value: 0x\(newHex), nbits: \(self.nbits), prec: \(self.prec), signed: \(self.signed)"
        return strng
    }

    /**
     * display two's complement variable with binary representation and leading 0's.
     *
     * It does not take any parameters
     *
     * - Returns String:
     */
    public func display() -> String {
        let bnry = String(self.value, radix: 2)
        let width = self.nbits
        let newBnry = String(repeating: "0", count: (width - bnry.count)) + bnry
        let strng = "value: 0b\(newBnry), nbits: \(self.nbits), prec: \(self.prec), signed: \(self.signed)"
        return strng
    }

    /**
     * Multiply a two's complement integers and then rshifts by the nbits
     * specified by rshift. This is a convenience function for not requiring
     * States.multiplyMode = .truncate and then back to States.multiplyMode = .full.
     *
     * - Parameter lhs: a TwoCmplt value
     * - Parameter rhs: a TwoCmplt value
     * - Parameter rshift: the number of bits to shift by
     *
     * - Returns: new TwoCmplt value
     */
    public static func multN(lhs: TwoCmplt, rhs: TwoCmplt, rshift: Int) -> TwoCmplt {
        let nbits = lhs.nbits
        let prec = lhs.prec
        let rshift = rshift
        let signed = lhs.signed
        var val = lhs.toInt() * rhs.value // This preserves sign
        val = (States.roundMode == .round) ? val + (1<<(rshift - 1)) : val
        val = val >> rshift // This extends sign if negative
        let ocmplt = TwoCmplt(value: val, nbits: nbits, prec: prec, signed: signed)
        return ocmplt
    }

    /**
     * Converts the TwoCmplt to it's Int equivalent.
     * If the TwoCmplt is signed with it's msb a 1, it returns a negative Int
     *
     * - Returns: the TwoCmplt value as an Int discarding bits when self.prec > 0
     */
    public func toInt() -> Int {
        let x = self.value
        let n = self.nbits
        let val: Int
        val = self.signed ? (x&((1<<(n-1))-1)) - (x&(1<<(n-1))) >> self.prec : x >> self.prec
        return val
    }

    /**
     * Converts the TwoCmplt to it's Double equivalent.
     * If the TwoCmplt is signed with it's msb a 1, it returns a negative Double
     *
     * - Returns: the TwoCmplt value as an Double with prec bits forming fractional part
     */
    public func toDbl() -> Double {
        let x = self.value
        let n = self.nbits
        let val1 = Double((x&((1<<(n-1))-1)) - (x&(1<<(n-1))))
        let val2 = val1/pow(2.0, Double(self.prec))
        return val2
    }

    /**
     * Selects single bit from a TwoCmplt.
     *
     * - Parameter n: the bit position
     *
     * - Returns:  Int
     */
    public func selBit(n: Int) -> Int {
        let bt = (self.value >> n)&1
        return bt
    }

    /**
     * Selects bits from a TwoCmplt, the selected bits are always unsigned.
     *
     * - Parameter n1: the bit position of the msb
     * - Parameter n2: the bit position of the lsb
     *
     * - Returns:  TwoCmplt, unsigned and prec=0
     */
    public func selBits(n1: Int, n2: Int) -> TwoCmplt {
        assert(n1 >= n2) // for example selecting 1 bit from right, n1 = 1, n2 = 1
        let sz = n1 - n2 + 1
        let msk = (1<<sz) - 1
        let bts = (self.value >> n2)&msk
        let rtrn = TwoCmplt(value: bts, nbits: sz)
        return rtrn
    }

    /**
     * Sets bit of a TwoCmplt.
     *
     * - Parameter n1: the position of the bit to be set
     *
     * - Returns:  TwoCmplt, unsigned and prec=0
     */
    @discardableResult
    public mutating func setBit(_ val: Int, n1: Int) -> TwoCmplt {
        let msk = 1
        let bt = val&msk
        let newVal = self.toInt()&(~(msk<<n1)) | (bt<<n1)
        self.value = newVal
        return self
    }

    /**
     * Sets bits of a TwoCmplt, the set bits are always unsigned.
     *
     * - Parameter n1: the bit position of the msb
     * - Parameter n2: the bit position of the lsb
     *
     * - Returns:  TwoCmplt, unsigned and prec=0
     */
    @discardableResult
    public mutating func setBits(_ val: Int, n1: Int, n2: Int) -> TwoCmplt {
        assert(n1 >= n2) // for example selecting 1 bit from right, n1 = 1, n2 = 1
        let sz = n1 - n2 + 1
        let msk = msk_(sz)
        let bts = val&msk
        let newVal = self.toInt()&(~(msk<<n2)) | (bts<<n2)
        self.value = newVal
        return self
    }

    /**
     * Gets all the bits of a TwoCmplt.
     * The returned bits are unsigned and have prec=0.
     *
     * - Returns:  TwoCmplt always unsigned and prec=0
     */
    public func getBts() -> TwoCmplt {
        let ocmplt = TwoCmplt(value: self.value, nbits: self.nbits, prec: 0, signed: false)
        return ocmplt
    }

    /**
     * change the prec of self
     * The returned bits are unsigned and have prec=0
     *
     * - Parameter prec: The new precision
     *
     * - Returns TwoCmplt: Note: it can be ignored.
     */
    @discardableResult
    public mutating func setPrec(prec: Int) -> TwoCmplt {
        self.prec = prec
        let ocmplt = TwoCmplt(value: self.value, nbits: self.nbits, prec: prec, signed: self.signed)
        return ocmplt
    }

    /**
     * set TwoCmplt to Int value
     *
     * - Parameter value: The value to set
     *
     * - Returns TwoCmplt: Note: it can be ignored.
     */
    @discardableResult
    public mutating func set(_ value: Int) -> TwoCmplt {
        let nbits = self.nbits
        if (value < 0) && (self.signed == true) {
           self.value = ((1 << nbits) + value)&((1<<nbits)-1)
        } else {
            self.value = value&((1<<nbits)-1)
        }
        return self
    }

    /**
     * change the nbits of self
     *
     * - Parameter nbits: The new number of bits. If signed and negative, sign bit is extended
     *
     * - Returns TwoCmplt: Note: it can be ignored.
     */
    @discardableResult
    public mutating func setNbits(_ nbits: Int) -> TwoCmplt {
        let val = self.toInt()
        let newCmplt: TwoCmplt = TwoCmplt(value: val, nbits: nbits, prec: self.prec, signed: self.signed)
        self = newCmplt
        return newCmplt
    }

    /**
     * concatanate bits to self
     *
     * - Parameter reg: is joined to the right of self
     *   before doing the concatanation, the bits of self are shifted to
     *   to give room
     * 
     *   The returned signed value is the same as reg.signed
     *
     * - Returns TwoCmplt: with nbits large enough to hold both sets of bits
     */
    public func joinBts(reg: TwoCmplt) -> TwoCmplt {
        let val1 = self.value<<reg.nbits
        let val2 = val1 | reg.value
        let nbits = self.nbits + reg.nbits
        let ocmplt = TwoCmplt(value: val2, nbits: nbits, prec: 0, signed: reg.signed)
        return ocmplt
    }

    /**
     * concatanates a list of TwoCmplt's or Int's into a single TwoCmplt
     *
     * - Parameter segs: A list of [MixedValue] enums
     *
     * - Returns TwoCmplt: which is concatentation of all values in the list
     */
    public static func concatSegs(segs: [MixedValue]) -> TwoCmplt {
        /*
        Note: when concatanating segments, the result is alway unsigned with prec = 0.
        This can be modified seperately if required.
        Segments are concatanated in the order they appear in the array.
        */
        var ocmplt: TwoCmplt = TwoCmplt(value: 0, nbits:0)
        for seg in segs {
            switch seg {
            case .int(let intNmb):
                let segn = intNmb.bitWidth - intNmb.leadingZeroBitCount
                ocmplt.value = (ocmplt.value << segn) | intNmb&((1<<segn) - 1)
                ocmplt.nbits = ocmplt.nbits + segn
            case .two(let twoVal):
                ocmplt.value = (ocmplt.value << twoVal.nbits) | twoVal.value
                ocmplt.nbits = ocmplt.nbits + twoVal.nbits
            }
        }
        ocmplt.signed = false
        ocmplt.prec = 0
        return ocmplt
    }

    /**
     * Absolute value of self.value.
     *
     * - Returns:  TwoCmplt were value is always positive
     */
    public func abs() -> TwoCmplt {
        var val: Int = self.toInt()
        val = val < 0 ? -val : val
        let ocmplt: TwoCmplt = TwoCmplt(value: val, nbits: self.nbits)
        return ocmplt
    }


    /**
     * Returns the String representation of the TwoCmplt value using binary notation.
     *
     * - Returns:  String in binary format; note no leading "0b"
     */
    public func bin() -> String {
        let bnry = String(self.value, radix: 2)
        let width = self.nbits
        let binaryString = String(repeating: "0", count: (width - bnry.count)) + bnry
        return binaryString
    }

    /**
     * Returns the String representation of the TwoCmplt value using hex notation.
     *
     * - Returns:  String in hex format; note no leading "0x"
     */
    // public mutating func hex() -> String {
    public func hex() -> String {
        let hex = String(self.value, radix: 16)
        let width = self.nbits
        let hexString = String(repeating: "0", count: ((width + 3)/4 - hex.count)) + hex
        // self.repr = hexString
        return hexString
    }

}
