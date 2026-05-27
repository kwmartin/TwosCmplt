# FilterIntro
When realizing digital filters in hardware, and when high-speed operation is important, a popular choice is to use two's complement arithmetic for the signal-processing operations. Often, the initial design debugging is done using a high-level simulation but with bit accurate operations.
The TwoCmplt Library is intended to help simulate high-level, bit-accurate
filters with minimal effort.

## Approach

The signal-flow-graph of a simple first-order filter is shown directly below

![First-Order Filter](Filter_3A.png)

In this example, the muliplier is realized by a new approach for impementing a
multiplication where the multiplication is by a fixed coefficient that either is
a constant or changes only slowly. The multiplication is realized using the struct
```TwosCmplt/CoeffMlt```. The example of using this struct is found in the swift executable file
Filter3A.swift found in Examples/Filter3A/ in the main project directory. Note the other
examples are also all under Examples from the main project directory. Additional documentation
on the Examples can be found in ExamplesDoc/ExamplesDoc.docc. Some of the examples write their
impulse response into the tools directory. The FFT magnitude of the impulse response can
be displayed (and optionally saved to a png or pdf file) using python3 anal_functs <example_name.dat>

Another illustrative example is:

![Third-Order Elliptic Filter](Filter_3C.png)

This filter can be realized without using multipliers and can have its -3dB frequency changed over
a wide range while it's shape remains constant. It and some similar architectures where used
in early ADSL systems.

The magnitude transfer function of this filter is easily found by simulating
the filter with an impulse input signal, and then doing an FFT on the output impulse response.

![Impulse Response of Third-Order](ThrdOrdr_with_Zero.png)

The slight anomoly at dc is interesting; it is not due to numerical inaccuracies. It is *real* and caused by the
fact that the impulse response does not settle to zero as might be expected. When the internal states get small, the ouputs
of the multipliers are zero even when the internal states are not exactly zero due to finite arithmetic truncation. Unless the design is modified to correct for this, an actual realization will have this behavior.

## Topics

- <doc:CoeffMlt>

