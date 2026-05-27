import TwosCmplt

import SharedTypes
import Foundation
import Glibc
import Yams

/*
 * CmplxMltply:
 * Examples showing the use of a complex multiply:
 * OutR, OutQ = InR * coeffR - InQ * coeffQ, InR * coeffQ + InQ * coeffR
 * The multiply is done using our multiplexor based fixed coefficient multiplyer
 * and carry-save blocks (including the csA2S() where the first two inputs are considered
 * positive and the third input is considered negative. Seven csAdd()'s and 1 csA2S() are
 * required for the real and for the quadrature path; the depth is 5 csAdd()'s followed by
 * a full adder()
 *
 */

func CmplxShift(_ inFreq: Double, _ freqShft: Double) {
    let N = 34816
    var cs: Int
    var sn: Int
    var InR = TwoCmplt(0, nbits: 20, signed: true)
    var InQ = TwoCmplt(0, nbits: 20, signed: true)

    var shftCs = Int((0x100000 * cos(2*Double.pi*freqShft)).rounded())
    var shftSn = Int((0x100000 * sin(2*Double.pi*freqShft)).rounded())
    var cMlt = CmplxMlt(rval: shftCs, qval: shftSn, nbits: 24)

    var Outr: [Int] = Array(repeating: 0, count: N)
    var Outq: [Int] = Array(repeating: 0, count: N)

    for i in 0..<34816 {

        // cs = 32767.0 * cos(Double(i)*2*Double.pi*inFreq + deltPhi)
        // sn = 32767.0 * sin(Double(i)*2*Double.pi*inFreq + deltPhi)
        cs = Int((0x40000 * cos(Double(i)*2*Double.pi*inFreq)).rounded())
        sn = Int((0x40000 * sin(Double(i)*2*Double.pi*inFreq)).rounded())
        InR.set(cs)
        InQ.set(sn)

        shftCs = Int((0x100000 * cos(Double(i)*2*Double.pi*freqShft)).rounded())
        shftSn = Int((0x100000 * sin(Double(i)*2*Double.pi*freqShft)).rounded())
        cMlt = CmplxMlt(rval: shftCs, qval: shftSn, nbits: 24)

        let (OutR, OutQ) = cMlt.mult((InR, InQ))

        Outr[i] = OutR.toInt()
        Outq[i] = OutQ.toInt()

        print("InR: \(InR.toInt()), InQ: \(InQ.toInt()), OutR: \(OutR.toInt()), OutQ: \(OutQ.toInt()), shftCs: \(shftCs), shftSn: \(shftSn), ")
    }
    let path = "/home/Dropbox/programming/Swift/TwosCmplt/PlotResponse/CmplxMltply.dat"
    withFile(path, mode: "w") { fp in
        for i in 0..<N {
            // Write the string and add a newline
            let line = "\(String(format: "%d", Outr[i])) \(String(format: "%d", Outq[i]))\n"
            fputs(line, fp)
        }
    }
}

func CmplxMltply (){
    // let InR = TwoCmplt(0x1ff62, nbits: 20, signed: true)
    // let InQ = TwoCmplt(0x191f, nbits: 20, signed: true)
    // let InR = TwoCmplt(0x1fd89, nbits: 20, signed: true)
    // let InQ = TwoCmplt(0x322f, nbits: 20, signed: true)
    let InR = TwoCmplt(0x2d414, nbits: 20, signed: true)
    let InQ = TwoCmplt(0x2d414, nbits: 20, signed: true)

    var cMlt = CmplxMlt(rval: 0xb504e, qval: -0xb504e, nbits: 24)
    // var cMlt = CmplxMlt(rval: -0xfffff, qval: -0x00000, nbits: 24)
    // var cMlt = CmplxMlt(rval: -0x1fa75, qval: -0x4b20, nbits: 24)
    // let cMlt = CmplxMlt(rval: 0xffb10, qval: 0xc8fb, nbits: 24)
    // let cMlt = CmplxMlt(rval: 0xfec46, qval: 0x1917a, nbits: 24)
    // let cMlt = CmplxMlt(rval: 0x1fa75, qval: 0x4b20, nbits: 24)
    let (OutR, OutQ) = cMlt.mult2((InR, InQ))
    print("OutR: \(OutR.toInt()), OutQ: \(OutQ.toInt())")
 }

@main
struct RunCmplxMltply {
    static func main() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            CmplxMltply()
            // CmplxShift(-0.25, 0.1875)
        }
        print("Elapsed Time: \(elapsed)")

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("Time: ", String(format: "%.4f", seconds)) // prints 15 digits after decimal
    }
}
