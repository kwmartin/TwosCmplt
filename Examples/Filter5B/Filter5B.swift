import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

/**
 * A Fifth-Order Filter with a Finite Zero. This filter has very good stop bands and only requires
 * simple shifts. It is implemented using carry-save techniques, (one csAdd(), and six CsA2S1()
 * i.e. (sout, cout) = (a _ b - c)) and 7 generate/propogate adders.
 *
 */
func Filter5B (){

    let k1Shft = 3
    let k2Shft = 3
    let k3Shft = 3
    let k4Shft = 3
    let k5Shft = 2
    // let k6Shft = 4
    let k7Shft = 3

    var In: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 8192)
    var Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 8192)
    var XI: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 6)
    var X: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 6)

    var s0 = TwoCmplt(0, nbits: 24), c0 = TwoCmplt(0, nbits: 24)
    var s1 = TwoCmplt(0, nbits: 24), c1 = TwoCmplt(0, nbits: 24)
    var s2 = TwoCmplt(0, nbits: 24), c2 = TwoCmplt(0, nbits: 24)
    var s3 = TwoCmplt(0, nbits: 24), c3 = TwoCmplt(0, nbits: 24)
    var s4 = TwoCmplt(0, nbits: 24), c4 = TwoCmplt(0, nbits: 24)
    // var s5 = TwoCmplt(0, nbits: 24), c5 = TwoCmplt(0, nbits: 24)
    var s6 = TwoCmplt(0, nbits: 24), c6 = TwoCmplt(0, nbits: 24)

    let msk24 = ((1<<24) - 1)

    var States: [(Int, Int, Int, Int, Int, Int)] = Array(repeating: ( 0, 0, 0, 0, 0, 0), count: 8192)

    let zero: TwoCmplt = TwoCmplt(0, nbits: 24, signed: true)
    _ = zero

    /*
    for i in 1..<8192 {
        In[i].value = (1<<14)
    }
    */
    // let F0: Double = 1.00/128
    // var sn: Double
    // var Sn: Int

    In[0].value = (1<<19)
    for i in 0..<8192 {

        (s0, c0) = TwoCmplt.csA2S(csin: [In[i].toInt()>>k1Shft, X[0].toInt(), X[2].toInt()>>k1Shft], nbits: 24)
        XI[0] = (s0 + c0) & msk24

        (s1, c1) = TwoCmplt.csA2S(csin: [X[1].toInt(), X[0].toInt()>>k2Shft, X[2].toInt()>>k2Shft], nbits: 24)
        XI[1] = (s1 + c1) & msk24

        (s2, c2) = TwoCmplt.csAdd(csin: [s1.toInt(), c1.toInt(), In[i].toInt()>>k3Shft], nbits: 24)
        XI[2] = (s2 + c2) & msk24

        (s3, c3) = TwoCmplt.csA2S(csin: [X[3].toInt(), X[2].toInt()>>k4Shft, X[4].toInt()>>k4Shft], nbits: 24)
        XI[3] = (s3 + c3) & msk24

        (s4, c4) = TwoCmplt.csA2S(csin: [X[4].toInt(), X[3].toInt()>>k5Shft, X[4].toInt()>>k5Shft], nbits: 24)
        // (s5, c5) = TwoCmplt.csA2S(csin: [s4.toInt(), c4.toInt(), X[4].toInt()>>k6Shft], nbits: 24)
        XI[4] = (s4 + c4) & msk24

        (s6, c6) = TwoCmplt.csA2S(csin: [X[5].toInt(), X[4].toInt()>>k7Shft, X[5].toInt()>>k7Shft], nbits: 24)
        XI[5] = (s6 + c6) & msk24

        Out[i] = X[5]

        States[i] = (X[0].toInt(), X[1].toInt(), X[2].toInt(), X[3].toInt(), X[4].toInt(), X[5].toInt())

        X[0] = XI[0]
        X[1] = XI[1]
        X[2] = XI[2]
        X[3] = XI[3]
        X[4] = XI[4]
        X[5] = XI[5]

    }

    let path = "/home/Dropbox/programming/Swift/TwosCmplt/tools/fltr5b.dat"
    withFile(path, mode: "w") { fp in
        for val in Out {
            // Write the string and add a newline
            let line = "\(String(format: "%d", val.toInt()))\n"
            fputs(line, fp)
        }
    }

    let path2 = "/home/Dropbox/programming/Swift/TwosCmplt/tools/states5b.dat"
    withFile(path2, mode: "w") { fp in
        for val in States {
            // Write the string and add a newline
            let line = "\(String(format: "%d", val.0)) \(String(format: "%d", val.1)) \(String(format: "%d", val.2)) \(String(format: "%d", val.3)) \(String(format: "%d", val.4)) \(String(format: "%d", val.5))\n"
            fputs(line, fp)
        }
    }
}

@main
struct RunFilter3B {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            Filter5B()
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
