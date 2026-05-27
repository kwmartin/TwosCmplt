import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

/**
 * An example of a second order oscillator with high frequency resolution. One use of this block
 * is for generating high quality on-chip test signals for D/A's. Note also that generating sine waves using
 * this approach has much less latency as compared to generating sine waves using DDFS's.
 *
 * - Parameter coeff: The coeff specifies the multiplication constant. It is a fraction between 0
 *   and 1. For a 16-bit signal path, the muliplication constant is taken coeff = K*65536 (i.e. 1<<16).
 *   The equation governing the frequency of oscillation is K = 2*sin(pi*f0) where f0 is a fraction; for
 *   example, if the oscillation period 16 clock cycles, take f0 = 1/16.
 *
 * - Parameter N: The number of periods to simulat for
 *
 * - Parameter accum: added to 24-bit TwoCmplt variable X2 each clock period. The carry-out of X2 is
*    added to coeff to give much greater resolution on the frequency of oscillation.
 */
func SimOsc3 (coeff: Int, N: Int, accum: Int) {
    var coeff: TwoCmplt = TwoCmplt(coeff, nbits: 20)
    let accum: TwoCmplt = TwoCmplt(accum, nbits: 24)

    // let Out: [TwoCmplt] = Array(repeating: TwoCmplt(0, nbits: 20, signed: true), count: N )
    var Out: [Int] = Array(repeating: 0, count: N)

    var X0: TwoCmplt = TwoCmplt(0x7d880, nbits: 20, signed: true)
    var XI0: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var X1: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var XI1: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var X2: TwoCmplt = TwoCmplt(0, nbits: 24, signed: false)
    var V0: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var V1: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
    var coeff2: TwoCmplt = TwoCmplt(0, nbits: 20, signed: true)
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

        X2 = X2 + accum
        coeff2 = X2.crry ? (coeff + 1) : coeff

        // cs = 32767.0 * cos(Double(i)*2*Double.pi*F0 + deltPhi)
        // sn = 32767.0 * sin(Double(i)*2*Double.pi*F0 + deltPhi)
        cs = cos(Double(i)*2*Double.pi*F0)
        sn = sin(Double(i)*2*Double.pi*F0)

        V0 = TwoCmplt.multN(lhs: X0, rhs: coeff2, rshift: 16) 
        XI1 = X1 + V0
        V1 = TwoCmplt.multN(lhs: XI1, rhs: coeff2, rshift: 16) 
        XI0 = X0 - V1

        if X1 < 0 && XI1 > 0 {
            print("i: \(i), X0: \(X0.toInt()), XI0: \(XI0.toInt()), X1: \(X1.toInt())")
        }

        if X0 < 0 && XI0 > 0 {
            // print("i: \(i), X0: \(X0.toInt()), XI0: \(XI0.toInt()), X1: \(X1.toInt())")
        }
        if i > N-66 {
            print("i: \(i), X0: \(X0.toInt()), X1: \(X1.toInt())")
        }

        X0 = XI0
        X1 = XI1

        if X1 > 0x7FFF0 {
            X1 = X1 - 4
        }

        Out[i] = X1.toInt()
        // print("i: \(i), X0: \(X0.toInt()), X1: \(X1.toInt()), sync: \(M0.sync)")
        // print("i: \(i), cs: \(String(format: "%7.5f", cs)), sn: \(String(format: "%7.5f", sn))")

        /*
        if i == 240 {
            M0.coeff = TwoCmplt(0x63e4, nbits: 20)
        }
        */

        rl1 = (X0.toInt() > 0) ? rl1 + cs : rl1 - cs
        rl2 = (X1.toInt() > 0) ? rl2 + sn : rl2 - sn
        rl3 = (rl1 - rl2)/pow(2.0, 28)
        qd1 = (X0.toInt() > 0) ? qd1 + sn : qd1 - sn
        qd2 = (X1.toInt() > 0) ? qd2 + cs : qd2 - cs
        qd3 = (qd1 + qd2)/pow(2.0, 28)
        /*
        if (i > 2082) {
            // print("i: \(i), rl3: \(String(format: "%7.5f", rl3)), qd3: \(String(format: "%7.5f", qd3)), coeff: \(coeff.toInt()), deltPhi: \(deltPhi)")
            print("i: \(i), X0: \(X0.toInt()), X1: \(X1.toInt())")
        }
        */

        // print("i: \(i), rl3: \(String(format: "%7.5f", rl3)), qd3: \(String(format: "%7.5f", qd3)), coeff: \(coeff.toInt()), deltPhi: \(deltPhi)")

        deltPhi = deltPhi + 0.0*1e-16*qd3
        deltaCoeff = Int(2.0e-12*qd3*pow(2,4.0).rounded())
        coeff = coeff + TwoCmplt(deltaCoeff, nbits: 20)

        ()
      }
    _ = Out

    let path = "/home/Dropbox/programming/Swift/PlotResponse/Osc3.dat"
    withFile(path, mode: "w") { fp in
        for val in Out {
            // Write the string and add a newline
            let line = "\(String(format: "%d", val))\n"
            fputs(line, fp)
        }
    }

    print("rls3: \(rl3)")
    ()
}


@main
struct RunOsc1 {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            SimOsc3 (coeff: 0x63e2, N: 65536, accum: 0xE0CAC0)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
