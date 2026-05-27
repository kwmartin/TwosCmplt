### Waveform Input-Signal Editor

Waveform Input-Signal Editor is a Qt application intended to help specify input signals
to be used in digital test benches. It is intended to be useful for simple testbenches
and as a quick starting point for non-simple testbenches.

It's output is a YAML file that can be read by a program that automates making testbenches.
An example of such a program suitable for making verilog testbenches is included in the same
directory as this application.

Both programs are written in Python and should work with Python 3.12 or later. A
requirements.txt file is also included with this application that can be used with uv to
make a virtual environment with the dependent modules, so installation should be easy. Making
a simple shell script to call these programs helps automate the complete process.

The assumption is that most of a user's testbenches will use the same or similar clock waveforms
and possibly INIT inputs, but that other inputs will change from testbench to testbench. So, clock
input signals are specified with a configuration file. The other input signals are then specified
using the graphical editor. Since the output files are in YAML format, they are readable and easily
edited using a text editor. After editing with a text editor, they can then be re-read by the
waveform editor, and then used as a starting point for creating other new testbenches.

Currently, this waveform editor only works with single-bit input signals. Multiple-bit input signals
need to be added to the output YAML file using an editor. If this application becomes popular, it might
be extended at a later date.

### License

This project is licensed under the MIT License (the "License").  
You may obtain a copy of the License at: <https://opensource.org/licenses/MIT>.

### Calling Signal-Editor

It is recommended to first make a directory to clone the application into.
After cloning the application, the next step is to create a virtual environment
using uv. Run uv in the same dirctory that waveform_edit.py exists in.

### Specifying Clock Signals

The clock signals can be specified using a simple YAML format so that each edge does
not have to be individually specified. Many logic blocks assume a simple single clock signal,
so they will all have the same clock specification; for this reason, the clock signal can be
specified in a start-up configuration file, and then it never needs to be considered afterword.
An example specification of a clock signal might be:

```YAML
Clock:
  - clkNm: CLK
    initVal: 0
    per: PER
    delay: 0
```

- **clkNm**: The name of the signal; it's case sensitive.
- **initVaL**: Either a 0 or a 1. This is the clock value for the first 50% of each period.
- **per**: The period of the clock. We recommend using the constant *PER*, which is specified as 1000.
- **delay**: The clock is delayed by the specified value. For example, 2\*PER.

### Specifying PER and FinishTime

It is recommended to specify times in terms or *PER* units. *PER* is a constant that specifies the time units
of each period. This allows testbenches to be specified in a technology-independent manner. In addition,
the graphical waveform editor has a built-in snap so all changes must be at times of 0.1\*PER. This tool is
primarily intended for generating short-running testbenches to be used in test setups, not long-running
detailed testbenches. The latter would normally be created manually as they are only used when a significant
time commitment is invested. The former might be used, for example, to calibrating digital functional
simulations to match *Spice* level simulations. Suitable definitions for *PER* and *FinishTime* can be included
in the configuration file using the following YAML code.

```YAML
Constants:
  -   - PER
      - 1000
FinishTime: 32*PER
```

This specifies that PER is a constant: PER=1000. It also specifies that the simulation end after 32 periods.

### Edditing Waveforms

The aim of the waveform editor application is to make editing input signals quick and easy, using as few keystrokes
as possible. Therefore, the interface primarily uses the mouse and a couple of keys. They
are intended to be memorized; since there are only a few of them, this is not difficult

When the graphical editor starts, the *CLK* waveforms specified in the configuration file are displayed. It addition,
a single *INIT* waveform is displayed that starts at 1, stays there for one period, and then goes to 0, which it stays at from then on. For most logic systems, this is appropriate. Additional input signals are added using the *Add* item from the *Waves*
menu, or the key shortcut **^a**. It is recommended to generally use the key shortcut. After a waveform is added, then its logic changes are edited using the mouse and a couple of keys. When it is desired to delete a waveform, the waveform is first selected by clicking it, which highlights a box around the waveform. It is then deleted using *Delete* from the *Waves* menu or pressing **^d** and clicking the waveform without selecting it. Deleting waveforms is not often required.

Once a non-clock waveform has been added, it is edited by adding or deleting change edges. The waveform value alternates at each edge. There are two alternative ways an edge can be added. One method is to simply hold the `<Shift>` key down and clicking where ever the edge is desired. Alternatively, the **a** key can be held down, and simply click where the edge is to be added. Preselecting the waveform is not necessary. To delete a change edge, hold `<Cntl>` down and click on the edge. Alternatively, and equivalently, hold the key **d** down and click on the edge.

### Zooming and Panning

The display window shows times of 0 to 10\*PER at startup, or whenever `<CNTL>f` is pushed. A waveform can be edited by first panning to the desired location. Panning is achieved by simply clicking and dragging the waveform horizontally. Once the waveform has been panned to the desired location, the mouse can be hovered over it, and the waveform zoomed in by rotating the mouse wheel. The position under the cursor will remain visible. It should be noted that edges are constrained to a fixed snap value of 0.1\*PER. It is considered a design error if greater resolution is deemed necessary.

### Saving and Opening

The output YAML files are always saved in the same location relative to the directory the application is saved in. This location is ```.../Resources/SimSpcs``` and is hard-wired into the code. However, the specification is very close to the beginning of the file, and since Python is interpreted, it is easily changed by the user (one of the nice features of Python).
The directory ```.../Resources/SimSpcs``` needs to exist before saving the output.

It is also possible to open a previously saved YAML and use it as the starting point for generating simulation input signals. The YAML is loaded, and then the TimeSpcs values are separated into individual waveforms and displayed. These can be edited and then re-saved into a new set of inputs to generate a slightly different testbench. When running many different testbenches, it is often the case that only a single input signal changes; this case makes generating many testbenches efficient.

### Displaying VCD Signals

Since the YAML *TimeSpcs* format is very simple, it is possible to read *Value-Change-Dump* files, convert them to equivalent YAML files, and use the display editor to view them. Indeed, Python has a module for working with *VCD* files making this easy. We haven't done this yet, but we will add this capability soon.
