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
func simCmplxFltr3E (_ coeff: (Int, Int), nbits: Int){
    let (rval, qval) = coeff

    let msk24 = ((1<<24) - 1)

    // var cMlts: [CmplxMlt] = Array(repeating: CmplxMlt(rval: rval, qval: qval, nbits: nbits), count: 4)
    var cMlt = CmplxMlt(rval: rval, qval: qval, nbits: nbits)

    let k1Shft = 4
    let k2Shft = 4
    let k3Shft = 4
    let k4Shft = 4

    var Inr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 8192)
    var Outr: [Int] = Array(repeating: 0, count: 8192)

    var Inq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 8192)
    var Outq: [Int] = Array(repeating: 0, count: 8192)

    var XIr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 4)
    var XIr_: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 4)
    var Xr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 4)
    var XIq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 4)
    var XIq_: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 4)
    var Xq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 4)
    var Sr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 4)
    var Cr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 4)
    var Sq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 4)
    var Cq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 4)

    var States: [(Int, Int, Int, Int)] = Array(repeating: ( 0, 0, 0, 0), count: 8192)

    Inr[0].value = (1<<18)
    Inq[0].value = 0
    for i in 0..<8192 {

        (Sr[0], Cr[0]) = TwoCmplt.csA2S(csin: [Inr[i].toInt()>>k1Shft, Xr[0].toInt(), Xr[2].toInt()>>k1Shft], nbits: 20)
        XIr_[0] = (Sr[0] + Cr[0]) & msk24

        (Sq[0], Cq[0]) = TwoCmplt.csA2S(csin: [Inq[i].toInt()>>k1Shft, Xq[0].toInt(), Xq[2].toInt()>>k1Shft], nbits: 20)
        XIq_[0] = (Sq[0] + Cq[0]) & msk24

        (XIr[0], XIq[0]) = cMlt.mult((XIr_[0], XIq_[0]))

        (Sr[1], Cr[1]) = TwoCmplt.csA2S(csin: [Xr[1].toInt(), Xr[0].toInt()>>k2Shft, Xr[2].toInt()>>k2Shft], nbits: 20)
        XIr_[1] = (Sr[1] + Cr[1]) & msk24

        (Sq[1], Cq[1]) = TwoCmplt.csA2S(csin: [Xq[1].toInt(), Xq[0].toInt()>>k2Shft, Xq[2].toInt()>>k2Shft], nbits: 20)
        XIq_[1] = (Sq[1] + Cq[1]) & msk24

        (XIr[1], XIq[1]) = cMlt.mult((XIr_[1], XIq_[1]))

        (Sr[2], Cr[2]) = TwoCmplt.csAdd(csin: [Sr[1].toInt(), Cr[1].toInt(), Inr[i].toInt()>>k3Shft], nbits: 20)
        XIr_[2] = (Sr[2] + Cr[2]) & msk24

        (Sq[2], Cq[2]) = TwoCmplt.csAdd(csin: [Sq[1].toInt(), Cq[1].toInt(), Inq[i].toInt()>>k3Shft], nbits: 20)
        XIq_[2] = (Sq[2] + Cq[2]) & msk24

        (XIr[2], XIq[2]) = cMlt.mult((XIr_[2], XIq_[2]))

        (Sr[3], Cr[3]) = TwoCmplt.csA2S(csin: [Xr[3].toInt(), Xr[2].toInt()>>k4Shft, Xr[3].toInt()>>k4Shft], nbits: 20)
        XIr_[3] = (Sr[3] + Cr[3]) & msk24

        (Sq[3], Cq[3]) = TwoCmplt.csA2S(csin: [Xq[3].toInt(), Xq[2].toInt()>>k4Shft, Xq[3].toInt()>>k4Shft], nbits: 20)
        XIq_[3] = (Sq[3] + Cq[3]) & msk24

        (XIr[3], XIq[3]) = cMlt.mult((XIr_[3], XIq_[3]))

        Outr[i] = Xr[3].toInt()
        Outq[i] = Xq[3].toInt()

        States[i] = (XIr_[1].toInt(), XIq_[1].toInt(), XIr[1].toInt(), XIq[1].toInt(), 
        )

        Xr[0] = XIr[0]
        Xr[1] = XIr[1]
        Xr[2] = XIr[2]
        Xr[3] = XIr[3]

        Xq[0] = XIq[0]
        Xq[1] = XIq[1]
        Xq[2] = XIq[2]
        Xq[3] = XIq[3]
    }

    let path = "/home/Dropbox/programming/Swift/TwosCmplt/tools/CmplxFltr3e.dat"
    withFile(path, mode: "w") { fp in
        for i in 0..<8192 {
            // Write the string and add a newline
            let line = "\(String(format: "%d", Outr[i])) \(String(format: "%d", Outq[i]))\n"
            fputs(line, fp)
        }
     }

    let path2 = "/home/Dropbox/programming/Swift/TwosCmplt/tools/CmplxFltr3e_states.dat"
    withFile(path2, mode: "w") { fp in
        for val in States {
            // Write the string and add a newline
            let line = "\(sgndHx(val.0, width: 5)) \(sgndHx(val.1, width: 5)) \(sgndHx(val.2, width: 5)) \(sgndHx(val.3, width: 5))\n"
            fputs(line, fp)
        }
    }
}

@main
struct RunFilter3B {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            simCmplxFltr3E((0xb504f, 0xb504f), nbits: 24)
            // simCmplxFltr3E((0xfffff, 0x0), nbits: 24)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
