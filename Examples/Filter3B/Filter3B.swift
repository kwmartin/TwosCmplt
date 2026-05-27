import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

/**
 * A Third Order Filter with F-3dB = 0.16*k1 (approximately).
 * This filter is about the simplest third-order filter one can realize.
 * All of the three coefficients should be taken equal and normally they
 * are a simple shift right by a fixed number of bits. For example, ">> 2"
 * The transfer function shape is very constant irrespective of the value for k1.
 * To get arbitrary precision on the -3dB frequency, change ">> k1Shift" to "* k1".
 *
 */
func Filter3B (){

    let k1Shift = 2
    var In: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var States: [(Int, Int, Int)] = Array(repeating: ( 0, 0, 0), count: 1024)
    var XI: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 3)
    var X: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 3)
    var V: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 6)
    /*
    for i in 1..<1024 {
        In[i].value = (1<<18)
    }
    */
    // let F0: Double = 1.00/128
    // var sn: Double
    // var Sn: Int

    In[0].value = (1<<18)

    for i in 0..<1024 {
        V[0] = In[i] - X[0]
        V[1] = V[0] >> k1Shift

        XI[0] = V[1] + X[0]

        V[2] = X[0] - X[2]
        V[3] = V[2]  >> k1Shift
        XI[1] = X[1] + V[3]

        V[4] = XI[1] - X[2]
        V[5] = V[4] >> k1Shift

        XI[2] = X[2] + V[5]

        Out[i] = X[2]
        X[0] = XI[0]
        X[1] = XI[1]
        X[2] = XI[2]

        States[i] = (X[0].toInt(), X[1].toInt(), X[2].toInt())
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
            Filter3B()
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
