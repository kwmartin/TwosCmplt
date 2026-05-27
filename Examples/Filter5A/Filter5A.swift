import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

/**
 * A Fifth-Order Filter with a Finite Zero. This filter has very good stop bands and only requires
 * simple shifts.
 *
 */
func Filter5A (){

    let k1Shift = 2
    let k2Shift = 2
    let k3Shift = 2
    let k4Shift = 2
    let k5Shift = (1, 4)
    let k6Shift = 2

    var In: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 8192)
    var Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 8192)
    var XI: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 6)
    var X: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 6)
    var V: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 24, signed: true), count: 11)

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
        V[6] = (V[5] >> k4Shift)
        XI[3] = X[3] + V[6]
        V[7] = X[3] - X[4]
        V[8] = (V[7] >> k5Shift.0) - (X[4] >> k5Shift.1)
        XI[4] = X[4] + V[8]

        V[9] = X[4] - X[5]
        V[10] = V[9] >> k6Shift
        XI[5] = X[5] + V[10]

        Out[i] = X[5]

        States[i] = (X[0].toInt(), X[1].toInt(), X[2].toInt(), X[3].toInt(), X[4].toInt(), X[5].toInt())

        X[0] = XI[0]
        X[1] = XI[1]
        X[2] = XI[2]
        X[3] = XI[3]
        X[4] = XI[4]
        X[5] = XI[5]

    }

    let path = "/home/Dropbox/programming/Swift/TwosCmplt/tools/fltr5a.dat"
    withFile(path, mode: "w") { fp in
        for val in Out {
            let line = "\(val.toInt())\n"
            fputs(line, fp)
        }
    }

    let path2 = "/home/Dropbox/programming/Swift/TwosCmplt/tools/states5a.dat"
    withFile(path2, mode: "w") { fp in
        for val in States {
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
            Filter5A()
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
