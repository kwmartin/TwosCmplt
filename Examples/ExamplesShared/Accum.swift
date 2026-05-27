/**
 * A struct to realize an accumultor
 */

import TwosCmplt
import SharedTypes
import Foundation

/** 
 * struct Accum
 * The Accumulator for generating the phase of a DDFS
 *
 * - Parameter freq: a 34-bit UInt to specify the frequency of the DDFS
 *
 * - Parameter X0: The lower order 16-bit register to specify fine resolution
 *                 Its carry-out is fed to the carry-in of the main accumulator
 * - Parameter X1: The main 18-bit register to specify the phase. The two MSBs
 *                 specify the quadrant. The third MSB specifies lower half or
 *                 upper half of quadrant.
 */
public struct Accum {
    public var freq: UInt = 0
    let f0: UInt
    let f1: UInt
    public var X0: TwoCmplt = TwoCmplt(0, nbits: 18)
    public var X1: TwoCmplt = TwoCmplt(0, nbits: 18)

    /**
     * initialize two's complement variable setting the value using value:.
     *
     * - Parameter freq: sets the frequency of the DDFS
     *
     */
    public init(freq: UInt) {
        self.freq = freq
        self.f0 = freq & ((1<<18) - 1)
        self.f1 = (freq>>18) & ((1<<18) - 1)
    }

    public mutating func update () -> TwoCmplt {
        self.X0 = self.X0 + Int(self.f0)
        self.X1 = self.X1 + Int(self.f1)
        self.X1 = self.X0.crry ? (self.X1 + 1) : self.X1
        return self.X1
    }
}
