import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

/**
 * A simple example of a first order to illustrate using the new fixed-coefficient multiplier
 * based on using multiplexors to select multiples of the coefficient, k*coeff for i=0...15
 * or shifted versions of the same based on nibbles of the signal path
 *
 * - Parameter coeff: unsigned, not nbits=20, but the maximum size is (1<<16)-1 because room
 *   is required for the multiples
 */
func Filter3A (_ coeff: Int) {
    var M0: CoeffMlt = CoeffMlt(0x0, nbits: 20)
    let coeff: TwoCmplt = TwoCmplt(coeff, nbits: 20)
    var In: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)
    var Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024)

    /*
    for i in 18..<1024 {
        In[i].value = (1<<14)
    }
    */
    In[16].value = 0x7fff

    var X0: TwoCmplt = TwoCmplt(0, nbits: 20)
    var X1: TwoCmplt = TwoCmplt(0, nbits: 20)
    var X2: TwoCmplt = TwoCmplt(0, nbits: 20)

    for i in 0..<1024 {
        M0.coeffUpdate(coeff)
        X0 = In[i] - X2
        X1 = X0 * M0
        X2 = X2 + X1
        // X0 = ((In[i] - X0) * M0) + X0
        Out[i] = X2
        print("X0: ", X0)
        print("X1: ", X1)
        print("X2: ", X2)
        print("Out: ", Out[i])
        print("i= ", i)
    }
    _ = In
    _ = Out

    let path = "/home/Dropbox/programming/Swift/TwosCmplt/PlotResponse/fltr3a.dat"
    withFile(path, mode: "w") { fp in
        for val in Out {
            let line = "\(val.toInt())\n"
            fputs(line, fp)
        }
    }

    ()
}

@main
struct RunFilter3A {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            Filter3A(0x63e4)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.15f", seconds)) // prints 15 digits after decimal

    }
}
