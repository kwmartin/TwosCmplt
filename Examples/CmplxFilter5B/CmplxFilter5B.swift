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
func simCmplxFltr (_ coeff: (Int, Int), nbits: Int, filename: String){
    let (rval, qval) = coeff

    let msk24 = ((1<<24) - 1)

    // var cMlts: [CmplxMlt] = Array(repeating: CmplxMlt(rval: rval, qval: qval, nbits: nbits), count: 6)
    var cMlt = CmplxMlt(rval: rval, qval: qval, nbits: nbits)

    let k1Shft = 3
    let k2Shft = 3
    let k3Shft = 3
    let k4Shft = 3
    let k5Shft = 2
    let k6Shft = 3

    var Inr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var Outr: [Int] = Array(repeating: 0, count: 1024)

    var Inq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var Outq: [Int] = Array(repeating: 0, count: 1024)

    var XIr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    var XIr_: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    var Xr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    var XIq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    var XIq_: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    var Xq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    var Sr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    var Cr: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    var Sq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    var Cq: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)

    var States: [(Int, Int, Int, Int)] = Array(repeating: ( 0, 0, 0, 0), count: 1024)

    Inr[0].value = (1<<18)
    Inq[0].value = 0
    for i in 0..<1024 {

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

        (Sr[3], Cr[3]) = TwoCmplt.csA2S(csin: [Xr[3].toInt(), Xr[2].toInt()>>k4Shft, Xr[4].toInt()>>k4Shft], nbits: 20)
        XIr_[3] = (Sr[3] + Cr[3]) & msk24

        (Sq[3], Cq[3]) = TwoCmplt.csA2S(csin: [Xq[3].toInt(), Xq[2].toInt()>>k4Shft, Xq[4].toInt()>>k4Shft], nbits: 20)
        XIq_[3] = (Sq[3] + Cq[3]) & msk24

        (XIr[3], XIq[3]) = cMlt.mult((XIr_[3], XIq_[3]))

        (Sr[4], Cr[4]) = TwoCmplt.csA2S(csin: [Xr[4].toInt(), Xr[3].toInt()>>k5Shft, Xr[4].toInt()>>k5Shft], nbits: 20)
        XIr_[4] = (Sr[4] + Cr[4]) & msk24

        (Sq[4], Cq[4]) = TwoCmplt.csA2S(csin: [Xq[4].toInt(), Xq[3].toInt()>>k5Shft, Xq[4].toInt()>>k5Shft], nbits: 20)
        XIq_[4] = (Sq[4] + Cq[4]) & msk24

        (XIr[4], XIq[4]) = cMlt.mult((XIr_[4], XIq_[4]))

        (Sr[5], Cr[5]) = TwoCmplt.csA2S(csin: [Xr[5].toInt(), Xr[4].toInt()>>k6Shft, Xr[5].toInt()>>k6Shft], nbits: 20)
        XIr_[5] = (Sr[5] + Cr[5]) & msk24

        (Sq[5], Cq[5]) = TwoCmplt.csA2S(csin: [Xq[5].toInt(), Xq[4].toInt()>>k6Shft, Xq[5].toInt()>>k6Shft], nbits: 20)
        XIq_[5] = (Sq[5] + Cq[5]) & msk24

        (XIr[5], XIq[5]) = cMlt.mult((XIr_[5], XIq_[5]))

        Outr[i] = Xr[5].toInt()
        Outq[i] = Xq[5].toInt()

        States[i] = (XIr[0].toInt(), XIq[0].toInt(), XIr[1].toInt(), XIq[1].toInt())

        Xr[0] = XIr[0]
        Xr[1] = XIr[1]
        Xr[2] = XIr[2]
        Xr[3] = XIr[3]
        Xr[4] = XIr[4]
        Xr[5] = XIr[5]

        Xq[0] = XIq[0]
        Xq[1] = XIq[1]
        Xq[2] = XIq[2]
        Xq[3] = XIq[3]
        Xq[4] = XIq[4]
        Xq[5] = XIq[5]
    }

    let cwd = FileManager.default.currentDirectoryPath

    let path = "\(cwd)/tools/\(filename).dat"
    withFile(path, mode: "w") { fp in
        for i in 0..<1024 {
            // Write the string and add a newline
            let line = "\(String(format: "%d", Outr[i])) \(String(format: "%d", Outq[i]))\n"
            fputs(line, fp)
        }
    }
    let path2 = "/home/Dropbox/programming/Swift/TwosCmplt/tools/CmplxFltr5B_states.dat"
    withFile(path2, mode: "w") { fp in
        for val in States {
            let line = "\(String(format: "%d", val.0)) \(String(format: "%d", val.1)) \(String(format: "%d", val.2)) \(String(format: "%d", val.3))\n"
            fputs(line, fp)
        }
    }

}

@main
struct RunFilter3B {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            simCmplxFltr((0xec835, 0x61f78), nbits: 24, filename: "CmplxFltr5a")
            simCmplxFltr((0xb504f, 0xb504f), nbits: 24, filename: "CmplxFltr5b")
            simCmplxFltr((0x61f78, 0xec835), nbits: 24, filename: "CmplxFltr5c")
            simCmplxFltr((0x00000, 0xfffff), nbits: 24, filename: "CmplxFltr5d")
            // simCmplxFltr((0xfffff, 0x0), nbits: 24)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
