** TwosCmplt Library: Some Parts are Usable

This started as a port of my personal Python Library for doing TwosCmplt operations to Swift to see
if Swift was a good language; might have been a real mistake. Some good, a lot bad. Still, once I got
started I didn't want to stop until I had something usable. The Good: Swift has very good operator over-loading and these work well for doing TwosCmplt operations. The library is very good for doing very low
level hand-crafted simulations. Many examples can be found in Examples, some documented, some not yet documented.

Look at <project_dir>/scripts

The bad: Swift is obtuse, non-intuitive, and terrible for decoding yaml representing somewhat arbitrary JSON. It's not really arbitrary, but since it is originally derived from Verilog, and Verilog includes the kitchen-sink, it's effectively arbitrary.

I started on an example of doing a simple general purpose simulator, and this was a real mistake.
Irrespective, I just got a somewhat real example (one of my quadrature DDFS's simulating in the simulator and it matches my iVerilog simulations). The simulator now covers a reasonable sub-set of verilog but it is far from complete (and will probably never be complete - just too much for one person). It is not intended as a replacement for the excellent iVerilog, I wanted to have something I can cusotmize for helping in debug and design. In particular I eventually want it to be a tool for checking critical paths, electro-migration, power estimation, speed estimation, etc.

If you find something interesting, let me know and maybe I can find some time to work on. it

This was also my first project where I heavily used AI, starting with Perplexity, and now mostly Claude. I can't afford Copilot, and haven't gotten around to Gemini yet, I'm allergic to Open AI. If you want to try and get something to work, try it out, and then ask claude to help getting it to work. I could never have done the yaml decoding (and still can't properly do it) without their help. I use Perplexity almost 100% of the time to replace Google Search

Again, let me know what you find interesting. Once I get the simulator (and viewer in PlotResponse/wave_display.py) working properly, I plan on looking into some ideas on minimizing power by switching to a low supply dynamically for blocks that don't need speed - just some ideas).

As an aside, where I found AI truly excels is in making GUIs. I personally prefer PySide6 as I have previous experience with it, and since it's Python based should be easy to port especially if you use AI to help do the port. The Python uses a uv based Virtual Environment.
