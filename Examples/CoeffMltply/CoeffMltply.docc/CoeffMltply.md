# CoeffMltply Examples

@Metadata {
    @TechnologyRoot
}

Examples of using the TwoCmplt structs in simulating two's complement systems

## Topics

### Fixed-Coefficient Multipler

A fixed-point multiplier based on using 16-to-1 word multiplexors

### Filters

A number of different filters used as examples of using
the TwoCmplt library for simulating filters. Currently, two
different third-order filters are described. Both filters are low-pass
and can have their -3dB frequencies changed over a wide range while
prserving the filter shape. One filter has poles only and the other
has a finite transmission zero. The filter examples are first given
as "hard-wired" and secondly where the structures and coefficients
are read from a yaml file. When they are simulated with an impulse
response, their outputs are placed in ../tools which
contains a Python file that will plot the FFT of the impulse response.

## See Also

- [Reference Guide](ReferenceGuide.md)
