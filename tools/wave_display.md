## Wave Display

**Wave Display** is a PySide6 application for selecting, simulating, and viewing circuit node waveforms produced by the TwosCmplt Swift simulation library. It consists of two windows: the **Selector window** (`wave_display.py`) and the **Waveform Display window** that opens when you click Display or after a simulation completes.

---

### Calling Wave Display

```
wave_display.py <CircuitName> [--config /path/to/Config.yaml]
```

`Config.yaml` defaults to `../Config.yaml` relative to the script. The relevant keys are:

| Key (under `fileNames:`) | Purpose |
|---|---|
| `simRunner` | Path to the compiled `SimRun` binary |
| Key (under `directories:`) | |
| `specsLib` | Directory containing simulation spec YAML files |
| `dumpDir` | Directory where `SimRun` writes `<Name>Map.yml` and `<Name>Chngs.yml` |

When a circuit name is given on the command line, the circuit is built and simulated automatically on startup.

---

### Selector Window

The selector window lets you navigate the circuit hierarchy, choose which nodes to display, and control the simulation.

#### Circuit Hierarchy Tree (left pane)

Clicking a node in the tree selects that sub-circuit and populates the right pane with its node names. When a circuit is first loaded, the tree opens showing the top-level circuit and its direct sub-circuits. Deeper levels are hidden until you click the expand arrow on an item.

#### Node Checkboxes (right pane)

Each checkbox corresponds to a node in the currently selected sub-circuit. Check the nodes you want to add to the output waveform display. **Select All** checks all nodes except power rails (VDD, VSS); **Clear** unchecks all checkboxes in the current pane.

#### Action Buttons

| Button | Action |
|---|---|
| **Simulate** | Run simulation using the current input waveforms from the editor (the spec file is not modified). |
| **Save** | Write the edited input waveforms and the current node selection permanently to the spec file. |
| **Display** | Open or update the Waveform Display window with the currently selected signals. |
| **Add** | Add the checked nodes to the output display without clearing existing selections. |
| **Remove** | Remove the checked nodes from the output display. |
| **Remove All** | Clear the saved selection for the currently displayed sub-circuit. |

#### File Menu

| Item | Shortcut | Action |
|---|---|---|
| Open Circuit | Ctrl+O | Browse for a circuit YAML in the circuit library directory. |
| Reload | Ctrl+R | Rebuild and re-simulate the current circuit. |
| Quit | Ctrl+Q | Exit the application. |

#### Help Menu

| Item | Action |
|---|---|
| Help | Open this documentation in a help viewer window. |
| About | Show version and description information. |

---

### Waveform Display Window

The Waveform Display window opens automatically after a simulation or when you click **Display**. It contains two panes separated by a movable divider.

#### Top Pane — Input Waveforms (editable)

The top pane shows the input signals defined in the circuit's spec file (e.g., CLK, INIT). These waveforms are **fully editable**: you can add, delete, and move transition edges. VDD and VSS power rails are never shown here because they never change.

Editing operations:

| Action | Method |
|---|---|
| Add an edge | Hold **Shift** and click, or hold the **a** key and click |
| Delete an edge | Hold **Ctrl** and click the edge, or hold the **d** key and click the edge |
| Pan horizontally | Click and drag |
| Zoom | Ctrl + scroll wheel (zooms around the cursor position) |

Edges snap to 0.1 × PER resolution.

The edited input waveforms are used when you click **Simulate** (in either window). The spec file is only modified when you click **Save** or **Save Inputs**.

#### Bottom Pane — Output Waveforms (read-only)

The bottom pane shows all simulation output signals: Clock signals, TimeSpcs inputs, SaveNds signals, and any nodes selected in the hierarchy tree. The signals appear in the order specified by the spec file, with checkbox-selected nodes appended.

**Selecting waveforms**: Click a waveform label to select it (this also sets the range-select anchor). Hold **Shift** and click a second label to select that waveform and all waveforms between it and the anchor — Shift+clicking again extends or contracts the selection from the same anchor. Press **Esc** or click an empty area of the waveform pane to deselect all.

**Reordering**: With one or more waveforms selected, use **Ctrl+Up** / **Ctrl+Down** (or the Wave menu) to move the entire selection up or down one position at a time. The display order is **preserved across re-simulations**.

**Removing from display**: Press **Ctrl+D** (or use Wave → Delete) to remove all selected waveforms from the output display. If multiple waveforms are selected, all are deleted at once. When waveforms are deleted, the corresponding node checkboxes in the Selector window are automatically unchecked. This does not modify the spec file.

Bus signals (nbits > 1) are displayed in the format set by right-clicking the signal (Hex, Decimal, Signed Decimal, or Binary). Right-clicking a 1-bit signal has no effect.

#### Status Bar (bottom row)

A position readout appears to the right of the **Simulate** and **Save Inputs** buttons. It shows the current mouse position in period units while the cursor is inside either waveform pane:

```
Pos: 5.23
```

When a marker is dropped, the readout expands to show the marker position, the live cursor position, and the delta between them:

```
Marker: 3.00    Pos: 5.23    Δ: +2.23 per
```

#### Markers

A **marker** is a fixed vertical reference line (solid red) that can be dropped anywhere on the output waveform pane. Use it to measure time intervals between two points.

| Action | How |
|---|---|
| Drop / move marker | **Ctrl + Right-click** at the desired position (also available from the **Markers** menu) |
| Drag marker to new position | **Ctrl + Left-drag** on or near the marker line (within ~8 px) |
| Drop marker from menu | **Markers → Drop Marker** — drops at the current cursor position |

The live cursor (dashed yellow) continues to move as you move the mouse. The delta in the status bar always reads **cursor − marker**.

#### Buttons

| Button | Action |
|---|---|
| **Simulate** | Same as the Simulate button in the selector window. |
| **Save Inputs** | Same as the Save button in the selector window — writes edited inputs and node selection to the spec file. |

#### File Menu

| Item | Shortcut | Action |
|---|---|---|
| Save Inputs | Ctrl+S | Write edited input waveforms to the spec file. |
| Goto Select | Ctrl+H | Bring the Selector window to the front. |
| Close | Ctrl+W | Close the Waveform Display window. |

#### Wave Menu

| Item | Shortcut | Action |
|---|---|---|
| Move Up | Ctrl+Up | Move the selected output waveform(s) up one position. |
| Move Down | Ctrl+Down | Move the selected output waveform(s) down one position. |
| Delete | Ctrl+D | Remove all selected waveform(s) from the display and uncheck them in the Selector. |
| Go To… | Ctrl+G | Open a dialog to center both panes at a specified period number. |

#### Zoom Menu

| Item | Shortcut | Action |
|---|---|---|
| Full | Ctrl+F | Restore the initial zoom level, centered at the current cursor position. |
| Pan to Start | Ctrl+0 or Ctrl+B | Scroll both panes back to time 0 without changing zoom. |

#### Markers Menu

| Item | Action |
|---|---|
| Drop Marker | Drop a marker at the current cursor position (same as Ctrl+Right-click). |

#### Help Menu

| Item | Action |
|---|---|
| Help | Open this documentation in a help viewer window. |
| About | Show version and description information. |

---

### Keyboard Shortcuts

#### Selector Window

| Shortcut | Action |
|---|---|
| Ctrl+O | Open Circuit — browse for a circuit YAML file |
| Ctrl+R | Reload — rebuild and re-simulate the current circuit |
| Ctrl+Q | Quit the application |

#### Waveform Display Window — Menus

| Shortcut | Action |
|---|---|
| Ctrl+S | Save Inputs — write edited input waveforms to the spec file |
| Ctrl+H | Goto Select — bring the Selector window to the front |
| Ctrl+W | Close the Waveform Display window |
| Ctrl+Up | Move selected waveform(s) up one position |
| Ctrl+Down | Move selected waveform(s) down one position |
| Ctrl+G | Go To… — center both panes at a specified period number |
| Ctrl+F | Zoom Full — restore initial zoom, centered at the cursor |
| Ctrl+0 | Pan to Start — scroll to time 0 |
| Ctrl+B | Pan to Start (alternate binding) |

#### Waveform Display Window — Mouse & Navigation (both panes)

| Shortcut | Action |
|---|---|
| Click + drag | Pan the waveform horizontally |
| Ctrl + scroll up | Zoom in around the cursor |
| Ctrl + scroll down | Zoom out around the cursor |
| Scroll up / down | Scroll vertically through waveforms |

#### Waveform Display Window — Output Pane (bottom)

| Shortcut | Action |
|---|---|
| Click label | Select a waveform and set the range anchor (clears existing selection) |
| Shift + click label | Select the range from the anchor to the clicked label (inclusive) |
| Esc | Deselect all waveforms |
| Ctrl+D | Delete selected waveform(s) from the display and uncheck them in the Selector |
| Ctrl + Right-click | Drop a marker at the clicked position |
| Ctrl + Left-drag (near marker) | Drag the marker to a new position |
| Right-click (bus signal) | Set display format: Hex, Decimal, Signed Decimal, or Binary |

#### Waveform Display Window — Input Pane (top, editable)

| Shortcut | Action |
|---|---|
| Shift + click | Add a transition edge at the clicked time |
| a (hold) + click | Add a transition edge at the clicked time |
| Ctrl + click edge | Delete the edge at the clicked position |
| d (hold) + click edge | Delete the edge at the clicked position |
| Escape | Cancel the held **a** or **d** action key |

---

### Spec File Format

Simulation specs are YAML files in `specsLib` (e.g., `TB_DVDR4.yml`):

```yaml
Module: DVDR4
Constants:
    PER: 1000
FinishTime: 40*PER
Clock:
  - clkNm: CLK
    per: PER
SaveNds:
  - name: Top.OUT
    format: u
  - name: Top.INIT
    format: u
TimeSpcs:
  - tm: 0
    vls:
      - [INIT, 1]
  - tm: PER
    vls:
      - [INIT, 0]
```

- **Constants**: Defines `PER` (the tick count per simulation period). Accepts either mapping (`PER: 1000`) or list (`[[PER, 1000]]`) format.
- **FinishTime**: Total simulation duration expressed as `N*PER`.
- **Clock**: One or more clock signals. `initVal` (0 or 1) sets the value for the first half-period; defaults to 0 if omitted.
- **SaveNds**: Nodes to record. The format field is `u` (unsigned) or `h` (hex).
- **TimeSpcs**: Input stimulus. Each entry has a time `tm` (as integer or `N*PER` expression) and a list of `[signal, value]` pairs. VDD and VSS entries are accepted but never displayed.

---

### Typical Workflow

1. **Start**: `wave_display.py TB_DVDR4` — builds, simulates, and loads the circuit.
2. **Display**: Click **Display** to open the Waveform Display window. Input waveforms (CLK, INIT, etc.) appear in the top pane; simulation outputs appear in the bottom pane.
3. **Edit inputs**: Modify transition edges in the top pane.
4. **Re-simulate**: Click **Simulate** (in either window). The spec file is unchanged; the edited inputs are used for this run only. Output waveforms update in place, retaining any reordering.
5. **Select more nodes**: In the selector window, navigate the tree, check additional nodes (use **Select All** to check everything except power rails), and click **Add**. New waveforms are appended to the bottom of the output pane.
6. **Reorder**: Click a waveform label to select it; Shift+click to add more. Use Ctrl+Up / Ctrl+Down to move the selection. The order persists through subsequent simulations.
7. **Navigate time**: Use Ctrl+G to jump to a specific period, Ctrl+F to zoom to the initial level centered at the cursor, or Ctrl+0 / Ctrl+B to pan to time 0. Pan with click-and-drag; zoom with Ctrl+scroll.
8. **Measure timing**: Ctrl+Right-click to drop a marker; the status bar shows the delta from the marker to the live cursor as you move the mouse.
9. **Save**: Click **Save** or **Save Inputs** to write the current input waveforms and node selection permanently to the spec file.

---

### License

This project is licensed under the Apache License 2.0.  
See `LICENSE.txt` in the repository root, or: <https://www.apache.org/licenses/LICENSE-2.0>.
