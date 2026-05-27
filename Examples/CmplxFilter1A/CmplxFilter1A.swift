import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

/**
 * A Third-Order Filter with a Finite Zero. This filter has very good stop bands and only requires
 * simple shifts. It is implemented using carry-save techniques, (one csAdd(), and three CsA2S1()
 * i.e. (sout, cout) = (a _ b - c)) and 4 generate/propogate adders.
 *
 */
func simCmplxFltr1A (_ coeff: (Int, Int), nbits: Int){
    let (rval, qval) = coeff

    let msk24 = ((1<<24) - 1)

    // var cMlts: [CmplxMlt] = Array(repeating: CmplxMlt(rval: rval, qval: qval, nbits: nbits), count: 1)
    var cMlt = CmplxMlt(rval: rval, qval: qval, nbits: nbits)

    let k1Shft = 2

    var Inr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 8192)
    var Outr: [Int] = Array(repeating: 0, count: 8192)

    var Inq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 8192)
    var Outq: [Int] = Array(repeating: 0, count: 8192)

    var XIr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1)
    var XIr_: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1)
    var Xr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1)
    var XIq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1)
    var XIq_: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1)
    var Xq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1)
    var Sr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1)
    var Cr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1)
    var Sq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1)
    var Cq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1)


    Inr[0].value = (1<<18)
    Inq[0].value = 0
    for i in 0..<8192 {

        (Sr[0], Cr[0]) = TwoCmplt.csA2S(csin: [Inr[i].toInt()>>k1Shft, Xr[0].toInt(), Xr[0].toInt()>>k1Shft], nbits: 20)
        XIr_[0] = (Sr[0] + Cr[0]) & msk24

        (Sq[0], Cq[0]) = TwoCmplt.csA2S(csin: [Inq[i].toInt()>>k1Shft, Xq[0].toInt(), Xq[0].toInt()>>k1Shft], nbits: 20)
        XIq_[0] = (Sq[0] + Cq[0]) & msk24

        (XIr[0], XIq[0]) = cMlt.mult((XIr_[0], XIq_[0]))

        Outr[i] = Xr[0].toInt()
        Outq[i] = Xq[0].toInt()

        Xr[0] = XIr[0]
        Xq[0] = XIq[0]

    }

    let path = "/home/Dropbox/programming/Swift/TwosCmplt/PlotResponse/CmplxFltr1a.dat"
    withFile(path, mode: "w") { fp in
        for i in 0..<8192 {
            // Write the string and add a newline
            let line = "\(String(format: "%d", Outr[i])) \(String(format: "%d", Outq[i]))\n"
            fputs(line, fp)
        }
    }
}

@main
struct RunFilter1A {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            simCmplxFltr1A((0xb504f, 0xb504f), nbits: 24)
            // simCmplxFltr1A((0xfffff, 0x00000), nbits: 24)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
