# Direct Digital Frequency Synthesizers
A *Direct-Digital-Frequency-Synthesizer* is an integrated circuit digital block that realizes sine and cosine values using
fixed-point arithmetic. This block is used in systems such as digital communication systems, phased-array receivers, and chirp-based radars.

## DDFS Approaches

There are many different architectures used to implement DDFS sytems; the early popular approach was to use ROM lookup tables. One of the first important seminal descriptions of an integrated realization is: 
[Sunderland: DDFS](https://ieeexplore.ieee.org/document/1052173). This realization uses two ROM lookup tables: a 256x11 ROM, and a 256x4 ROM. The generated sine wave had a spurious free sprectral purity of -65dBc; the output was real, as opposed to complex quadrature. Another example of an integrated ROM-based DDFS is found in [Nicholas: -90dBc](https://ieeexplore.ieee.org/document/104190) which improved performance to -90dBc using very clever optimization techniques. A high level block diagram of a DDFS is shown:

![DDFS](DDFS_Cordic1.png)

An alternative approach to realizing DDFS's is based on CORDIC transforms [Volder: Cordic](https://ieeexplore.ieee.org/document/5222693?arnumber=5222693). This approach seems to be the most popular currently as it doesn't require a relatively area hungry ROM (it's actually the ROM decoders that take the majority of the space, not the storage locations). The CORDIC approach to realizing DDFS's is based on using a number or "rotations" starting from a fixed location and terminating at the desired rotation phase. The main idea is when applying the rotations, the multiplications are constrained to be powers of two only which are implemented using shift rights, as opposed to area-hungry multipliers. Reported approaches include: the classical approach that constrains tan(phi) to be powers of two; and an alternative approach that constrains the phase shifts themselves to be powers of two [Madisetti: Cordic DDFS](https://ieeexplore.ieee.org/document/777100). The Cordic approaches typically achieve -100dBc spurious free outputs and normally generate both cosine and quadrature sine outputs.

We will only superficially describe the how to implement DDFS's using the Cordic approach, as there are many excellent references in the literature that give many more details than we can give here-in without requiring way too much space. For any that are very interested in this subject, we will give a few references. Some easy to read references are by Steve Arar [DDFS: Arar](https://www.allaboutcircuits.com/technical-articles/an-introduction-to-the-cordic-algorithm/) and details of a verilog implementation by Gisselquist Techology, LLC [DDFS: Gisselquist](https://zipcpu.com/dsp/2017/08/30/cordic.html). Analog Devices uses the CORDIC approach to realize their very popular DDFS's [DDFS: ADI](https://archive.org/details/JL10239) with an example data sheet at [DDFS: ADI 9914s](https://www.mouser.ca/datasheet/2/609/ad9914s-2955786.pdf). A reference the author has high respect for is by Jouko Vankka [DDFS: Vankka](https://www.researchgate.net/publication/27515907_Direct_Digital_Synthesizers_Theory_Design_and_Applications).

Two Cordic examples are simulated using the TwoCmplt library: the first example is based on the classic approach; the second example is based on a hybrid architecture that uses a 16:1 lookup-table similar to that used by Madisetti, but then uses the classic rotations; this hybrid approach eliminates the fixed multiplier used by Madisetti. The first example uses 16 *buterflys*, whereas the second example uses the looup-table and 13 *butterflys*. Both examples have better than -100dBc spurious free spectral purity (we have included a Python file in the tools directory at the top level for checking spectral purity using FFT's; see the README file for running the script).

A plot of the output of example Cordic1 is shown.

![Cordic1](Cordic1_33)

A plot of the output of example Cordic2 is shown.

![Cordic2](Cordic2_33)

In both cases, the period is chosen to be 33 delays. The spectral density of Cordic2 is about 10dB better than the spectral purity of Cordic1 (for our particular designs).

The examples presented are intended to accurately document the details of the algorithms; this is felt to be one of the benefits of first simulating at a high level but bit accurate.

The aim of these DDFS examples is not to present the *best* solution for a DDFS; albeit they are both reaonable architectures. Rather, it is intended to show that when realizing a relatively complicated digital signal processing system, the TwoCmplt library is useful in getting the *details* correct. Indeed, in many digital systems: *The Devil is in the Details*. In the recommended approach, the system design is done at a high-level, but bit accurate so the degradation due to the finite accuracy can be properly assessed, before committing to the expense of an integrated realization. Also, when an actual integrated realization is being developed, the outputs of the verilog design can be matched to the outputs of the TwoCmplt based design during the verilog debug phase expediating the verilog debug. The spectral purity of the architectures described is shown to be approximately -100dBc; which is adequate for most applications (we also have a ROM-based solution with -120dBc spectral purity, but we are hoping to submit it to a conference and can't include it until after the conference presentation (or possibly submission rejection).

We might also mention that often we first develop a high-level simulation using Python and not using TwoCmplt objects (although we do have them available). We have found Python easier to debug because of its interactive nature, and how easy it is to call functions at debug breakpoints. Once we have a Python solution, then we can use this to enable getting a Swift solution debugged. For simpler examples, we just implement directly in Swift without the Python intermediary. (We also have some simulations in Julia, which we also like, but this is on hold for now until the Swift project is further along.)
