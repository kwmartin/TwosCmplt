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
public struct MSB_anal {
    public var swap: Bool
    public var xinvert: Bool
    public var yinvert: Bool
    public var sector: Int
    public var bit2: Int
    public var bit1: Int
    public var bit0: Int
    public var rom_slct: Int

    /**
     * initialize MSB_anal instance
     *
     */
    public init() {
        self.swap = false
        self.xinvert = false
        self.yinvert = false
        self.sector = 0
        self.bit2 = 0
        self.bit1 = 0
        self.bit0 = 0
        self.rom_slct = 0
    }

/**
 * update is used to set sector, invert, and swap bits. It expects accum
 * is 20 bits.
 *
 * - Parameter accum: the output of the DDSF accumulator as a TwoCmplt
 *
 * - Returns: either the accumulator as a TwoCmplt, or Pi/2 - accumulator
 *            if in a quadrant where swap is necessary
 *
 */
    public mutating func update (accum: TwoCmplt) -> TwoCmplt {
        self.sector = ((accum.toInt()) >> 17) & 0x7
        self.bit0 = (self.sector & 1)
        self.bit1 = (self.sector & 2) >> 1
        self.bit2 = (self.sector & 4) >> 2
        let bit0 = self.bit0
        let bit1 = self.bit1
        let bit2 = self.bit2
        self.swap = (bit1 ^ bit0) == 1 ? true : false
        self.xinvert = (bit2 ^ bit1) == 1 ? true : false
        self.yinvert = bit2 == 1 ? true : false
        self.rom_slct = accum.selBits(n1: 16, n2: 13).value

        let signal = accum.toInt() & 0x3FFFF
        if (bit0 == 1) && rom_slct != 0 {
            rom_slct = 0x10 - rom_slct
        }
        return TwoCmplt(signal, nbits: 22)
    }
}
