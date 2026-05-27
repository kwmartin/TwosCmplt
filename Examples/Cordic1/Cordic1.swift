/* Cordic.swift: an example of a high-level simulation using the TwoCmplt Library
 *
 * This example is a simulation of a DDFS based on using a CORDIC architecture to calculate
 * cosine and sine functions.
 *
 * The approach illustrates using structs for each block in the system
 * The structs are normally updated once per clock cycle
 *
 */


import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams
import ExamplesShared

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
func SimDDFS (freq: UInt, N: Int) {

    var accum: Accum = Accum(freq: freq)
    var pre_rotate: PRErotate = PRErotate()
    var xaccum: TwoCmplt = TwoCmplt(0, nbits: 20, signed: false)
    var phiIdeal: TwoCmplt = TwoCmplt(0, nbits: 22, signed: false)
    // let scale = 0.6476382027663665
    // let scale = 0.894427191
    let scale = 0.8587853364804277
    let nmbFLys: Int = 16

    var X0 = TwoCmplt(Int(scale*1048576.0), nbits: 22, signed: true)
    var Y0 = TwoCmplt(0, nbits: 22, signed: true)
    var Z0 = TwoCmplt(0, nbits: 22, signed: true)

    var X1 = TwoCmplt(0, nbits: 22, signed: true)
    var Y1 = TwoCmplt(0, nbits: 22, signed: true)
    var Z1 = TwoCmplt(0, nbits: 22, signed: true)

    var rotate_vals: [Int]?
    var butterFlys: [butterFly] = []

    var Xout: [Int] = Array(repeating: 0, count: N)
    var Yout: [Int] = Array(repeating: 0, count: N)

    /*
    do {
        let cwd = FileManager.default.currentDirectoryPath
        let path = "\(cwd)/Examples/Resources/rotations.dat"
        rotate_vals = try readDat(from: path)
        print(rotate_vals ?? [])
    } catch {
        print("Failed to read or parse file: \(error)")
    }
    */
    rotate_vals = rdData(from: "rotations.dat")

    if let rotate_vals = rotate_vals {
        butterFlys = (0...15).map { butterFly(rotate: (rotate_vals[$0]), index: ($0 + 2)) }
        // Use butterFlys...
    }
    // print(butterFlys[0])

    // let F0: Double = 1.00/16.0
    // var cs: Double
    // var sn: Double

    // var rl1 = 0.0, rl2 = 0.0, rl3 = 0.0
    // var qd1 = 0.0, qd2 = 0.0, qd3 = 0.0

    /*
    Take (1<<20, 0) and rotate by pi/8, and then normalize back to magnitude of
    1<<20 and the multiply by scale = 0.8587853364804277
    */

    let Zinit: TwoCmplt = TwoCmplt(65536, nbits: 22, signed: true)
    let Xinit = 930149
    let Yinit = 385280

    for i in 0..<N {
        // cs = cos(Double(i)*2*Double.pi*F0)
        // sn = sin(Double(i)*2*Double.pi*F0)
        // print("i: \(i), cs: \(String(format: "%7.5f", cs)), sn: \(String(format: "%7.5f", sn))")

        X0 = TwoCmplt(Xinit, nbits: 22, signed: true)
        Y0 = TwoCmplt(Yinit, nbits: 22, signed: true)

        xaccum = (accum.update())
        xaccum.setNbits(20) // to be compatible with pre_rotate
        // print("i: \(i), xaccum: \(xaccum)")

        phiIdeal = pre_rotate.update(accum: (xaccum << 2))
        Z0 = phiIdeal - Zinit

        // print("i: \(i), phiIdeal: \(phiIdeal.toInt())")

        for k in 0..<nmbFLys {
            (X1, Y1, Z1) = butterFlys[k].update(X: X0, Y: Y0, Z: Z0)
            // print("k: \(k)", X1.toInt(), Y1.toInt(), Z1.toInt())
            X0 = X1
            Y0 = Y1
            Z0 = Z1
        }

        // print("i: \(i), X1: \(X1.toInt()), Y1: \( Y1.toInt()), Z1: \(Z1.toInt())")
        ()
        if pre_rotate.swap {
            swap( &X1, &Y1)
        }

        X1 = pre_rotate.xinvert ? -X1 : X1
        Y1 = pre_rotate.yinvert ? -Y1 : Y1

        // print("i: \(i), X1: \(X1.toInt()), Y1: \( Y1.toInt()), Z1: \(Z1.toInt())")

        Xout[i] = X1.toInt()
        Yout[i] = Y1.toInt()
        ()
      }

    //
    let path = "/home/Dropbox/programming/Swift/TwosCmplt/PlotResponse/Cordic1.dat"
    withFile(path, mode: "w") { fp in
        for i in 0..<N {
            // Write the string and add a newline
            let line = "\(String(format: "%d", Xout[i])) \(String(format: "%d", Yout[i]))\n"
            fputs(line, fp)
        }
    }
    ()
}

@main
struct RunCordic1 {
    static func main() {

        // Set freq = (1<<36)/Per, N = 2049*Per, and delete first T lines of output file
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            SimDDFS (freq: 0x7c1f07c1, N: 67617)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
