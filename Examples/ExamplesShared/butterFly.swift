/**
 * A struct to realize an accumultor
 */

import TwosCmplt
import SharedTypes
import Foundation

/** 
 * struct MSB_anal
 * The Pre analysis to allow operation over 0 to pi/4 based on Madisetti
 *
 */
public struct butterFly {
    public var rotate: TwoCmplt = TwoCmplt(0, nbits: 22, signed: false)
    public var k: Int

    /**
     * initialize butterFly instance
     *
     */
    public init(rotate: Int, index: Int) {
        self.rotate.value = rotate
        self.k = index
    }

    public mutating func update (
        X: TwoCmplt, Y: TwoCmplt, Z: TwoCmplt) -> 
            (TwoCmplt, TwoCmplt, TwoCmplt) {
        let Xout: TwoCmplt
        let Yout: TwoCmplt
        let Zout: TwoCmplt

        let sign = Z.selBits(n1: 19, n2: 19).toInt()
        let k = self.k
        if sign == 0 {
            Xout = X - (Y >> k)
            Yout = Y + (X >> k)
            Zout = Z - self.rotate
        } else {
            Xout = X + (Y >> k)
            Yout = Y - (X >> k)
            Zout = Z + self.rotate
        }
    return (Xout, Yout, Zout)
    }
}
