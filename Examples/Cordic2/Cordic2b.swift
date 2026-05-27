/* Cordic2b.swift: an example of a high-level simulation using the TwoCmplt Library
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

public func MultPIovr4( xin: TwoCmplt ) -> TwoCmplt {
    var xout: TwoCmplt = TwoCmplt(0, nbits: 22)
    let val0 = xin.setNbits(nbits: 22)
    xout = TwoCmplt.csAddN(csin: [val0>>1, val0>>2, val0>>5, val0>>8, val0>>12])
    return xout
}

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
func SimDDFS2b (freq: UInt, N: Int) {

    let I18 = (1<<18)
    let I20 = (1<<20)
    let D18 = Double(I18)
    let D20 = Double(I20)
    let PI = Double.pi

    var accum: Accum = Accum(freq: freq)
    var bttrFlys: [butterFly] = []

    var XlookUp: Mux = Mux(dataFile: "Xtable.dat")
    var YlookUp: Mux = Mux(dataFile: "Ytable.dat")

    // print(mux3.datVals)

    var msb_anal: MSB_anal = MSB_anal()
    var xaccum: TwoCmplt = TwoCmplt(0, nbits: 22, signed: false)
    var xpi_ovr4: TwoCmplt = TwoCmplt(0, nbits: 22, signed: false)
    var xaddr: TwoCmplt = TwoCmplt(0, nbits: 22, signed: false)

    // let scale = 0.6476382027663665
    // let scale = 0.894427191
    let scale = 0.8587853364804277
    let nmbFLys = 14

    var X0 = TwoCmplt(Int(scale*1048576.0), nbits: 22, signed: true)
    var Y0 = TwoCmplt(0, nbits: 22, signed: true)
    var Z0 = TwoCmplt(0, nbits: 22, signed: true)

    var X1 = TwoCmplt(0, nbits: 22, signed: true)
    var Y1 = TwoCmplt(0, nbits: 22, signed: true)
    var Z1 = TwoCmplt(0, nbits: 22)

    var Xout: [Int] = Array(repeating: 0, count: N)
    var Yout: [Int] = Array(repeating: 0, count: N)
    var Xidl: Int
    var Yidl: Int
    var Xidls: [Int] = Array(repeating: 0, count: N)
    var Yidls: [Int] = Array(repeating: 0, count: N)
    var Xerrs: [Int] = Array(repeating: 0, count: N)
    var Yerrs: [Int] = Array(repeating: 0, count: N)

    // let F0: Double = 1.00/33.0
    // var cs: Double
    // var sn: Double

    let startValue = 5213.4925 // (1<<20)*tan(1/(1<<5)*1/(2*pi))
    // let rotate_vals = (0..<nmbFLys).map { startValue >> $0 }
    let rotate_vals = (0..<nmbFLys).map { Int(round(startValue/(pow(2.0, Double($0))))) }
    bttrFlys = (0..<nmbFLys).map { butterFly(rotate: (rotate_vals[$0]), index: ($0 + 5)) }

    _ = Y0

    // The next bit is just to test csAdd2Subt1() without having to do a whole new test bench
    let val0 = TwoCmplt(-13, nbits: 22, signed: true)
    let val1 = TwoCmplt(27, nbits: 22, signed: true)
    let val2 = TwoCmplt(-22, nbits: 22, signed: true)
    // let val3 = TwoCmplt(-32, nbits: 22, signed: true)
    let val4 = TwoCmplt.csAdd2Subt1(csin: [val0, val1, val2])
    print(val4, "(\(val4.toInt()))")

    for i in 0..<N {
        xaccum = (accum.update())
        xaccum.setNbits(22) // to be compatible with msb_anal, otherwise 2 MSB's are lost

        Xidl = Int(round(D20*cos(2*PI*Double(xaccum.toInt())/D18)))
        Yidl = Int(round(D20*sin(2*PI*Double(xaccum.toInt())/D18)))
        Xidls[i] = Xidl
        Yidls[i] = Yidl
        // cs = cos(Double(i)*2*Double.pi*F0)
        // sn = sin(Double(i)*2*Double.pi*F0)
        // print("i: \(i), cs: \(String(format: "%7.5f", cs)), sn: \(String(format: "%7.5f", sn))")

        xpi_ovr4 = msb_anal.update(accum: (xaccum << 2))

        if msb_anal.rom_slct == 0 {
            switch msb_anal.sector {
                case 0:
                    X0.value = 1047893
                    Y0.value = 0
                    msb_anal.xinvert = false
                    msb_anal.yinvert = false
                case 1:
                    X0.value = 740972
                    Y0.value = 740972
                    msb_anal.xinvert = false
                    msb_anal.yinvert = false
                case 2:
                    X0.value = 0
                    Y0.value = 1047893
                    msb_anal.xinvert = true
                    msb_anal.yinvert = false
                case 3:
                    X0.value = 740972
                    Y0.value = 740972
                    msb_anal.xinvert = true
                    msb_anal.yinvert = false
                case 4:
                    X0.value = 1047893
                    Y0.value = 0
                    msb_anal.xinvert = true
                    msb_anal.yinvert = true
                case 5:
                    X0.value = 740972
                    Y0.value = 740972
                    msb_anal.xinvert = true
                    msb_anal.yinvert = true
                case 6:
                    X0.value = 1047893
                    Y0.value = 0
                    msb_anal.xinvert = false
                    msb_anal.yinvert = true
                case 7:
                    X0.value = 740972
                    Y0.value = 740972
                    msb_anal.xinvert = false
                    msb_anal.yinvert = true
                case _:
                    print("Shouldn't be necessary as case is exhaustive")
            }
        } else {
            if msb_anal.bit0 == 1 {
                // Note: X0 uses Ylookup, and Xlookup when bit0 is a 1
                X0 =  YlookUp.selectDat(slct: msb_anal.rom_slct)
                Y0 =  XlookUp.selectDat(slct: msb_anal.rom_slct)
            } else {
                X0 =  XlookUp.selectDat(slct: msb_anal.rom_slct)
                Y0 =  YlookUp.selectDat(slct: msb_anal.rom_slct)
            }
        }

        xaddr = xpi_ovr4
        Z0 = xaddr & ((1<<13) - 1)

        for k in 0..<nmbFLys {
            (X1, Y1, Z1) = bttrFlys[k].update(X: X0, Y: Y0, Z: Z0)
            // print("k: \(k), X1: \(X1.toInt()), Y1: \(Y1.toInt()), Z1: \(Z1.toInt())")
            (X0, Y0, Z0) = (X1, Y1, Z1)
        }

        if msb_anal.bit1 == 1 { swap( &X1, &Y1) }

        // print("i: \(i), X1: \(X1.toInt()), Y1: \( Y1.toInt()), Z1: \(Z1.toInt())")
        ()
        X1 = msb_anal.xinvert ? -X1 : X1
        Y1 = msb_anal.yinvert ? -Y1 : Y1

        // print("i: \(i), X1: \(X1.toInt()), Y1: \( Y1.toInt()))")

        Xout[i] = X1.toInt()
        Yout[i] = Y1.toInt()
        Xerrs[i] = Xout[i] - Xidls[i]
        Yerrs[i] = Yout[i] - Yidls[i]
        ()
    }

    //
    let path = "/home/Dropbox/programming/Swift/TwosCmplt/tools/Cordic2b.dat"
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
struct RunCordic2b {
    static func main() {
        // Set freq = (1<<36)/Per, N = 2049*Per, and delete first T lines of output file
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            SimDDFS2b (freq: 0x7c1f07c1, N: 67617)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 4 digits after decimal
        ()
    }
}
