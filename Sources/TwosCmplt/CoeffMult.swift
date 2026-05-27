// Sources/SharedTypes/CoeffMltply.swift
/**
 * CoeffMult.swift
 * An example of using the TwoCmplt struct in simulating multiplication by fixed coefficients.
 * This is an update from CoeffMltply.swift where the inversions required when the signal is negative
 * are more efficient taking advantage of the empty bit position of Cry[0]
 *
 * Note: if this technique is used with Carry-Save adders, coefficient multiplies with 24 bit
 * signals have only 3 levels of carry-save logic (i.e. 3 input exor and ab | ac | bc logic)
 * and a generate/propogate adder, which is not that much more delay than just the adder.
 * Normally, a generate/propogate adder is used as a reasonable compromise between speed and area.
 *
 * This example uses a 16-bit signed signal path and 20-bit registers and adders
 * The coefficients are assumed to be unsigned positive values between 0 and
 * (1<<15) - 1. Each coefficient represents a fraction; the maximum of the coefficients is
 * ((1<<15)-1) / (1<<15). Sixteen 20-bit registers need to be pre-loaded with k*coeff, k = 0,..,15
 * At each multiplication, if the signal is negative, it is converted to a positive value, and then
 * after an unsigned multiplication, it is converted back to a negative value.
 * In the multiplication operation, 4 different values are added together to get the final result.
 * In a hardware implementation, the first two additions would occur in parallel, followed by adding
 * their outputs, so two cascaded levels of addition are required.
 * The values being added are determined by the unsigned signal nibbles, with each nibble being 4 bits
 * The 4-bit nibbles select one of the coefficient registers shifted right rshift, rshift = 0,4,8,12
 * depending on the nibble, going from the most significant nibble to the least significant nibble.
 * The selection is done using 20 16-bit to 1-bit multiplexors implemented using three levels of
 * 2 to 1 switched inverters.
 * After the summation, 8 is added to the sum, to implement rounding, and then the final output is
 * the sum shifted right by 4 bits.
 * This example includes a block to show how the coefficient registers could be slowly updated, once
 * every 16 signal values, for applications were the coefficients might be slowly adapting
 * Also, cs_mult() shows how the coefficient multiplication can be realized using carry-save adders
 * which save area as well as being fast, especially when combined with a generate/propogate adder.
 * 
 * @author  Kenneth Martin
 * @date    2025-10-22
 * @version 0.1
 */

import SharedTypes


let getSeg: @Sendable (Int, Int, Int) -> Int = { (val, n1, n2) in
    return (val >> n2) & ((1<<(n1 - n2 + 1)) - 1)
}

/// 
/// 
///   Contains properties and functions used to implement fixed coefficient multiplication.
/// 
///  - Parameter nbits: the nbits used for the summation and storing the coefficients
///  - Parameter nmbNibls: the input signal is grouped into 4-bit nibls. Note: the input
///    must have 4 less bits than the CoeffMlt
///  - Parameter coeffs: an array of TwoCmplt structs for storing k*coeff, k = 0,..,15
///  - Parameter shifts: an array of tuples used for shifting coeffs depending on which nibble
///  - Parameter bits: an array of tuples used in selecting the nibbles from the signal
///  - Parameter ready: a Bool value to indicate a set of coeffs has been loaded
///  - Parameter sync: a Bool that is high once each 16 signal values that can be used
///      for synchronizing the updating of the coefficients. The input to the uploading
///      block is changed when sync just goes to false
///  - Parameter k: the indic used in the coefficient update block
/// 
///  - Returns: new TwoCmplt value
///

public struct CoeffMult {
    public var nbits: Int = 20
    public var nmbNibls: Int
    public var coeffs: [TwoCmplt] = [] // array of TwoCmplt structs
    public var shifts: [Int] = []
    public var bits: [(Int, Int)] = []
    public var ready: Bool = false
    public var sync: Bool = true
    public var k: Int = 0
    public var coeff: TwoCmplt
    private var coeffSum: TwoCmplt
    private var updCoeffs: [TwoCmplt] = []

    /**
     * Initialize a CoeffMult struct used to simulate coefficient multiplicaton.
     * A guard was used to ensure nbits is divisible by 4, this is probably not worth the
     * complication and has been removed
     *
     * - Parameter value: The coefficient. Since unsigned coefficient is assumed, use coeff = (1<<(nbits-4)*K)
     *   where K is desired coefficient in Double < 1.0
     * - Parameter nbits: the size of the TwoCmplt used for the multiplication. The signal
     *   needs to be a multiple of 4, and nbits should be the signal size plus 4
     *
     */
    public init(value: Int, nbits: Int = 20) {
        /**
         * removed the guard as it made calling the multiply function too complicated
         * It is now the user's responsibility to ensure CoeffMlt is used with proper bit lengths.
         * The struct CoeffMlt must have nbits larger than the signal path nbits by exactly 4bits
         * That is: the signal bit length must be divisible by 4, and nbits must the signal length + 4
         *
        guard ((nbits - 4) % 4) == 0 else {
            return nil       // Initialization fails cleanly
        }
         */
        assert(((nbits - 4) % 4) == 0, "ERROR: CoeffMlt used with incompatible bit lengths")
        self.nbits = nbits

        self.nmbNibls = (nbits - 4)/4
        // self.nmbNibls = (nbits)/4
        self.shifts = Array(repeating: 0, count: nmbNibls)
        self.bits = Array(repeating: (0, 0), count: nmbNibls)
        var bit = nbits - 5
        for i in 0..<nmbNibls {
            // print("i =", i)
            self.shifts[i] = i*4
            self.bits[i] = (bit, bit - 3)
            bit -= 4
        }
        self.coeffs = Array(repeating: TwoCmplt(value: 0, nbits: nbits), count: 16)
        self.updCoeffs = Array(repeating: TwoCmplt(value: 0, nbits: nbits), count: 16)
        let val2 = value & (1<<(nbits-4) - 1) // Truncate in case coeff is too large ; 
        self.coeff = TwoCmplt(val2, nbits: nbits)
        self.coeffSum = TwoCmplt(0, nbits: nbits)

        for i in 0...15 {
            self.coeffs[i]=self.coeff*i
            self.coeffs[i].nbits = nbits
            // print("i: \(i): ", self.coeffs[i])
        }
    }

    /**
     * Initialize a CoeffMlt struct used to simulate coefficient multiplicaton.
     *
     * - Parameter coeff: The coefficient. Since unsigned coefficient is assumed, use coeff = (1<<(nbits-4)*K)
     *   where K is desired coefficient in Double < 1.0
     * - Parameter nbits: the size of the TwoCmplt used for the multiplication. The signal
     *   needs to be a multiple of 4, and nbits should be the signal size plus 4
     *
     * - Returns: new TwoCmplt struct
     */
    public init(_ coeff: Int, nbits: Int = 20) {
        self.init(value: coeff, nbits: nbits)
    }

    public static func * (signal: TwoCmplt, rhs: CoeffMult) -> TwoCmplt {
        assert( rhs.nbits == signal.nbits + 4, "ERROR: CoeffMlt used with incompatible bit lengths")
        let zero = TwoCmplt(value: 0, nbits: signal.nbits)
        let neg = (signal < zero) ? true : false
        let sig_unsgnd = neg ? -(signal.toInt()) : signal.toInt()

        let nmbNbls = rhs.nmbNibls

        var coeffSum: Int = 0
        var shift: Int = 0
        for i in stride(from: nmbNbls - 1, through: 0, by: -1) {
            let (n1, n2) = rhs.bits[i]
            let nibble = getSeg(sig_unsgnd, n1, n2)
            print("nibble: \(nibble)", sig_unsgnd, n1, n2)
            coeffSum = coeffSum + ((rhs.coeffs[nibble].value) << shift)
            shift += 4
        }
        coeffSum += (1<<(shift - 1))
        coeffSum = coeffSum >> shift
        let Sum: TwoCmplt = TwoCmplt(value: coeffSum, nbits: signal.nbits, prec: signal.prec, signed: signal.signed)
        let out: TwoCmplt = neg ? -Sum : Sum
        return out
    }

    public func mult(_ signal: TwoCmplt) -> TwoCmplt {
        assert( self.nbits == signal.nbits + 4, "ERROR: CoeffMlt used with incompatible bit lengths")
        let zero = TwoCmplt(value: 0, nbits: signal.nbits)
        let neg = (signal < zero) ? true : false
        let sig_unsgnd = neg ? -(signal.toInt()) : signal.toInt()

        let nmbNbls = self.nmbNibls

        var coeffSum: Int = 0
        var shift: Int = 0
        for i in stride(from: nmbNbls - 1, through: 0, by: -1) {
            let (n1, n2) = self.bits[i]
            let nibble = getSeg(sig_unsgnd, n1, n2)
            print("nibble: \(nibble)", sig_unsgnd, n1, n2)
            coeffSum = coeffSum + ((self.coeffs[nibble].value) << shift)
            shift += 4
        }
        coeffSum += (1<<(shift - 1))
        coeffSum = coeffSum >> shift
        let Sum: TwoCmplt = TwoCmplt(value: coeffSum, nbits: signal.nbits, prec: signal.prec, signed: signal.signed)
        let out: TwoCmplt = neg ? -Sum : Sum
        return out
    }

    // Newest version uses two csAddp1's to do +1 twice for TwoCmplt inversion
    public func csMlt(_ signal: TwoCmplt) -> TwoCmplt {
        assert( self.nbits == signal.nbits + 4, "ERROR: CoeffMlt used with incompatible bit lengths")
        let zero = TwoCmplt(value: 0, nbits: signal.nbits)
        let neg = (signal < zero) ? true : false
        let negInt = (signal < zero) ? 1 : 0
        let sigInvrt = neg ? (~signal).toInt() : signal.toInt()

        var s0 = TwoCmplt(0, nbits: 24), c0 = TwoCmplt(0, nbits: 24)
        var s1 = TwoCmplt(0, nbits: 24), c1 = TwoCmplt(0, nbits: 24)
        var s2 = TwoCmplt(0, nbits: 24), c2 = TwoCmplt(0, nbits: 24)
        var s3 = TwoCmplt(0, nbits: 24), c3 = TwoCmplt(0, nbits: 24)
        var s4 = TwoCmplt(0, nbits: 24), c4 = TwoCmplt(0, nbits: 24)
        var s5 = TwoCmplt(0, nbits: 24), c5 = TwoCmplt(0, nbits: 24)

        var coeffSum = TwoCmplt(0, nbits: 20, signed: true)

        if self.nbits == 24 {
            let val0 = (self.coeffs[getSeg(sigInvrt, 3, 0)].value) >> 16
            let val1 = (self.coeffs[getSeg(sigInvrt, 7, 4)].value) >> 12
            let val2 = (self.coeffs[getSeg(sigInvrt, 11, 8)].value) >> 8
            let val3 = (self.coeffs[getSeg(sigInvrt, 15, 12)].value) >> 4
            let val4 = (self.coeffs[getSeg(sigInvrt, 19, 16)].value) >> 0
            let val5 = self.coeff.value >> 16

            (s0, c0) = TwoCmplt.csAdd(csin: [val4, val3, val2], nbits: 24)
            (s1, c1) = TwoCmplt.csAdd(csin: [s0.value, c0.value, val1], nbits: 24)
            (s2, c2) = TwoCmplt.csAdd(csin: [s1.value, c1.value, val0], nbits: 24)
            // csAddp1 adds +self.coeff.value >> 16 when neg == 1 before making negative
            // This corrects for the fact we are using ~input rather than -input.
            (s3, c3) = TwoCmplt.csAddp1(csin: [s2.value, c2.value, val5], nbits: 24, neg: negInt)
            // we next use a "csAddp1()" to add 2 so we don't need to do it in the adder
            // we might change this to be in adder
            (s4, c4) = neg ? (~s3, ~c3) : (s3, c3)
            (s5, c5) = TwoCmplt.csAddp1(csin: [s4.value, c4.value, 0x2], nbits: 24, neg: negInt)
            // let coSm = neg ? (~s4 + ~c4) : s3 + c3 // note: in this version +2 is done using a csAddp1
            let coSm = s5 + c5
            coeffSum = coSm >> 4
            coeffSum.setNbits(20)

        } else if (self.nbits == 20) {
            let val0 = (self.coeffs[getSeg(sigInvrt, 3, 0)].value) >> 12
            let val1 = (self.coeffs[getSeg(sigInvrt, 7, 4)].value) >> 8
            let val2 = (self.coeffs[getSeg(sigInvrt, 11, 8)].value) >> 4
            let val3 = (self.coeffs[getSeg(sigInvrt, 15, 12)].value) >> 0
            let val4 = self.coeff.value >> 12

            (s0, c0) = TwoCmplt.csAdd(csin: [val3, val2, val1], nbits: 20)
            (s1, c1) = TwoCmplt.csAdd(csin: [s0.value, c0.value, val0], nbits: 20)
            (s2, c2) = TwoCmplt.csAddp1(csin: [s1.value, c1.value, val4], nbits: 20, neg: negInt)
            let coSm = neg ? (~s2 + ~c2 + 2) : s2 + c2
            coeffSum = coSm >> 4
            coeffSum.setNbits(16)
        } else if (self.nbits == 16) {
            let val0 = (self.coeffs[getSeg(sigInvrt, 3, 0)].value) >> 8
            let val1 = (self.coeffs[getSeg(sigInvrt, 7, 4)].value) >> 4
            let val2 = (self.coeffs[getSeg(sigInvrt, 11, 8)].value) >> 0
            let val3 = self.coeff.value >> 8

            (s0, c0) = TwoCmplt.csAdd(csin: [val2, val1, val0], nbits: 16)
            (s1, c1) = TwoCmplt.csAddp1(csin: [s0.value, c0.value, val3], nbits: 16, neg: negInt)
            let coSm = neg ? (~s1 + ~c1 + 2) : s1 + c1
            coeffSum = coSm >> 4
            coeffSum.setNbits(12)
        } else {
            coeffSum = TwoCmplt(0, nbits: 20, signed: true)
        }

        // let out: TwoCmplt = neg ? -coeffSum : coeffSum
        let out = coeffSum
        return out
    }

    public func csMult(_ signal: TwoCmplt) -> TwoCmplt {
        assert( self.nbits == signal.nbits + 4, "ERROR: CoeffMlt used with incompatible bit lengths")
        let zero = TwoCmplt(value: 0, nbits: signal.nbits)
        let neg = (signal < zero) ? true : false
        let negInt = (signal < zero) ? 1 : 0
        let sigInvrt = neg ? (~signal).toInt() : signal.toInt()

        var s0 = TwoCmplt(0, nbits: 24), c0 = TwoCmplt(0, nbits: 24)
        var s1 = TwoCmplt(0, nbits: 24), c1 = TwoCmplt(0, nbits: 24)
        var s2 = TwoCmplt(0, nbits: 24), c2 = TwoCmplt(0, nbits: 24)
        var s3 = TwoCmplt(0, nbits: 24), c3 = TwoCmplt(0, nbits: 24)

        var coeffSum = TwoCmplt(0, nbits: 20, signed: true)

        if self.nbits == 24 {
            let val0 = (self.coeffs[getSeg(sigInvrt, 3, 0)].value) >> 16
            let val1 = (self.coeffs[getSeg(sigInvrt, 7, 4)].value) >> 12
            let val2 = (self.coeffs[getSeg(sigInvrt, 11, 8)].value) >> 8
            let val3 = (self.coeffs[getSeg(sigInvrt, 15, 12)].value) >> 4
            let val4 = (self.coeffs[getSeg(sigInvrt, 19, 16)].value) >> 0
            let val5 = self.coeff.value >> 16

            (s0, c0) = TwoCmplt.csAdd(csin: [val4, val3, val2], nbits: 24)
            (s1, c1) = TwoCmplt.csAdd(csin: [s0.value, c0.value, val1], nbits: 24)
            (s2, c2) = TwoCmplt.csAdd(csin: [s1.value, c1.value, val0], nbits: 24)
            // csAddp1 adds +self.coeff.value >> 16 when neg == 1 before making negative
            // This corrects for the fact we are using ~input rather than -input.
            (s3, c3) = TwoCmplt.csAddp1(csin: [s2.value, c2.value, val5], nbits: 24, neg: negInt)
            let coSm = neg ? (~s3 + ~c3 + 2) : s3 + c3  // note we have to add 2 to implement "-"
            coeffSum = coSm >> 4
            coeffSum.setNbits(20)

        } else if (self.nbits == 20) {
            let val0 = (self.coeffs[getSeg(sigInvrt, 3, 0)].value) >> 12
            let val1 = (self.coeffs[getSeg(sigInvrt, 7, 4)].value) >> 8
            let val2 = (self.coeffs[getSeg(sigInvrt, 11, 8)].value) >> 4
            let val3 = (self.coeffs[getSeg(sigInvrt, 15, 12)].value) >> 0
            let val4 = self.coeff.value >> 12

            (s0, c0) = TwoCmplt.csAdd(csin: [val3, val2, val1], nbits: 20)
            (s1, c1) = TwoCmplt.csAdd(csin: [s0.value, c0.value, val0], nbits: 20)
            (s2, c2) = TwoCmplt.csAddp1(csin: [s1.value, c1.value, val4], nbits: 20, neg: negInt)
            let coSm = neg ? (~s2 + ~c2 + 2) : s2 + c2
            coeffSum = coSm >> 4
            coeffSum.setNbits(16)
        } else if (self.nbits == 16) {
            let val0 = (self.coeffs[getSeg(sigInvrt, 3, 0)].value) >> 8
            let val1 = (self.coeffs[getSeg(sigInvrt, 7, 4)].value) >> 4
            let val2 = (self.coeffs[getSeg(sigInvrt, 11, 8)].value) >> 0
            let val3 = self.coeff.value >> 8

            (s0, c0) = TwoCmplt.csAdd(csin: [val2, val1, val0], nbits: 16)
            (s1, c1) = TwoCmplt.csAddp1(csin: [s0.value, c0.value, val3], nbits: 16, neg: negInt)
            let coSm = neg ? (~s1 + ~c1 + 2) : s1 + c1
            coeffSum = coSm >> 4
            coeffSum.setNbits(12)
        } else {
            coeffSum = TwoCmplt(0, nbits: 20, signed: true)
        }

        // let out: TwoCmplt = neg ? -coeffSum : coeffSum
        let out = coeffSum
        return out
    }

    public func cs_mult(_ signal: TwoCmplt) -> TwoCmplt {
        assert( self.nbits == signal.nbits + 4, "ERROR: CoeffMlt used with incompatible bit lengths")
        let zero = TwoCmplt(value: 0, nbits: signal.nbits)
        let neg = (signal < zero) ? true : false
        let sig_unsgnd = neg ? -(signal.toInt()) : signal.toInt()

        var s0 = TwoCmplt(0, nbits: 24), c0 = TwoCmplt(0, nbits: 24)
        var s1 = TwoCmplt(0, nbits: 24), c1 = TwoCmplt(0, nbits: 24)
        var s2 = TwoCmplt(0, nbits: 24), c2 = TwoCmplt(0, nbits: 24)

        var coeffSum = TwoCmplt(0, nbits: 20, signed: true)

        if self.nbits == 24 {
            let val0 = (self.coeffs[getSeg(sig_unsgnd, 3, 0)].value) >> 16
            let val1 = (self.coeffs[getSeg(sig_unsgnd, 7, 4)].value) >> 12
            let val2 = (self.coeffs[getSeg(sig_unsgnd, 11, 8)].value) >> 8
            let val3 = (self.coeffs[getSeg(sig_unsgnd, 15, 12)].value) >> 4
            let val4 = (self.coeffs[getSeg(sig_unsgnd, 19, 16)].value) >> 0

            (s0, c0) = TwoCmplt.csAdd(csin: [val4, val3, val2], nbits: 24)
            (s1, c1) = TwoCmplt.csAdd(csin: [s0.value, c0.value, val1], nbits: 24)
            (s2, c2) = TwoCmplt.csAdd(csin: [s1.value, c1.value, val0], nbits: 24)
            coeffSum = (((s2 + c2) >> 3) + 1) >> 1
            coeffSum.setNbits(20)
        } else if (self.nbits == 20) {
            let val0 = (self.coeffs[getSeg(sig_unsgnd, 3, 0)].value) >> 12
            let val1 = (self.coeffs[getSeg(sig_unsgnd, 7, 4)].value) >> 8
            let val2 = (self.coeffs[getSeg(sig_unsgnd, 11, 8)].value) >> 4
            let val3 = (self.coeffs[getSeg(sig_unsgnd, 15, 12)].value) >> 0

            (s0, c0) = TwoCmplt.csAdd(csin: [val3, val2, val1], nbits: 20)
            (s1, c1) = TwoCmplt.csAdd(csin: [s0.value, c0.value, val0], nbits: 20)
            coeffSum = (((s1 + c1) >> 3) + 1) >> 1
            coeffSum.setNbits(16)
        } else if (self.nbits == 16) {
            let val0 = (self.coeffs[getSeg(sig_unsgnd, 3, 0)].value) >> 8
            let val1 = (self.coeffs[getSeg(sig_unsgnd, 7, 4)].value) >> 4
            let val2 = (self.coeffs[getSeg(sig_unsgnd, 11, 8)].value) >> 0

            (s0, c0) = TwoCmplt.csAdd(csin: [val2, val1, val0], nbits: 16)
            coeffSum = (((s0 + c0) >> 3) + 1) >> 1
            coeffSum.setNbits(12)
        } else {
            coeffSum = TwoCmplt(0, nbits: 20, signed: true)
        }

        let out: TwoCmplt = neg ? -coeffSum : coeffSum
        return out
    }

    /**
     * Directly set the coeff and internal coeffs of a CoeffMlt struct
     *
     * - Parameter coeff: The coefficient. Since unsigned coefficient is assumed, use coeff = (1<<(nbits-4)*K)
     *   where K is desired coefficient in Double < 1.0
     *
     */
    public mutating func setCoeff (_ coeff: TwoCmplt) {
        for i in 0...15 {
            self.coeffs[i]=coeff*i
            self.coeffs[i].nbits = nbits
            print("i: \(i): ", self.coeffs[i])
        }
    }

    /**
     * Sets the internal coeffs to i*coeff over i....15 iterations to have same timing
     * as expected hardware realization
     *
     * - Parameter coeff: The coefficient. Since unsigned coefficient is assumed, use coeff = (1<<(nbits-4)*K)
     *   where K is desired coefficient in Double < 1.0
     *
     */
    public mutating func coeffUpdate (_ coeff: TwoCmplt) {
        if self.k == 0 {
            self.sync = true
            self.coeff = coeff
            if (self.coeffSum != TwoCmplt(0, nbits: self.nbits)) { // update all coeffs[] registers
                for j in 0...15 {
                    self.coeffs[j] = self.updCoeffs[j]
                }
                self.ready = true
            }
            self.coeffSum = TwoCmplt(0, nbits: self.nbits)
            self.updCoeffs[0] = TwoCmplt(0, nbits: self.nbits)
            self.k += 1
        } else {
            self.sync = false
            self.coeffSum = self.coeffSum + self.coeff
            self.updCoeffs[k] = self.coeffSum
            self.k += 1
            self.k = self.k == 16 ? 0 : self.k
        }
    }

}

