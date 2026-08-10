### Waveform Input-Signal Editor

The **Waveform Input-Signal Editor** is a PySide6 application for specifying digital input signals for test benches. Since 9.4, the standalone editor is the same code used by the Swift waveform viewer: it launches `wave_display.py --edit <CircuitName>`, so all editing gestures and features are identical regardless of entry point.

It writes the same YAML `TimeSpcs` format consumed by the Swift simulator (`SimRun`) and the iVerilog testbench generator (`makeTB.py`). The file is saved under `Resources/SimSpcs/<CircuitName>.yml` (the exact path comes from `Config.yaml` `directories/specsLib`).

Both programs are written in Python and require Python 3.12 or later. A `requirements.txt` file is included; use `uv` or another virtual-environment tool to install the dependencies.

---

### Waveform Editor Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| F1 | Open this help window |
| Ctrl+O | Open a different base YAML spec file |
| Ctrl+S | Save the current input waveforms |
| Ctrl+W | Close the editor |
| Ctrl+A | Add a new input signal |
| Ctrl+D | Delete the selected input signal |
| Ctrl+Shift+D | Duplicate the selected input signal |
| Ctrl+Up | Move selected signal up one position |
| Ctrl+Down | Move selected signal down one position |
| Ctrl+Z / Ctrl+Y | Undo / Redo |
| Ctrl+F | Zoom full — reset zoom, centered at the cursor |

#### Editing waveforms

| Shortcut | Action |
|---|---|
| a (hold) + click | Add a transition edge at the clicked time |
| Ctrl + click edge | Delete the edge at the clicked position |
| d (hold) + click edge | Delete the edge at the clicked position |
| v (hold) + click segment | Open **Set Segment Value** for that segment |
| t (hold) + click waveform | Invert all values of a 1-bit waveform |
| Escape | Cancel the held **a**, **d**, **v**, or **t** action key |

#### Zoom and pan

| Shortcut | Action |
|---|---|
| Click + drag | Pan the waveform horizontally |
| Ctrl + scroll up | Zoom in around the cursor |
| Ctrl + scroll down | Zoom out around the cursor |

#### Generating patterns

| Shortcut | Action |
|---|---|
| (menu / toolbar / right-click) | Generate Counting Sequence… |
| (menu / toolbar / right-click) | Set Repeating Pattern… |

---

### Calling the Signal Editor

From the Swift/TwosCmplt tree:

```bash
python3 tools/wave_display.py --edit <CircuitName> [--config /path/to/Config.yaml] [--spec /path/to/spec.yml]
```

Legacy wrappers still work and open the same editor:

```bash
python3 ~/.xschem/verilogParse/wave_edit.py <CircuitName>
# or the "Edit Sigs" button in gen_verilog_tb.py
```

If no spec file exists, generate one first with `gen_verilog_tb.py`.

---

### Specifying Clock Signals

Clock signals are defined once per spec file. A typical clock definition:

```yaml
Clock:
  - clkNm: CLK
    initVal: 0
    per: PER
    delay: 0
```

- **clkNm**: The signal name; case-sensitive.
- **initVal**: Value for the first half of each period (`0` or `1`).
- **per**: Period, conventionally `PER`.
- **delay**: Optional clock delay, e.g. `2*PER`.

Clocks appear as read-only waveforms in the editor.

---

### Specifying PER and FinishTime

Times are expressed in `PER` units. `PER` is defined in `Constants`:

```yaml
Constants:
  - [PER, 1000]
FinishTime: 32*PER
```

The editor snaps all edges to `0.1*PER`. This resolution is intentional for short functional testbenches rather than long detailed simulations.

---

### Editing Waveforms

When the editor starts, clock signals are displayed first, followed by any input signals defined in the existing `TimeSpcs`. If no inputs exist, a default `INIT` signal is shown (high for one period, then low).

#### Adding and removing signals

| Action | Method |
|---|---|
| Add a new input signal | **Waves → Add** or **Ctrl+A** |
| Delete selected signal | **Waves → Delete** or **Ctrl+D** |
| Duplicate selected signal | **Edit → Duplicate** or **Ctrl+Shift+D** |

#### Editing transitions

| Action | Method |
|---|---|
| Add a transition edge | Hold **a** and click |
| Delete a transition edge | **Ctrl + click** the edge, or hold **d** and click the edge |
| Set multi-bit segment value | Hold **v** and click the segment |
| Invert a 1-bit waveform | Hold **t** and click the waveform |

Edges snap to `0.1*PER`.

#### Zoom and pan

| Action | Method |
|---|---|
| Pan | Click and drag |
| Zoom around cursor | **Ctrl + scroll wheel** |
| Reset zoom | **Ctrl+F** |

---

### Generating and Repeating Patterns

Use **Waves → Generate Counting Sequence…** to create a counter-style input (e.g. `0, 1, 2, …`), or **Waves → Set Repeating Pattern…** to create a tiled input signal. Both are available from the toolbar button and the right-click context menu.

#### Generate Counting Sequence

1. Choose **Start**, **Final**, **Time increment** (e.g. `1*PER`), and **Value increment**.
2. Choose **Replace** to overwrite the selected signal, or **Merge** to combine with existing transitions.
3. Values are masked to the signal's declared bit width. A 1-bit signal counting from `0` to `16` produces `0, 1, 0, 1, …`.

#### Set Repeating Pattern

1. Set **CLK periods per input period** (default `8`, range `1–256`). The x-axis updates immediately.
2. Set **Pattern delay** (default `0`, range `0–256`). This many clock periods keep the signal at its initial value before the first repeating period begins. Use it when a reset or idle interval is needed at the start of the run.
3. Edit the period with the same gestures as the main editor.
4. Click **OK** to tile the period from time `0` to `FinishTime`.

The default pattern is high for the first CLK period and low for the remaining CLK periods.

---

### Help

Press **F1** in any editor window to open this help file.

---

### Undo / Redo

The editor supports undo/redo for structural edits:

- **Ctrl+Z** / **Ctrl+Y**
- **Edit → Undo / Redo**

---

### Saving

The edited waveforms are written to the spec file with **File → Save** or **Ctrl+S**.

The output YAML uses the same `Constants / Clock / FinishTime / TimeSpcs / SaveNds` shape read by `SimRun` and `makeTB.py`.

> **Note on per-signal merge:** When saving, the editor only overwrites the signals it manages. Power rails (VDD, VSS) and signals not present in the editor are preserved in the existing spec file. Hand-edited files (without `generated: true`) are protected from wholesale overwrite (9.2).

---

### Displaying VCD Signals

The YAML `TimeSpcs` format is simple enough that VCD files can be converted to it and viewed in the editor. This capability is under development.

---

### License

This project is licensed under the MIT License (the "License").
You may obtain a copy of the License at: <https://opensource.org/licenses/MIT>.
