import TwosCmplt

import SharedTypes


/*
When using two's complement signal processing having a finite
precision with prec > 0, we can define the format as being
n1.n2, where nbits = n1+n2, and the prec is n2. For example,
a finite precision general purpose signal processor might use
a format of 16.4, which requires 20 bit operations. It would be
interesting to see if this could be implemented in a GPU?
*/

/*
Running Swift in Ubuntu, with Vscode, I can't get testing
working correctly yet (I'm brand new to Swift - but I think I like it?).
I'll fix this when I figure out how.
*/

var var1 = TwoCmplt(value: 123, nbits: 12, signed: true)
print("Line 4 in main.swift in TwosCmpltTestingRunner")
assert(var1.value == 123)

let var2 = TwoCmplt(value: -1, nbits: 14, prec: 2, signed: true)
var var3: TwoCmplt
var3 = var1 + var2
print("var3: \(var3)")
assert(var3.value == 491)

var var4  = TwoCmplt(value: -15.5, nbits: 12, prec: 4, signed: true, rnd: true)
print("var4: \(var4)")
assert(var4.value == 0xf08)

let var5 = var4 >> 2
print("var5: \(var5)")

let var6 = TwoCmplt(value: 0x7a3, nbits: 12)
let var7 = var6.selBits(n1: 7, n2: 4)
print("var7: \(var7)")
print(var7.display())

let var8 = TwoCmplt(value: 0xfa3, nbits: 12, signed: true) << 3
let var9 = TwoCmplt(value: 0x3a3, nbits: 12, signed: true) << 6
print("var8: \(var8), var9: \(var9)")

let var10 = var4.getBts()
print("var10: \(var10)")

let var11 = var4.setPrec(prec: 0)
print ("var4: \(var4), var11: \(var11)")

let var12 = var6.joinBts(reg: var2)
print ("var12: \(var12)")

let var13 = TwoCmplt(value: 5, nbits: 8, prec: 0, signed: true)
let var14 = TwoCmplt(value: 7, nbits: 8, prec: 2, signed: true)
var tst = var14 < var13
print ("var14 < var13: \(tst)")
tst = var13 < var14
print ("var14 < var13: \(tst)")

let var15 = TwoCmplt(value: 12, nbits: 8, prec: 2, signed: true)
let var16 = TwoCmplt(value: 3, nbits: 8, prec: 0, signed: true)
tst = var15 <= var16
print ("var15 <= var16: \(tst)")

tst = var15 == var16
print ("var15 == var16: \(tst)")

tst = var15 != var16
print ("var15 != var16: \(tst)")

tst = var15 > var16
print ("var15 > var16: \(tst)")

tst = var15 >= var16
print ("var15 >= var16: \(tst)")

let var17 = TwoCmplt(value: 0x3, nbits: 4) - TwoCmplt(value: 0x7a3, nbits: 12)
let var18 = TwoCmplt(value: 0x7a3, nbits: 12) - TwoCmplt(value: 0x3, nbits: 4) 
print("var17: \(var17), var18: \(var18)")

var var19 = TwoCmplt(value: 0x3, nbits: 8)
var var20 = TwoCmplt(value: 0x4, nbits: 8)
var var21 =  var19 * var20
print ("var21: \(var21)", "var21: ", var20 * 4)


States.multiplyMode = .truncate
var19 = TwoCmplt(value: 0x48, nbits: 12, prec: 4, signed: true)
// var19 represents 4.5
var20 = TwoCmplt(value: 0x80, nbits: 8, prec: 8)
// var20 represents 0.5
let var22 =  var19 * var20
// we expect 4.5*0.5 = 2.25 = 0x24 in 8.4 representation
print ("var22: \(var22)")
States.multiplyMode = .full

var1.setPrec(prec: 4)
print ("var1: \(var1)")

let var23 = TwoCmplt(value: 0b01100, nbits: 5) | TwoCmplt(value: 0b00001, nbits: 5) 
print ("var23: \(var23)")
print ("var23: \(var23.display())")

let var24 = TwoCmplt(value: 0b01100, nbits: 5) & TwoCmplt(value: 0b01001, nbits: 5) 
print ("var24: \(var24.display())")

let var25 = TwoCmplt(value: 0b01100, nbits: 5) ^ TwoCmplt(value: 0b01001, nbits: 5) 
print ("var25: \(var25.display())")

print("1?: \(|TwoCmplt(value: 0b01001, nbits: 5)), 0?: \(|TwoCmplt(value: 0b00000, nbits: 5))")

print("0?: \(&&TwoCmplt(value: 0b11011, nbits: 5)), 1?: \(&&TwoCmplt(value: 0b11111, nbits: 5))")

print("1?: \(^TwoCmplt(value: 0b11001, nbits: 5)), 0?: \(^TwoCmplt(value: 0b11000, nbits: 5))")

print("abs(-5): \(TwoCmplt(value: -5, nbits: 4).abs()), abs(5): \(TwoCmplt(value: 5, nbits: 4).abs())")

let var26: TwoCmplt = TwoCmplt.concatSegs(
    segs: [
        .two(TwoCmplt(value: -5, nbits: 4)),
        .two(TwoCmplt(value: 5, nbits: 4))
    ]
)
print("var26: \(var26)")

print("expecting true? \(~TwoCmplt(value: 0b0101, nbits: 4) == TwoCmplt(value: 0b1010, nbits: 4))")

var var27: TwoCmplt = TwoCmplt(5, nbits: 8)
var27 += 1
print("var27: \(var27) (\(var27.toInt()))")

var27 -= 1
print("var27: \(var27) (\(var27.toInt()))")

let mixedArray: [MixedValue] = [
    .int(5),
    .two(TwoCmplt(value: 3, nbits: 8)),
    .int(12)
]
let var28: TwoCmplt = TwoCmplt.concatSegs(segs: mixedArray)
print("var28: \(var28)")

print("Hello")

import Testing
@testable import TwosCmplt

@Test
func testInit() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    let tc = TwoCmplt(value: 123, nbits: 12, signed: true)
    print("Line 14 in main.swift in TwosCmpltTestingRunner")
    #expect(tc.value == 123)
    #expect(tc.signed == true)
    #expect(tc.prec == 0)
    #expect(tc.nbits == 12) 
}
