import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

/**
 * An example of a complex oscillator using the Fixed Coefficient Complex Multiplier
 *
 * - Parameter coeff: A tuple of two Ints specifying the real and the
 *   imgaginary parts of the complex coefficient used for the oscillator.
 * - Parameter nbits: the nbits for the multiplier. This should be equal to the signal nbits + 4.
 * - Parameter N: the number of samples to simulate for. Should be an integer multiple
 *   of the period to simplify spectral analysis using an FFT.
 */
func simCmplxOsc1 (_ coeff: (Int, Int), nbits: Int, N: Int) {
    let (rval, qval) = coeff
    var cMlt = CmplxMlt(rval: rval, qval: qval, nbits: nbits)
    var Xr0: TwoCmplt = TwoCmplt(0x7FF00, nbits: 20, signed: true)
    var XIr0: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var Xq0: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var XIq0: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)

    var OutR: [Int] = Array(repeating: 0, count: N)
    var OutQ: [Int] = Array(repeating: 0, count: N)

    for i in 0..<N {
        (XIr0, XIq0) = cMlt.mult((Xr0, Xq0))

        (OutR[i], OutQ[i]) = (Xr0.toInt(), Xq0.toInt())
        (Xr0, Xq0) = (XIr0, XIq0)

        if Xr0 > 0x7FF80 {
            Xr0 -= 4
        }
        print("\(i): \(Xr0.toInt()), \(Xq0.toInt())")

    }

    let path = "/home/Dropbox/programming/Swift/TwosCmplt/PlotResponse/CmplxOsc1.dat"
    withFile(path, mode: "w") { fp in
        for i in 0..<N {
            // Write the string and add a newline
            let line = "\(String(format: "%d", OutR[i])) \(String(format: "%d", OutQ[i]))\n"
            fputs(line, fp)
        }
    }
    ()
}

@main
struct RunCmplxOsc1 {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            // coeff = ((1<<20)*cos(2*pi/per), (1<<20)*sin(2*pi/per)) rounded to Int
            // This example has per = 33, N = 8193*per
            simCmplxOsc1((0xfb5fa, 0x3072d), nbits: 24, N: 270369)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
