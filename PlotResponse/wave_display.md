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

The selector window (`wave_display.py`) lets you navigate the circuit hierarchy, choose which nodes to display, and control the simulation.

#### Circuit Hierarchy Tree (left pane)

Clicking a node in the tree selects that sub-circuit and populates the right pane with its node names.

#### Node Checkboxes (right pane)

Each checkbox corresponds to a node in the currently selected sub-circuit. Check the nodes you want to add to the output waveform display. **Select All** and **Clear** buttons operate on all checkboxes in the current pane.

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

Editing operations (same as the standalone waveform editor):

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

Waveforms can be **selected** by clicking their labels and **reordered** using the Wave menu or keyboard shortcuts. The display order is **preserved across re-simulations** — moving a waveform up or down is persistent until you close the window.

Bus signals (nbits > 1) are displayed in hexadecimal.

#### Buttons

| Button | Action |
|---|---|
| **Simulate** | Same as the Simulate button in the selector window. |
| **Save Inputs** | Same as the Save button in the selector window — writes edited inputs and node selection to the spec file. |

#### File Menu

| Item | Shortcut | Action |
|---|---|---|
| Close | Ctrl+W | Close the Waveform Display window. The window state (wave order, editor contents) is preserved — re-simulating or clicking Display reopens it with the same layout and updated values. |

#### Wave Menu

| Item | Shortcut | Action |
|---|---|---|
| Move Up | Ctrl+Up | Move the selected output waveform(s) up one position. |
| Move Down | Ctrl+Down | Move the selected output waveform(s) down one position. |
| Go To… | Ctrl+G | Open a dialog to center both panes at a specified period number. |

#### Zoom Menu

| Item | Shortcut | Action |
|---|---|---|
| Full | Ctrl+F | Zoom both panes to show periods 0–10. |
| Pan to Start | Ctrl+0 or Ctrl+B | Scroll both panes back to time 0. |

#### Help Menu

| Item | Action |
|---|---|
| Help | Open this documentation in a help viewer window. |
| About | Show version and description information. |

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
5. **Select more nodes**: In the selector window, navigate the tree, check additional nodes, and click **Add**. New waveforms are appended to the bottom of the output pane.
6. **Reorder**: Select a waveform label and use Ctrl+Up / Ctrl+Down to move it. The order persists through subsequent simulations.
7. **Navigate time**: Use Ctrl+G to jump to a specific period, Ctrl+F to zoom full, or Ctrl+0 / Ctrl+B to pan to time 0. Pan with click-and-drag; zoom with Ctrl+scroll.
8. **Save**: Click **Save** or **Save Inputs** to write the current input waveforms and node selection permanently to the spec file.

---

### License

This project is licensed under the MIT License.  
You may obtain a copy of the License at: <https://opensource.org/licenses/MIT>.
