# Introduction

A library to enable Swift when doing simulations of two's complement signal-processing blocks.

## Topics

- <doc:TwoComplement>
- <doc:CoeffMlt>

## Summary

A TwoCmplt struct contains the value (called value, an Int) of the two's complement variable, and
properties defining the variable. These properties describe the number of bits
used for the variable (nbits, an Int), whether the variable is considered to be signed
or unsigned (signed, a Bool), and the precision if it's not zero (prec, an Int). The precision
determines how the value should be scaled when it is combined with other two's complement
integers similar to how Matlab represents two's complement variables using it's "fi" objects.

