import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

/**
 * A simple example of a second order oscillator using the Fixed Coefficient Multiplier
 *
 * - Parameter coeff: The coeff specifies the multiplication constant. It is a fraction between 0
 *   and 1. For a 16-bit signal path, the muliplication constant is taken coeff = K*65536 (i.e. 1<<16).
 *   The equation governing the frequency of oscillation is K = 2*sin(pi*f0) where f0 is a fraction; for
 *   example, if the oscillation period 16 clock cycles, take f0 = 1/16.
 */
func SimOsc2 (_ coeff: Int, N: Int) {
    var coeff: TwoCmplt = TwoCmplt(coeff, nbits: 20)
    // let Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: 1024 )
    var Out: [Int] = Array(repeating: 0, count: N)
    var X0: TwoCmplt = TwoCmplt(0x7d880, nbits: 20, signed: true)
    var XI0: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var X1: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var XI1: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var V0: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var V1: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    // var Cs: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    // var Sn: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    let F0: Double = 1.00/16.0
    var cs: Double
    var sn: Double
    // let deltPhi: Double = -Double.pi*0.0

    var deltPhi: Double = -Double.pi*0.37506

    var rl1 = 0.0, rl2 = 0.0, rl3 = 0.0
    var qd1 = 0.0, qd2 = 0.0, qd3 = 0.0
    var deltaCoeff: Int
    for i in 0..<N {

        // cs = 32767.0 * cos(Double(i)*2*Double.pi*F0 + deltPhi)
        // sn = 32767.0 * sin(Double(i)*2*Double.pi*F0 + deltPhi)
        cs = cos(Double(i)*2*Double.pi*F0)
        sn = sin(Double(i)*2*Double.pi*F0)
        V0 = TwoCmplt.multN(lhs: X0, rhs: coeff, rshift: 16) 
        XI1 = X1 + V0
        V1 = TwoCmplt.multN(lhs: XI1, rhs: coeff, rshift: 16) 
        XI0 = X0 - V1
        X0 = XI0
        X1 = XI1
        Out[i] = X0.toInt()
        // print("i: \(i), X0: \(X0.toInt()), X1: \(X1.toInt()), sync: \(M0.sync)")
        // print("i: \(i), cs: \(String(format: "%7.5f", cs)), sn: \(String(format: "%7.5f", sn))")

        /*
        if i == 240 {
            M0.coeff = TwoCmplt(0x63e4, nbits: 20)
        }
        */
        // print("i: \(i), X0: \(X0.toInt()), X1: \(X1.toInt())")

        rl1 = (X0.toInt() > 0) ? rl1 + cs : rl1 - cs
        rl2 = (X1.toInt() > 0) ? rl2 + sn : rl2 - sn
        rl3 = (rl1 - rl2)/pow(2.0, 28)
        qd1 = (X0.toInt() > 0) ? qd1 + sn : qd1 - sn
        qd2 = (X1.toInt() > 0) ? qd2 + cs : qd2 - cs
        qd3 = (qd1 + qd2)/pow(2.0, 28)
        if i % 16 == 0 {
            // print("i: \(i), rl3: \(String(format: "%7.5f", rl3)), qd3: \(String(format: "%7.5f", qd3)), coeff: \(coeff.toInt()), deltPhi: \(deltPhi)")
        }

        // print("i: \(i), rl3: \(String(format: "%7.5f", rl3)), qd3: \(String(format: "%7.5f", qd3)), coeff: \(coeff.toInt()), deltPhi: \(deltPhi)")

        deltPhi = deltPhi + 0.0*1e-12*qd3
        deltaCoeff = Int(2.0e-12*qd3*pow(2,4.0).rounded())
        coeff = coeff + TwoCmplt(deltaCoeff, nbits: 20)

        ()
      }
    _ = Out
    print(rl3)
    let path = "/home/Dropbox/programming/Swift/PlotResponse/Osc1.dat"
    withFile(path, mode: "w") { fp in
        for val in Out {
            // Write the string and add a newline
            let line = "\(String(format: "%d", val))\n"
            fputs(line, fp)
        }
    }


    ()
}

@main
struct RunOsc1 {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            SimOsc2(0x63e3, N: 65536)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
