import SharedTypes


import Foundation

public func InitCoeffArrays(K: TwoCmplt) {
    Glbl.a3_ = Array(repeating: TwoCmplt(value: 0, nbits: 20), count: 16)
    Glbl.a2_ = Array(repeating: TwoCmplt(value: 0, nbits: 20), count: 16)
    Glbl.a1_ = Array(repeating: TwoCmplt(value: 0, nbits: 20), count: 16)
    Glbl.a0_ = Array(repeating: TwoCmplt(value: 0, nbits: 20), count: 16)

    Glbl.a3_[0] = TwoCmplt(value: 0, nbits: 20)
    Glbl.a3_[1] = K
    Glbl.a3_[2] = K<<1
    Glbl.a3_[3] = (K<<1) + K
    Glbl.a3_[4] = K<<2
    Glbl.a3_[5] = (K<<2) + K
    Glbl.a3_[6] = (K<<2) + (K<<1)
    Glbl.a3_[7] = (K<<3) - K
    Glbl.a3_[8] = K<<3
    Glbl.a3_[9] = (K<<3) + K
    Glbl.a3_[10] = (K<<3) + (K<<1)
    Glbl.a3_[11] = (K<<3) + (K<<1) + K
    Glbl.a3_[12] = (K<<3) + (K<<2)
    Glbl.a3_[13] = (K<<3) + (K<<2) + K
    Glbl.a3_[14] = (K<<4) - (K<<1)
    Glbl.a3_[15] = (K<<4) - K

    for i in 0...15 {
       Glbl.a2_[i] = Glbl.a3_[i] >> 4
    }

    for i in 0...15 {
       Glbl.a1_[i] = Glbl.a2_[i] >> 4
    }

    for i in 0...15 {
       Glbl.a0_[i] = Glbl.a1_[i] >> 4
    }
}

public func InitCoeffArray(K: TwoCmplt) {
    Glbl.arry = Array(repeating: TwoCmplt(value: 0, nbits: 20), count: 16)

    Glbl.arry[0] = TwoCmplt(value: 0, nbits: 20)
    Glbl.arry[1] = K
    Glbl.arry[2] = K<<1
    Glbl.arry[3] = (K<<1) + K
    Glbl.arry[4] = K<<2
    Glbl.arry[5] = (K<<2) + K
    Glbl.arry[6] = (K<<2) + (K<<1)
    Glbl.arry[7] = (K<<3) - K
    Glbl.arry[8] = K<<3
    Glbl.arry[9] = (K<<3) + K
    Glbl.arry[10] = (K<<3) + (K<<1)
    Glbl.arry[11] = (K<<3) + (K<<1) + K
    Glbl.arry[12] = (K<<3) + (K<<2)
    Glbl.arry[13] = (K<<3) + (K<<2) + K
    Glbl.arry[14] = (K<<4) - (K<<1)
    Glbl.arry[15] = (K<<4) - K
}
