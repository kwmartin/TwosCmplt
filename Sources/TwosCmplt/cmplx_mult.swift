/// 
/// 
///   Contains properties and functions used to implement fixed coefficient multiplication.
/// 
///  - Parameter nbits: the nbits used for the summation and storing the coefficients
///  - Parameter rcoeffs: coeffs for cos(theta)
///  - Parameter qcoeffs: coeffs for sin(theta)
///  - Parameter rcoeff: coeff used to set rcoeffs
///  - Parameter qcoeff: coeff used to set qcoeffs
/// 
///  - Returns: new TwoCmplt value
///

import SharedTypes

public struct CmplxMlt {
    public var nbits: Int
    public var sgnlQd: Int
    public var coeffQd: Int
    public var rcoeffs: [TwoCmplt] = [] // array of TwoCmplt structs
    public var qcoeffs: [TwoCmplt] = [] // array of TwoCmplt structs
    public var rcoeff: TwoCmplt
    public var qcoeff: TwoCmplt

    /**
     * Initialize a CmplxMlt struct used to simulate coefficient multiplicaton.
     *
     * - Parameter value: The coefficient. Since signed coefficient is assumed, use coeff = (1<<(nbits-5)*K)
     *   where K is desired coefficient in Double < 1.0
     * - Parameter nbits: the size of the TwoCmplt used for the multiplication. The signal
     *   needs to be a multiple of 4, and nbits should be the signal size plus 4
     *
     */
    public init(rval: Int, qval: Int, nbits: Int) {
        self.nbits = nbits
        self.rcoeffs = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 16)
        self.qcoeffs = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 16)
        self.sgnlQd = 0
        self.coeffQd = 0
        self.rcoeff = TwoCmplt(0, nbits: nbits, signed: true)
        self.qcoeff = TwoCmplt(0, nbits: nbits, signed: true)
        if rval > 0 && qval >= 0 {
            self.coeffQd = 0
            self.rcoeff = TwoCmplt(rval, nbits: nbits, signed: true)
            self.qcoeff = TwoCmplt(qval, nbits: nbits, signed: true)
        } else if rval <= 0 && qval > 0 { // pre-rotate by by -j
            self.coeffQd = 1
            self.rcoeff = TwoCmplt(qval, nbits: nbits, signed: true)
            self.qcoeff = TwoCmplt(-rval, nbits: nbits, signed: true)
        } else if rval < 0 && qval <= 0 { // pre-rotate by -1
            self.coeffQd = 2
            self.rcoeff = TwoCmplt(-rval, nbits: nbits, signed: true)
            self.qcoeff = TwoCmplt(-qval, nbits: nbits, signed: true)
        } else if rval >= 0 && qval < 0 { // pre-rotate by +j
            self.coeffQd = 3
            self.rcoeff = TwoCmplt(-qval, nbits: nbits, signed: true)
            self.qcoeff = TwoCmplt(rval, nbits: nbits, signed: true)
        }

        for i in 0...15 {
            self.rcoeffs[i]=rcoeff*i
            self.rcoeffs[i].nbits = nbits
            self.qcoeffs[i]=qcoeff*i
            self.qcoeffs[i].nbits = nbits
        }
    }

    public mutating func mult(_ cmplxIn: (TwoCmplt, TwoCmplt)) -> (TwoCmplt, TwoCmplt) {
        assert( self.nbits == cmplxIn.0.nbits + 4, "ERROR: CoeffMlt used with incompatible bit lengths")

        var (rsig, qsig) = (cmplxIn.0.toInt(), cmplxIn.1.toInt())

        if rsig > 0 && qsig >= 0 {
            self.sgnlQd = 0
        } else if rsig <= 0 && qsig > 0 { // pre-rotate by by -j
            self.sgnlQd = 1
            (rsig, qsig) = (qsig, -rsig)
        } else if rsig < 0 && qsig <= 0 { // pre-rotate by -1
            self.sgnlQd = 2
            (rsig, qsig) = (-rsig, -qsig)
        } else if rsig >= 0 && qsig < 0 { // pre-rotate by +j
            self.sgnlQd = 3
            (rsig, qsig) = (-qsig, rsig)
        }

        var srr = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 5)
        var crr = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 5)
        var srq = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 3)
        var crq = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 3)
 
        var sqq = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 5)
        var cqq = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 5)
        var sqr = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 3)
        var cqr = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 3)
 
        var valrr = Array(repeating: 0, count: 5)
        var valqq = Array(repeating: 0, count: 5)
        var valrq = Array(repeating: 0, count: 5)
        var valqr = Array(repeating: 0, count: 5)

        var coeffSumr = TwoCmplt(0, nbits: 24, signed: true)
        var coeffSumq = TwoCmplt(0, nbits: 24, signed: true)

        var rout = TwoCmplt(0, nbits: 20, signed: true)
        var qout = TwoCmplt(0, nbits: 20, signed: true)

        if self.nbits == 24 {
            valrr[0] = (self.rcoeffs[getSeg(rsig, 3, 0)].value) >> 16
            valrr[1] = (self.rcoeffs[getSeg(rsig, 7, 4)].value) >> 12
            valrr[2] = (self.rcoeffs[getSeg(rsig, 11, 8)].value) >> 8
            valrr[3] = (self.rcoeffs[getSeg(rsig, 15, 12)].value) >> 4
            valrr[4] = (self.rcoeffs[getSeg(rsig, 19, 16)].value) >> 0

            valqq[0] = (self.rcoeffs[getSeg(qsig, 3, 0)].value) >> 16
            valqq[1] = (self.rcoeffs[getSeg(qsig, 7, 4)].value) >> 12
            valqq[2] = (self.rcoeffs[getSeg(qsig, 11, 8)].value) >> 8
            valqq[3] = (self.rcoeffs[getSeg(qsig, 15, 12)].value) >> 4
            valqq[4] = (self.rcoeffs[getSeg(qsig, 19, 16)].value) >> 0

            valrq[0] = (self.qcoeffs[getSeg(qsig, 3, 0)].value) >> 16
            valrq[1] = (self.qcoeffs[getSeg(qsig, 7, 4)].value) >> 12
            valrq[2] = (self.qcoeffs[getSeg(qsig, 11, 8)].value) >> 8
            valrq[3] = (self.qcoeffs[getSeg(qsig, 15, 12)].value) >> 4
            valrq[4] = (self.qcoeffs[getSeg(qsig, 19, 16)].value) >> 0

            valqr[0] = (self.qcoeffs[getSeg(rsig, 3, 0)].value) >> 16
            valqr[1] = (self.qcoeffs[getSeg(rsig, 7, 4)].value) >> 12
            valqr[2] = (self.qcoeffs[getSeg(rsig, 11, 8)].value) >> 8
            valqr[3] = (self.qcoeffs[getSeg(rsig, 15, 12)].value) >> 4
            valqr[4] = (self.qcoeffs[getSeg(rsig, 19, 16)].value) >> 0

            (srq[0], crq[0]) = TwoCmplt.csAdd(csin: [valrq[4], valrq[3], valrq[2]], nbits: 24)
            (srq[1], crq[1]) = TwoCmplt.csAdd(csin: [srq[0].value, crq[0].value, valrq[1]], nbits: 24)
            (srq[2], crq[2]) = TwoCmplt.csAdd(csin: [srq[1].value, crq[1].value, valrq[0]], nbits: 24)

            (srr[0], crr[0]) = TwoCmplt.csAdd(csin: [valrr[4], valrr[3], valrr[2]], nbits: 24)
            (srr[1], crr[1]) = TwoCmplt.csAdd(csin: [srr[0].value, crr[0].value, valrr[1]], nbits: 24)
            (srr[2], crr[2]) = TwoCmplt.csAdd(csin: [srr[1].value, crr[1].value, valrr[0]], nbits: 24)
            (srr[3], crr[3]) = TwoCmplt.csA2S(csin: [srr[2].value, crr[2].value, crq[2].value], nbits: 24)
            (srr[4], crr[4]) = TwoCmplt.csA2S(csin: [srr[3].value, crr[3].value, srq[2].value], nbits: 24)

            (sqr[0], cqr[0]) = TwoCmplt.csAdd(csin: [valqr[4], valqr[3], valqr[2]], nbits: 24)
            (sqr[1], cqr[1]) = TwoCmplt.csAdd(csin: [sqr[0].value, cqr[0].value, valqr[1]], nbits: 24)
            (sqr[2], cqr[2]) = TwoCmplt.csAdd(csin: [sqr[1].value, cqr[1].value, valqr[0]], nbits: 24)

            (sqq[0], cqq[0]) = TwoCmplt.csAdd(csin: [valqq[4], valqq[3], valqq[2]], nbits: 24)
            (sqq[1], cqq[1]) = TwoCmplt.csAdd(csin: [sqq[0].value, cqq[0].value, valqq[1]], nbits: 24)
            (sqq[2], cqq[2]) = TwoCmplt.csAdd(csin: [sqq[1].value, cqq[1].value, valqq[0]], nbits: 24)
            (sqq[3], cqq[3]) = TwoCmplt.csAdd(csin: [sqq[2].value, cqq[2].value, cqr[2].value], nbits: 24)
            (sqq[4], cqq[4]) = TwoCmplt.csAdd(csin: [sqq[3].value, cqq[3].value, sqr[2].value], nbits: 24)

            coeffSumr = (((srr[4] + crr[4]) >> 3) + 1) >> 1
            coeffSumr.setNbits(20)

            coeffSumq = (((sqq[4] + cqq[4]) >> 3) + 1) >> 1
            coeffSumq.setNbits(20)
        } else {
            coeffSumr = TwoCmplt(0, nbits: 20, signed: true)
            coeffSumq = TwoCmplt(0, nbits: 20, signed: true)
        }

        if self.coeffQd == 1 {
            (coeffSumr, coeffSumq) = (-coeffSumq, coeffSumr)
        } else if self.coeffQd == 2 {
            (coeffSumr, coeffSumq) = (-coeffSumr, -coeffSumq)
        } else if self.coeffQd == 3 {
            (coeffSumr, coeffSumq) = (coeffSumq, -coeffSumr)
        }

        switch self.sgnlQd {
            case 0: (rout, qout) = (coeffSumr, coeffSumq)
            case 1: (rout, qout) = (-coeffSumq, coeffSumr)
            case 2: (rout, qout) = (-coeffSumr, -coeffSumq)
            case 3: (rout, qout) = (coeffSumq, -coeffSumr)
            default: (rout, qout) = (coeffSumr, coeffSumq)
        }

        return (rout, qout)
    }


/*
 * mult2 uses carry-save type adders and bit inversion to implement making Int's negative
 * versus using a full-adder or incrementer to implement the +1 to improve speed and minimize area.
 *
 * - Parameter cmplxIn: a Tuple with the real and imaginary inputs
 * 
 * - Returns: a Tuple with the real and imaginary outputs after multiplication
 */
    public mutating func mult2(_ cmplxIn: (TwoCmplt, TwoCmplt)) -> (TwoCmplt, TwoCmplt) {
        assert( self.nbits == cmplxIn.0.nbits + 4, "ERROR: CmplxMlt used with incompatible bit lengths")

        var rneg = 0
        var qneg = 0

        var (rsig, qsig) = (cmplxIn.0.toInt(), cmplxIn.1.toInt())

        if rsig > 0 && qsig >= 0 {
            self.sgnlQd = 0
            rneg = 0
            qneg = 0
        } else if rsig <= 0 && qsig > 0 { // pre-rotate by by -j
            self.sgnlQd = 1
            rneg = 1
            qneg = 0
            (rsig, qsig) = (qsig, ~rsig)
        } else if rsig < 0 && qsig <= 0 { // pre-rotate by -1
            self.sgnlQd = 2
            qneg = 1
            rneg = 1
            (rsig, qsig) = (~rsig, ~qsig)
        } else if rsig >= 0 && qsig < 0 { // pre-rotate by +j
            self.sgnlQd = 3
            rneg = 0
            qneg = 1
            (rsig, qsig) = (~qsig, rsig)
        }

        var srr = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 7)
        var crr = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 7)
        var srq = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 5)
        var crq = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 5)
 
        var sqq = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 7)
        var cqq = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 7)
        var sqr = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 5)
        var cqr = Array(repeating: TwoCmplt(value: 0, nbits: nbits, signed: true), count: 5)
 
        var valrr = Array(repeating: 0, count: 5)
        var valqq = Array(repeating: 0, count: 5)
        var valrq = Array(repeating: 0, count: 5)
        var valqr = Array(repeating: 0, count: 5)

        var coeffSumr = TwoCmplt(0, nbits: 24, signed: true)
        var coeffSumq = TwoCmplt(0, nbits: 24, signed: true)

        var rout = TwoCmplt(0, nbits: 20, signed: true)
        var qout = TwoCmplt(0, nbits: 20, signed: true)

        if self.nbits == 24 {
            valrr[0] = (self.rcoeffs[getSeg(rsig, 3, 0)].value) >> 16
            valrr[1] = (self.rcoeffs[getSeg(rsig, 7, 4)].value) >> 12
            valrr[2] = (self.rcoeffs[getSeg(rsig, 11, 8)].value) >> 8
            valrr[3] = (self.rcoeffs[getSeg(rsig, 15, 12)].value) >> 4
            valrr[4] = (self.rcoeffs[getSeg(rsig, 19, 16)].value) >> 0
            let valr5 = self.rcoeff.value >> 16

            valqq[0] = (self.rcoeffs[getSeg(qsig, 3, 0)].value) >> 16
            valqq[1] = (self.rcoeffs[getSeg(qsig, 7, 4)].value) >> 12
            valqq[2] = (self.rcoeffs[getSeg(qsig, 11, 8)].value) >> 8
            valqq[3] = (self.rcoeffs[getSeg(qsig, 15, 12)].value) >> 4
            valqq[4] = (self.rcoeffs[getSeg(qsig, 19, 16)].value) >> 0
            let valq5 = self.qcoeff.value >> 16

            valrq[0] = (self.qcoeffs[getSeg(qsig, 3, 0)].value) >> 16
            valrq[1] = (self.qcoeffs[getSeg(qsig, 7, 4)].value) >> 12
            valrq[2] = (self.qcoeffs[getSeg(qsig, 11, 8)].value) >> 8
            valrq[3] = (self.qcoeffs[getSeg(qsig, 15, 12)].value) >> 4
            valrq[4] = (self.qcoeffs[getSeg(qsig, 19, 16)].value) >> 0

            valqr[0] = (self.qcoeffs[getSeg(rsig, 3, 0)].value) >> 16
            valqr[1] = (self.qcoeffs[getSeg(rsig, 7, 4)].value) >> 12
            valqr[2] = (self.qcoeffs[getSeg(rsig, 11, 8)].value) >> 8
            valqr[3] = (self.qcoeffs[getSeg(rsig, 15, 12)].value) >> 4
            valqr[4] = (self.qcoeffs[getSeg(rsig, 19, 16)].value) >> 0

            (srq[0], crq[0]) = TwoCmplt.csAdd(csin: [valrq[4], valrq[3], valrq[2]], nbits: 24)
            (srq[1], crq[1]) = TwoCmplt.csAdd(csin: [srq[0].value, crq[0].value, valrq[1]], nbits: 24)
            (srq[2], crq[2]) = TwoCmplt.csAdd(csin: [srq[1].value, crq[1].value, valrq[0]], nbits: 24)

            (srq[3], crq[3]) = TwoCmplt.csAddp1(csin: [srq[2].value, crq[2].value, valq5], nbits: 24, neg: qneg)
            (srq[4], crq[4]) = TwoCmplt.csAddp1(csin: [srq[3].value, crq[3].value, 0x2], nbits: 24, neg: qneg)

            (srr[0], crr[0]) = TwoCmplt.csAdd(csin: [valrr[4], valrr[3], valrr[2]], nbits: 24)
            (srr[1], crr[1]) = TwoCmplt.csAdd(csin: [srr[0].value, crr[0].value, valrr[1]], nbits: 24)
            (srr[2], crr[2]) = TwoCmplt.csAdd(csin: [srr[1].value, crr[1].value, valrr[0]], nbits: 24)

            (srr[3], crr[3]) = TwoCmplt.csAddp1(csin: [srr[2].value, crr[2].value, valr5], nbits: 24, neg: rneg)
            (srr[4], crr[4]) = TwoCmplt.csAddp1(csin: [srr[3].value, crr[3].value, 0x2], nbits: 24, neg: rneg)

            (srr[5], crr[5]) = TwoCmplt.csA2S(csin: [srr[4].value, crr[4].value, crq[4].value], nbits: 24)
            (srr[6], crr[6]) = TwoCmplt.csA2S(csin: [srr[5].value, crr[5].value, srq[4].value], nbits: 24)


            (sqr[0], cqr[0]) = TwoCmplt.csAdd(csin: [valqr[4], valqr[3], valqr[2]], nbits: 24)
            (sqr[1], cqr[1]) = TwoCmplt.csAdd(csin: [sqr[0].value, cqr[0].value, valqr[1]], nbits: 24)
            (sqr[2], cqr[2]) = TwoCmplt.csAdd(csin: [sqr[1].value, cqr[1].value, valqr[0]], nbits: 24)

            (sqr[3], cqr[3]) = TwoCmplt.csAddp1(csin: [sqr[2].value, crq[2].value, valr5], nbits: 24, neg: rneg)
            (sqr[4], crq[4]) = TwoCmplt.csAddp1(csin: [sqr[3].value, crq[3].value, 0x2], nbits: 24, neg: rneg)

            (sqq[0], cqq[0]) = TwoCmplt.csAdd(csin: [valqq[4], valqq[3], valqq[2]], nbits: 24)
            (sqq[1], cqq[1]) = TwoCmplt.csAdd(csin: [sqq[0].value, cqq[0].value, valqq[1]], nbits: 24)
            (sqq[2], cqq[2]) = TwoCmplt.csAdd(csin: [sqq[1].value, cqq[1].value, valqq[0]], nbits: 24)

            (sqq[3], cqq[3]) = TwoCmplt.csAddp1(csin: [sqq[2].value, cqq[2].value, valq5], nbits: 24, neg: rneg)
            (sqq[4], cqq[4]) = TwoCmplt.csAddp1(csin: [sqq[3].value, cqq[3].value, 0x2], nbits: 24, neg: rneg)

            (sqq[5], cqq[5]) = TwoCmplt.csAdd(csin: [sqq[4].value, cqq[4].value, cqr[4].value], nbits: 24)
            (sqq[6], cqq[6]) = TwoCmplt.csAdd(csin: [sqq[5].value, cqq[5].value, sqr[4].value], nbits: 24)

        } else {
            coeffSumr = TwoCmplt(0, nbits: 20, signed: true)
            coeffSumq = TwoCmplt(0, nbits: 20, signed: true)
        }

        let qdrant = (self.coeffQd + self.sgnlQd) % 4
        switch qdrant {
        case 0:
            coeffSumr = (srr[6] + crr[6])
            coeffSumq = (sqq[6] + cqq[6])
        case 1:
            coeffSumr = (~sqq[6] + ~cqq[6])
            coeffSumq = (srr[6] + crr[6])
        case 2:
            coeffSumr = (~srr[6] + ~crr[6])
            coeffSumq = (~sqq[6] + ~cqq[6])
        case 3:
            coeffSumr = (sqq[6] + cqq[6])
            coeffSumq = (~srr[6] + ~crr[6])
        default:
            coeffSumr = (srr[6] + crr[6])
            coeffSumq = (sqq[6] + cqq[6])
        }

        rout = coeffSumr>>4
        qout = coeffSumq>>4
        rout.setNbits(20)
        qout.setNbits(20)

        return (rout, qout)
    }

}
