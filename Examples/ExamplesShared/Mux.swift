/**
 * Mux, a struct to implement a 16 to 1 multiplexor. This effectively realizes a 16-word
 * ROM. The inputs to the multiplexor come from a data file residing in the same directory
 * that is read at initilization. 
 */

import TwosCmplt
import SharedTypes
import Foundation

/** 
 * struct Mux
 * Take a 4-bit TwoCmplt select input and outputs one of 16 hard-coded values that
 * are initially up-loaded from a data file in the same directory (the directory might
 * change before release; for now we want to keep it simple.
 *
 */
public struct Mux {
    public var datVals: [TwoCmplt] = []

    /**
     * initialize MSB_anal instance
     *
     */
    public init(dataFile: String) {
        var data_vals: [Int]?

        data_vals = rdData(from: dataFile)

        if let data_vals = data_vals {
            self.datVals = (0...15).map { TwoCmplt(data_vals[$0], nbits: 22, signed: true) }
        }
    }

/**
 * selectDat is a multiplexor used to output a fixed TwoCmplt value dependedant
 * on the TwoCmplt slct input
 *
 * - Parameter slct: a 4-bit TwoCmplt used to select one of self.datVals[slct] 
 *
 * - Returns: a TwoCmplt equal to self.datVals[slct]
 *
 */
    public mutating func selectDat(slct: Int) -> TwoCmplt {
        return self.datVals[slct]
    }
}
