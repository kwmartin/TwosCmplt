# CoeffMlt

## Introduction

Many signal processing blocks have multiplications involving fixed coefficients.
The fixed coefficients may never change or change or slowly. For this case, it is advantageous
to realize the multiplications using a simpler and faster multiplier compared to a general-purpose
multiplier. This example shows one possible approach developed by the author.

This example uses a 16-bit signed signal path and 20-bit registers and adders
The coefficients are assumed to be unsigned positive values between 0 and
(1<<15) - 1. Each coefficient represents a fraction; the maximum of the coefficients is
((1<<15)-1) / (1<<15). Sixteen 20-bit registers need to be pre-loaded with k \* coeff, k = 0,..,15
At each multiplication, if the signal is negative, it is converted to a positive value, and then
after an unsigned multiplication, it is converted back to a negative value.
In the multiplication operation, 4 different values are added together to get the final result.
In a hardware implementation, the first two additions would occur in parallel, followed by adding
their outputs, so two cascaded levels of addition are required. In most hardware implementations,
carry-save adders would be used; this approach has not yet been incorporated into the example.

The values being added are determined by the unsigned signal nibbles, with each nibble being 4 bits.
The 4-bit nibbles select one of the coefficient registers shifted right by rshift, for rshift = 0,4,8,12
depending on the nibble, going from the most significant nibble to the least significant nibble.
The rshift's are implemented using wiring and don't require additional hardware.
The selection is done using 20-bit 16 to 1 multiplexors implemented using three levels of
2 to 1 switched inverters.
After the summation, 8 is added to the sum, to implement rounding, and then the final output is
the sum shifted right by 4 bits, and possible negated if the signal input was originally negative.

This example includes a relatively simple block to show how the coefficient registers could be slowly updated, once
every 16 signal values, for applications were the coefficients might be slowly adapting. 

### Topics

- <doc:Filters>
	