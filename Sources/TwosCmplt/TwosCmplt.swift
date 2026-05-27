import SharedTypes

public typealias CSin = (A: TwoCmplt, B: TwoCmplt, C: TwoCmplt)
public typealias CSout = (sum: TwoCmplt, crry: TwoCmplt)

let getCrry: @Sendable (Int, Int, Int) -> Int = { (a, b, c) in
    return ((a & b) | (b & c) | (a & c))
}

let getSum: @Sendable (Int, Int, Int) -> Int = { (a, b, c) in
    return (a^b^c)
}

let getCrryM: @Sendable (Int, Int, Int) -> Int = { (a, b, c) in
    let d = ~c
    return ((a & b) | (b & d) | (a & d))
}

let exNor: @Sendable (Int, Int, Int) -> Int = { (a, b, c) in
    let d = ~c
    return (a^b^d)
}

extension TwoCmplt {

    /**
     * A carry-save adder that takes three TwoCmplt args and produces sum and carry TwoCmplt outputs
     * Note: the inputs should all have the same nbits as it's not currently checked or adjuste to maximize
     * speed. Also, the output nbits is one bit larger than the nbits of the inputs
     *
     * - Parameter csin: A named Tuple (CSin) of three TwoCmplt inputs
     *
     * - Returns: a CSout which is a named Tuple (CSout) of the sum and which is concatentation of all values in the list
     */
    public static func csAdd(csin: [TwoCmplt]) -> CSout {
        let sumOut: TwoCmplt
        let crryOut: TwoCmplt
        let a: Int = csin[0].toInt()
        let b: Int = csin[1].toInt()
        let c: Int = csin[2].toInt()
        let sum = getSum(a, b, c)
        let carry: Int = getCrry(a, b, c) // getCrry is a closure defined at beginning of file (a|b & a|c & b|c)
        let crry = carry << 1
        sumOut = TwoCmplt(sum, nbits: csin[0].nbits, prec: csin[0].prec, signed: csin[0].signed)
        crryOut = TwoCmplt(crry, nbits: csin[0].nbits, prec: csin[0].prec, signed: csin[0].signed)
        return (sum: sumOut, crry: crryOut)
    }

    /**
     * A carry-save adder that takes three Int args, and nbits: and produces sum and carry TwoCmplt outputs
     * The output nbits is one bit larger than the nbits specified to account for carry
     *
     * - Parameter csin: A named Tuple (CSin) of three Int inputs
     * - Parameter nbits: The input Int's are truncated to nbits. The output nbits is input nbits.
     *
     * - Returns: a Returns: a Tuple of the sum and carry output of the csAdd
     */
    public static func csAdd(csin: [Int], nbits: Int) -> CSout {
        let sumOut: TwoCmplt
        let crryOut: TwoCmplt
        let msk = ((1<<nbits) - 1)
        let a: Int = csin[0] & ((1<<nbits) - 1)
        let b: Int = csin[1] & ((1<<nbits) - 1)
        let c: Int = csin[2] & ((1<<nbits) - 1)
        let sum = getSum(a, b, c) // getSum is a closure at beginning of file implementing a^b^c
        let carry: Int = getCrry(a, b, c) & msk // getCrry is a closure defined at beginning of file (a|b & a|c & b|c)
        let crry = (carry << 1) &  msk
        sumOut = TwoCmplt(sum, nbits: nbits, prec: 0, signed: true)
        crryOut = TwoCmplt(crry, nbits: nbits, prec: 0, signed: true)
        return (sum: sumOut, crry: crryOut)
    }

    /**
     * Similar to a carry-save adder but with an additional input (neg) to do operations
     * requred when signal is negative. The third input should self.coeff. Do regular csAdd()
     * with third input being self.coeff, invert both outputs, and then implement csAdd()
     * with third input being 0x1 to return output to a negative value.
     *
     * - Parameter csin: A named Tuple (CSin) of three Int inputs
     * - Parameter nbits: The input Int's are truncated to nbits. The output nbits is input nbits.
     * - Parameter neg: when 1, add 1 to output.
     *
     * - Returns: a Returns: a Tuple of the sum and carry output of the csAdd
     */
    public static func csAddp1(csin: [Int], nbits: Int, neg: Int) -> CSout {
        let sumOut: TwoCmplt
        let crryOut: TwoCmplt

        if neg == 0 { // just pass through the first two inputs
            sumOut = TwoCmplt(csin[0], nbits: nbits, prec: 0, signed: true)
            crryOut = TwoCmplt(csin[1], nbits: nbits, prec: 0, signed: true)
        } else {
            let msk = ((1<<nbits) - 1)
            let a: Int = csin[0] & ((1<<nbits) - 1)
            let b: Int = csin[1] & ((1<<nbits) - 1)
            let c: Int = csin[2] & ((1<<nbits) - 1)
            let sum = getSum(a, b, c)
            let carry: Int = getCrry(a, b, c) & msk // getCrry is a closure defined at beginning of file (a|b & a|c & b|c)
            let crry = (carry << 1) &  msk
            sumOut = TwoCmplt(sum, nbits: nbits, prec: 0, signed: true)
            crryOut = TwoCmplt(crry, nbits: nbits, prec: 0, signed: true)
        }
        return (sum: sumOut, crry: crryOut)
    }

    /**
     * A carry-save adder that takes three Int args, and nbits: and produces a + b - c and carry TwoCmplt outputs
     * The output nbits is one bit larger than the nbits specified to account for carry
     * The approach used is to invert c bits and to add 1 to vacant c[0] bit position.
     *
     * - Parameter csin: A named Tuple (CSin) of three TwoCmplt inputs
     * - Parameter nbits: The input Int's are truncated to nbits. The output nbits is input nbits.
     *
     * - Returns: a Tuple of the sum and carry of a + b - c output of the csAdd
     */
    public static func csA2S(csin: [Int], nbits: Int) -> CSout {
        let sumOut: TwoCmplt
        let crryOut: TwoCmplt
        let msk = ((1<<nbits) - 1)
        let msk_out = ((1<<nbits) - 1)
        let a: Int = csin[0] & msk
        let b: Int = csin[1] & msk
        let c: Int = csin[2] & msk
        let d = (~c) & msk
        // let sum = exNor(a, b, d)
        let sum = (a^b^d) & msk
        // let carry: Int = getCrryM(a, b, c) // getCrry is a closure defined at beginning of file (a|b & a|nc & b|nc).
        let carry = ((a & b) | (b & d) | (a & d)) & msk_out
        let crry = ((carry << 1) + 1) & msk_out // Note we add a "1" to the normally empty LSB of crry.
        sumOut = TwoCmplt(sum, nbits: nbits, prec: 0, signed: true)
        crryOut = TwoCmplt(crry, nbits: nbits, prec: 0, signed: true)
        return (sum: sumOut, crry: crryOut)
    }

    /**
     * A carry-save adder that takes three Int args, and nbits: and produces a + b - c and carry TwoCmplt outputs
     * The output nbits is one bit larger than the nbits specified to account for carry
     * This csAdd includes the third input if neg == 1, otherwise it sets it to zero.
     * It also adds a 1 to the vacant CrryOut[0] bit.
     *
     * - Parameter csin: A named Tuple (CSin) of three TwoCmplt inputs
     * - Parameter nbits: The input Int's are truncated to nbits. The output nbits is input nbits.
     * - Parameter neg: when 1, add 1 to output.
     *
     * - Returns: a Tuple of the sum and carry of a + b - c output of the csAdd
     */
    public static func csA2Sp1(csin: [Int], nbits: Int, neg: Int) -> CSout {
        let sumOut: TwoCmplt
        let crryOut: TwoCmplt
        let msk = ((1<<nbits) - 1)
        let msk_out = ((1<<nbits) - 1)
        let a: Int = csin[0] & msk
        let b: Int = csin[1] & msk
        let c: Int = csin[2] & msk
        let d = (~c) & msk
        // let sum = exNor(a, b, d)
        let sum = (a^b^d) & msk
        // let carry: Int = getCrryM(a, b, c) // getCrryM is a closure defined at beginning of file (a|b & a|nc & b|nc)
        let carry = ((a & b) | (b & d) | (a & d)) & msk_out
        let crry = ((carry << 1) + 1) & msk_out

        // The next few lines effectively add a "1" to help in the -out operation when neg is a "1"
        let sum0 = (sum&0x1)^neg
        let sOut = sum | sum0
        let cOut = ((sum0 & neg)<<1) | crry // i.e. when neg == 1, we know c[0] is a "1"

        sumOut = TwoCmplt(sOut, nbits: nbits, prec: 0, signed: true)
        crryOut = TwoCmplt(cOut, nbits: nbits, prec: 0, signed: true)

        return (sum: sumOut, crry: crryOut)
    }

    /**
     * A carry-save adder that takes three Int args, and nbits: and produces a + b + c and carry TwoCmplt outputs
     * The output nbits is one bit larger than the nbits specified to account for carry
     * This is the same as csAdd except it has a third input that when 0 sets third input to 0
     *
     * - Parameter csin: A named Tuple (CSin) of three TwoCmplt inputs
     * - Parameter nbits: The input Int's are truncated to nbits. The output nbits is input nbits.
     * - Parameter neg: when 1, don't subtract third input
     *
     * - Returns: a Tuple of the sum and carry of a + b - c output of the csAdd
     */
    public static func csA2Sp3(csin: [Int], nbits: Int, neg: Int) -> CSout {
        let sumOut: TwoCmplt
        let crryOut: TwoCmplt
        let msk = ((1<<nbits) - 1)
        let msk_out = ((1<<nbits) - 1)
        let a: Int = csin[0] & msk
        let b: Int = csin[1] & msk
        let c: Int = csin[2] & msk
        let d = neg == 1 ? c & msk : 0
        let sum = (a^b^d) & msk
        let carry = ((a & b) | (b & d) | (a & d)) & msk_out
        let crry = (carry << 1) & msk_out // Note we add a "1" to the normally empty LSB of crry.
        sumOut = TwoCmplt(sum, nbits: nbits, prec: 0, signed: true)
        crryOut = TwoCmplt(crry, nbits: nbits, prec: 0, signed: true)
        return (sum: sumOut, crry: crryOut)
    }

    /**
     * Uses csAdd's and a TwoCmplt + operation to take an array of TwoCmplt's and output their sum.
     * The output nbits is one bit larger than the nbits of the inputs
     *
     * - Parameter csin: An array of TwoCmplt values
     *
     * - Returns: a TwoCmplt which is the sum of array values
     */
    public static func csAddN(csin: [TwoCmplt]) -> TwoCmplt {

        var output = csAdd(csin: [csin[0], csin[1], csin[2]])

        for next in csin.dropFirst(3) {
            output = csAdd(csin: [output.sum, output.crry, next])
        }

        let outVal = output.sum + output.crry
        return outVal
    }

    /**
     * Uses csAdd and a TwoCmplt + operation to take an array of three TwoCmplt's and outputs a + b - c.
     * The output nbits is one bit larger than the nbits of the inputs. This is intended for digital filters.
     *
     * - Parameter csin: An array of Three TwoCmplt values
     *
     * - Returns: a TwoCmplt which is the sum of the first two minus the third
     */
    public static func csAdd2Subt1(csin: [TwoCmplt]) -> TwoCmplt {

        let output = csAdd(csin: [csin[0], csin[1], ~csin[2]])

        let outVal = output.sum + (output.crry | 1)
        return outVal
    }

    /**
     * Uses csAddN and a TwoCmplt + operation to take an array of four TwoCmplt's and outputs a + b + c - d.
     * The output nbits is one bit larger than the nbits of the inputs. This is useful in digital filters
     *
     * - Parameter csin: An array of Three TwoCmplt values
     *
     * - Returns: a TwoCmplt which is the sum of the first two minus the third
     */
    public static func csAdd3Subt1(csin: [TwoCmplt]) -> TwoCmplt {

        let output1 = csAdd(csin: [csin[0], csin[1], csin[2]])
        let output2 = csAdd(csin: [output1.sum, output1.crry, ~csin[3]])

        let outVal = output2.sum + (output2.crry | 1)
        return outVal
    }

    public var debugToInt: Int { toInt() }

    /**
     * Changes the size of a TwoCmplt. If increasing the size, there is sign-extension
     * If decreasing the size, there may be truncation; this is not checked
     *
     * - Parameter nbits:  Int, the new size
     */
    public func setNbits( nbits: Int) -> TwoCmplt {
        var xout: TwoCmplt
        if nbits == self.nbits {
            xout = self
            return xout
        }
        if nbits > self.nbits {
            let val = self.toInt()
            xout = TwoCmplt(val, nbits: nbits, prec: self.prec, signed: self.signed)
        } else {
            xout = self >> (nbits - self.nbits)
        }
        return xout
    }

}
