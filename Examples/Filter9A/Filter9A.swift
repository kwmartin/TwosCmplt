import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

/**
 * A Third Order Filter with a Finite Zeror. F-3dB = 0.16*k1 (approximately)
 * Fzero = 2.8*F-3dB. Leaving k2Shift and k3Shift fixed, but changing k1Shift only
 * frequency shifts the filter while leaving the filter shape constant. This filter
 * was used in early ADSL chips. This example is "hardwired" for speed. It is currently
 * set up with k1Shift being a fixed shift implying a power of two multiplication only.
 * To get arbitrary precision on the -3dB frequency, change ">> k1Shift" to "* k1".
 *
 * - Parameter coeff: should be set to k1*((1 << 16))
 */
func Filter3C (_ coeff: Int){

    let k1Shift = 4
    let k2Shift = 4
    let k3Shift = 4
    let k4Shift = (4, 64)
    let k5Shift = (4, 8)
    let k6Shift = 4

    var In: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 8192)
    var Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 8192)
    var XI: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 10)
    var X: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 10)
    var V: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 12)

    var States: [(Int, Int, Int, Int)] = Array(repeating: ( 0, 0, 0, 0), count: 8192)

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

    var m = 0
    In[0].value = (1<<19)
    for i in 0..<8192 {
        // Sn = Int((32767.0 * sin(Double(i)*2*Double.pi*F0)).rounded())

        V[0] = In[i] - X[2]
        V[1] = V[0] >> k1Shift
        XI[0] = X[0] + V[1]
        V[2] = X[0] - X[2]
        V[3] = V[2] >> k2Shift
        XI[1] = X[1] + V[3]
        V[4] = In[i] >> k3Shift
        XI[2] = XI[1] + V[4]

        V[5] = X[2] - X[4]
        V[6] = (V[5] >> k4Shift.0) + (V[5] >> k4Shift.1)
        XI[3] = X[3] + V[6]
        V[7] = X[3] - X[4]
        V[8] = (V[7] >> k5Shift.0) + (V[7] >> k5Shift.1)
        XI[4] = X[4] + V[8]

        V[9] = X[4] - X[5]
        V[10] = V[9] >> k6Shift
        XI[5] = X[5] + V[10]

        XI[6] = X[6] + ((In[i]) >> 4)
        XI[7] = X[7] + ((X[6]) >> 4)


        if (i%16) == 0 {
            XI[8] = X[7]
            XI[9] = XI[8] - X[8]
            V[11] = XI[9] - X[9]
            Out[m] = V[11]
            m += 1
        }

        States[i] = (X[6].toInt(), X[7].toInt(), XI[9].toInt(), V[11].toInt())

        X[0] = XI[0]
        X[1] = XI[1]
        X[2] = XI[2]
        X[3] = XI[3]
        X[4] = XI[4]
        X[5] = XI[5]
        X[6] = XI[6]
        X[7] = XI[7]

        if (i%16) == 0 {
            X[8] = XI[8]
            X[9] = XI[9]
        }

    }
    let path = "/home/Dropbox/programming/Swift/TwosCmplt/PlotResponse/fltr9a.dat"
    withFile(path, mode: "w") { fp in
        for val in Out {
            let line = "\(val.toInt())\n"
            fputs(line, fp)
        }
    }

    let path2 = "/home/Dropbox/programming/Swift/TwosCmplt/PlotResponse/states9a.dat"
    withFile(path2, mode: "w") { fp in
        for val in States {
            let line = "\(String(format: "%d", val.0)) \(String(format: "%d", val.1)) \(String(format: "%d", val.2))\n"
            fputs(line, fp)
        }
    }

}

@main
struct RunFilter3B {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            Filter3C(0x63e4)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
