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
 */
func Filter3C (){

    let k1Shift = 2
    let k2Shift = (0, 3)
    let k3Shift = 3
    var In: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var States: [(Int, Int, Int)] = Array(repeating: ( 0, 0, 0), count: 1024)
    var XI: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 3)
    var X: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 3)
    var V: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 7)
    /*
    for i in 1..<1024 {
        In[i].value = (1<<14)
    }
    */
    // let F0: Double = 1.00/128
    // var sn: Double
    // var Sn: Int
    In[0].value = (1<<18)
    for i in 0..<1024 {
        // Sn = Int((32767.0 * sin(Double(i)*2*Double.pi*F0)).rounded())
        V[0] = In[i] >> k3Shift
        // V[0] = TwoCmplt(Sn, nbits:20) >> k3Shift
        V[1] = V[0] + X[1]
        V[2] = (V[1] >> k2Shift.0) - (V[1] >> k2Shift.1)
        V[3] = In[i] - V[1]
        V[4] = X[0] + (V[3] >> k1Shift)
        V[5] = (V[4] - V[2]) >> k1Shift
        V[6] = (V[1] - X[2]) >> k1Shift

        XI[0] = V[4]
        XI[1] = X[1] + V[5]
        XI[2] = X[2] + V[6]

        Out[i] = X[2]
        States[i] = (X[0].toInt(), X[1].toInt(), X[2].toInt())

        X[0] = XI[0]
        X[1] = XI[1]
        X[2] = XI[2]

    }

    let path = "/home/Dropbox/programming/Swift/TwosCmplt/tools/fltr3b.dat"
    withFile(path, mode: "w") { fp in
        for val in Out {
            let line = "\(val.toInt())\n"
            fputs(line, fp)
        }
    }

    let path2 = "/home/Dropbox/programming/Swift/TwosCmplt/tools/states_3b.dat"
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
            Filter3C()
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
