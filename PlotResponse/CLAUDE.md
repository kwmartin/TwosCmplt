# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Python utility scripts for analyzing and visualizing digital signal processing (DSP) output from the TwosCmplt Swift simulation project. Three distinct tools exist in this repo:

1. **`anal_functs.py`** — CLI for plotting FFT magnitude spectra and time-domain waveforms from `.dat` simulation output files.
2. **`waveform_edit.py`** — PySide6 GUI editor for creating and editing digital timing diagrams, saved as YAML spec files consumed by the Swift simulator.
3. **`write_vcd.py`** — Converts a JSON signal description to VCD (Value Change Dump) format for waveform viewers.

## Setup

```bash
# Install uv if needed (see uv docs for proper install)
uv pip install -r requirements.txt
source .venv/bin/activate
```

## Running the Tools

### FFT/spectrum analysis (`anal_functs.py`)

```bash
# Oscillator: plot spectral response of a periodic signal (period = 16 samples)
python3 anal_functs.py Osc4.dat -p 16 --lims -20 110

# Filter: plot FFT magnitude of one or more impulse responses
python3 anal_functs.py CmplxFltr5a.dat CmplxFltr5b.dat --lims -40 35

# Data comparison: plot two waveforms side-by-side (exactly 2 files)
python3 anal_functs.py -d CmplxFltr5c.dat Fltr5c.dat
```

- Without `-p`, the script treats input as an impulse response (filter mode).
- With `-p <N>`, it treats input as a periodic oscillator signal with period N.
- With `-d`, it plots raw time-domain waveforms for direct comparison.
- `--lims LOW HIGH` sets the dB y-axis range.

### Waveform editor (`waveform_edit.py`)

```bash
python3 waveform_edit.py [output_base_name]
```

Loads `<output_base_name>.yml` from `../Resources/SimSpcs/` (relative to the script). Saves back to the same location via Ctrl+S. The base YAML defines `Constants` (including `PER`), `FinishTime`, and optional `Clock` specs — only the digital signal transitions are edited interactively and written back.

### VCD writer (`write_vcd.py`)

```bash
python3 write_vcd.py
```

Reads `vcd_debug_input.json` (hardcoded), writes VCD output to the path specified in the JSON `"out"` field.

## Data File Format

`.dat` files are whitespace-delimited text:
- **1 column**: real-valued signal (e.g., real filter impulse response)
- **2 columns**: complex signal as `cos sin` pairs (e.g., complex oscillator or complex filter)

No header lines. `np.genfromtxt()` is used to read them.

## YAML Spec Format (`FADD.yml` example)

```yaml
Constants:
  - [PER, 1000]
FinishTime: 32*PER
Clock:
  - clkNm: CLK
    initVal: 0
    per: PER
    delay: 0
```

Time values in `TimeSpcs` are expressed as `N*PER` multiplier expressions. `PER` must always be defined.

## Code Architecture

- **`lib/glbls.py`** — Shared utilities imported by `waveform_edit.py`: YAML I/O (`rd_yml`/`wrt_yml` using `ruyaml` for round-trip preservation), file locking (`wrt_wth_lck`), and dynamic module import (`imprt_fl`).
- **`waveform_edit.py`** — Qt widget hierarchy: `MainWindow` → `WaveformCanvas`. The canvas owns the wave model (`WaveRow` subclasses: `ClockWaveRow`, `DigitalWaveRow`) and renders everything via `paintEvent`. `Segment` is the data unit for digital waves (start, end, value). Clock waves are rendered by sampling `value_for_time(t)` rather than stored as segments.
- **`anal_functs.py`** — Standalone script; `pyqtgraph` is imported at module level (with a subprocess-based remote process) even though `matplotlib` is the active backend. This causes import overhead but the pyqtgraph code is not currently used.
