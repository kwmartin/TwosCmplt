# Digital Simulation Design Flow

This document describes the current end-to-end flow for running digital (Verilog/Swift) simulations starting from `ngui`. It covers the two overlapping interfaces — the Main Simulation Interface (`ngui` / `run_sim_ui.py`) and the Swift/TwosCmplt digital-simulation toolchain — and identifies the seams where the flow is currently awkward or duplicated.

> **Scope**: This write-up captures the state of the code as of 2026-08-02. It is intended as a baseline for refactoring and integration decisions, not as a user manual.

---

## 1. The two primary interfaces

There are two independently-grown interfaces that converge on the same digital simulation:

| Interface | Entry point | Primary purpose | Authoritative config |
|---|---|---|---|
| **Main Simulation Interface (analog-first)** | `ngui <symbol>` → `run_sim_ui.py` | Characterize xschem cells with NgSpice; also has a **Digital** mode that can generate Verilog netlists and dispatch to iVerilog or Swift. | `run_sim_ui.cfg` (analog defaults + selected digital library), `parse_verilog.cfg` (simulator/viewer selection) |
| **Swift digital-simulation toolchain** | `swift run SimRun <module> Config.yaml [--spec <path>]` or `wave_display.py <module>` | Build a circuit from YAML, evaluate it in topological order, and produce VCD-like waveform dumps. | `Config.yaml` / `swift_iverilog_config.yaml` |

Both interfaces read and write the same intermediate artifacts (CircuitLib YAML, SimSpcs YAML, DumpDir Map/Chngs), but they each have their own idea of which specs file is authoritative.

---

## 2. Starting point: `ngui TST_DES_3X2`

`ngui` is a thin shell script that launches `run_sim_ui.py` from the NgSpice testbench infrastructure:

```bash
ngui TST_DES_3X2
# → /home/Dropbox/programming/Python/lib/venv312/bin/python3 \
#    /home/martin/IC_Design/Testbenches/NgSpice/SimLib/run_sim_ui.py TST_DES_3X2
```

`run_sim_ui.py` opens in **Analog** mode by default. To do a digital simulation the user must either switch the **Mode** combo to `Digital` or use the **Hierarchy** combo set to `Verilog`.

---

## 3. Digital-mode flow inside `run_sim_ui.py`

### 3.1 Generate the Verilog netlist

When **Run Simulation** is pressed in Digital mode, `_on_run_dispatch()` calls `_on_run_verilog()`, which:

1. Finds the xschem `.sym` and `.sch` files via `XSCHEM_LIBRARY_PATH`.
2. Runs `xschem` to produce a Verilog netlist under the per-symbol project directory, e.g.:
   ```
   /home/martin/IC_Design/Testbenches/NgSpice/TST_DES_3X2/verilog/TST_DES_3X2.v
   ```
3. Parses the SPICE netlist (produced earlier for the analog path) to get model parameters.

### 3.2 Run the Verilog → CircuitLib pipeline

`_on_run_verilog()` then runs the `verilogParse` pipeline as a subprocess so the generated Verilog is converted into the YAML that Swift consumes:

```
parse_verilog.py  TST_DES_3X2.v   →  TST_DES_3X2.ast
parse_ast.py      TST_DES_3X2.ast →  TST_DES_3X2.mod
parse_mod.py      TST_DES_3X2.mod →  CircuitLib/TST_DES_3X2.yml  +  unl_modules/TST_DES_3X2.unl
```

This is the same `run_pipeline()` used by `gen_verilog_tb.py`. The pipeline also updates `CircuitLib/pipeline_deps.yml` with mtimes and SHA-256 hashes.

### 3.3 First-time setup: review dialog

If no authoritative specs file exists under `Resources/SimSpcs/<module>.yml` (Swift)
or `Resources/IVerilogSpcs/<module>.yml` (iVerilog), `_on_run_verilog()` launches
`gen_verilog_tb.py` in a subprocess, which:

1. Runs the pipeline again (redundant with the pipeline run above, but separate subprocess).
2. Loads the `.unl` file, classifies ports (clocks / resets / data / outputs / power), and opens a PySide6 **Run Generated Settings** dialog.
3. On **Generate** or dialog close, writes the specs file that matches the selected
   simulator:
   - `simulator: Swift`  → `Resources/SimSpcs/<module>.yml`
   - `simulator: iVerilog` → `Resources/IVerilogSpcs/<module>.yml`
   - `~/.xschem/simulations/<module>_tb.v` — the generated iVerilog testbench (both modes).

The review dialog also calls `sync_all_specs()` to propagate shared sections
(`Constants`, `Clock`, `FinishTime`, `TimeSpcs`, `SaveNds`) to the *other* specs file
using per-signal merge, so manual edits on signals not touched by the generator
survive.

If a legacy `~/.xschem/modules/<module>.yml` exists and the new authoritative file
does not, `run_sim_ui.py` copies it to the new location before checking for the
review dialog, so existing configurations keep working without forcing re-entry.

### 3.4 Subsequent runs: dispatch by simulator

On later runs, `_on_run_verilog()` skips the review dialog and uses the persisted
authoritative specs. It looks at `parse_verilog.cfg`:

```yaml
interactive: false
simulator: Swift
viewer: Native
```

- **simulator = iVerilog**: runs `makeTB.py <module>`, which reads
  `Resources/IVerilogSpcs/<module>.yml` and produces a Verilog testbench + VCD.
- **simulator = Swift**: runs `SimRun <module> Config.yaml --spec
  Resources/SimSpcs/<module>.yml`, which reads the Swift-native specs file.

The viewer selection (`GtkWave`, `Swift`, `Native`) determines what happens after the simulation finishes.

---

## 4. The Swift side of the flow

### 4.1 Circuit loading

`SimRun` calls `makeCircDef(circuitName)`:

1. Loads `Resources/CircuitLib/<module>.yml`.
2. If the YAML `kind` is `verilog`, decodes it into a `CircDef` and recursively loads all sub-module `CircDef`s referenced in `behav_blcks` (`async`, `sync`, `instance`, `subcirc`).
3. Registers every loaded `CircDef` in `Glbls`.
4. Calls `circDef.toCircuit()` to build a `Circuit` with nodes, ports, instances, gates, and a Kahn-sorted `evalOrder`.

For `TST_DES_3X2` this currently loads `DG_DES_3X2`, `DG_INV2_1X1`, and the passive stub `CAP`.

### 4.2 Simulation specs

`SimRun` loads specs from the path passed to `--spec`, or from `Resources/SimSpcs/<module>.yml` if no `--spec` is given. The spec YAML contains:

- `Constants` (e.g. `PER: 1000`)
- `Clock` — periodic clock definitions
- `FinishTime` — e.g. `64*PER`
- `TimeSpcs` — input stimulus as time/value pairs
- `SaveNds` — nodes to capture

Before simulating, `cleanSpecFile()` removes any `TimeSpcs` entries whose node names are not present in the circuit.

### 4.3 Running and viewing

`simCircuit()` drives the simulation:

1. Applies `TimeSpcs` to input nodes.
2. Runs clocks.
3. Evaluates components in `evalOrder` each timestep.
4. Writes `Resources/DumpDir/<module>Map.yml` and `<module>Chngs.yml`.

`wave_display.py` then reads those dumps and the same spec YAML to display waveforms.

---

## 5. Waveform / stimulus editing alternatives

There are currently **three** different waveform/spec editors with overlapping responsibilities:

| Tool | Location | Writes to | Key features | Pain points |
|---|---|---|---|---|
| **`waveform_edit.py`** | `verilogParse/` (older) | hard-wired `../Resources/SimSpcs` | Single-bit digital editor | Deprecated; replaced by `wave_edit.py` |
| **`wave_edit.py`** | `verilogParse/` (current) | `glbls.specs_dir` = `Resources/SimSpcs` | Single- and multi-bit digital editor, undo/redo, bus display, V+click value editing | Launched from `gen_verilog_tb.py` **Edit Sigs** button; saves to Swift specs file |
| **`wave_display.py` (editable top pane)** | `TwosCmplt/tools/` | `Resources/SimSpcs/<module>.yml` via **Save Inputs** | Same canvas as `wave_edit.py`, embedded in the Swift viewer | Edits are temporary until **Save**; merges editor-managed signals with preserved power/constant entries |

All three emit the same `Constants / Clock / FinishTime / TimeSpcs / Signals / SaveNds` YAML shape. The Swift simulator can read any of them.

---

## 6. The two-specs-file design (Phase 1)

Phase 1 of the refactoring establishes a clear, simulator-specific authoritative
specs file for each module:

1. `Resources/SimSpcs/<module>.yml` — authoritative for **Swift**. Written by the
   review dialog (when `simulator: Swift`), `wave_edit.py`, and `wave_display.py`
   Save; read by `SimRun` and `wave_display.py`.
2. `Resources/IVerilogSpcs/<module>.yml` — authoritative for **iVerilog**. Written by
   the review dialog (when `simulator: iVerilog`) and by manual edits; read by
   `makeTB.py`.

The legacy `~/.xschem/modules/<module>.yml` is no longer the source of truth. It is
kept only as a one-time migration source: if the new authoritative file does not
exist but the legacy file does, `run_sim_ui.py` copies it to the new location
before the first run.

### Merge behavior

`sync_all_specs()` now merges `TimeSpcs` on a **per-signal** basis:

- Signals present in the source file replace the same signals in the target file.
- Signals that are only in the target file are preserved, so manual edits on
  untouched signals survive an auto-generation or waveform-editor save.
- All other shared sections (`Constants`, `Clock`, `FinishTime`, `SaveNds`) are
  overwritten, because they are global rather than per-signal.

The same per-signal merge is used by `gen_verilog_tb.py`'s **Gen Inputs** dialog
and by `wave_edit.py` / `wave_display.py` when saving.

---

## 7. Current friction points

1. ✅ **Two specs files with unclear ownership.** Resolved in Phase 1: Swift and
   iVerilog each have an authoritative file under `Resources/` with clear
   simulator-based ownership.

2. ✅ **Auto-sync overwrites manual edits.** Resolved in Phase 1:
   `sync_all_specs()`, `wave_edit.py`, `wave_display.py`, and **Gen Inputs** now
   merge `TimeSpcs` per-signal, preserving manual edits on untouched signals.

3. **Redundant pipeline runs.** `run_sim_ui.py` runs `parse_verilog → parse_ast → parse_mod` once, then `gen_verilog_tb.py` runs it again when opening the review dialog.

4. **No periodic/repeating input primitive.** `TimeSpcs` is a flat list of time/value pairs. To create a repeating pattern (e.g. a serial bit stream), the user must either add many entries manually or write a Python helper to expand the pattern before simulation.

5. **Multiple waveform editors.** `waveform_edit.py`, `wave_edit.py`, and the editable pane in `wave_display.py` have overlapping but not identical behavior. Documentation points to different files depending on which entry point was used.

6. **Digital-mode discoverability in `ngui`.** `ngui` defaults to analog mode; the user must switch to Digital/Verilog hierarchy before Run Simulation does anything with Swift.

7. ✅ **iVerilog vs. Swift divergence.** Resolved in Phase 1: iVerilog reads
   `Resources/IVerilogSpcs/<module>.yml`; Swift reads
   `Resources/SimSpcs/<module>.yml`. The two are kept in sync by per-signal merge.

---

## 8. Data directories and conventions

| Artifact | Path | Written by | Read by |
|---|---|---|---|
| xschem symbol | `~/.xschem/verilogParse/lib/std28_lib/…/sym/<name>.sym` | xschem / `fix_circuit_params.py` | `run_sim_ui.py` |
| xschem schematic | `~/.xschem/verilogParse/lib/std28_lib/…/sch/<name>.sch` | xschem | `run_sim_ui.py` |
| Verilog netlist | `~/IC_Design/Testbenches/NgSpice/<name>/verilog/<name>.v` | xschem | `parse_verilog.py` |
| AST | `~/.xschem/ast_modules/<name>.ast` | `parse_verilog.py` | `parse_ast.py` |
| Module dict | `~/.xschem/mod_modules/<name>.mod` | `parse_ast.py` | `parse_mod.py` |
| Unified netlist | `~/.xschem/unl_modules/<name>.unl` | `parse_mod.py` | `SimRun`, viewers |
| CircuitLib YAML | `/home/Dropbox/…/TwosCmplt/Resources/CircuitLib/<name>.yml` | `parse_mod.py` | `makeCircDef()` |
| Swift specs | `/home/Dropbox/…/TwosCmplt/Resources/SimSpcs/<name>.yml` | `gen_verilog_tb.py` (Swift), `wave_edit.py`, `wave_display.py` Save | `SimRun`, `wave_display.py` |
| iVerilog specs | `/home/Dropbox/…/TwosCmplt/Resources/IVerilogSpcs/<name>.yml` | `gen_verilog_tb.py` (iVerilog), manual edits | `makeTB.py` |
| Dump files | `/home/Dropbox/…/TwosCmplt/Resources/DumpDir/<name>Map.yml` `<name>Chngs.yml` | `SimRun` | `wave_display.py`, `wave_view.py` |
| IVerilog VCD context | `/home/Dropbox/…/TwosCmplt/Resources/IVerilogSpcs/TB_<name>.yml` | `vcd2swift.py` / iVerilog flow | `wave_display.py` (iVerilog viewer branch) |
| Legacy Verilog specs | `~/.xschem/modules/<name>.yml` | (old, no longer written) | (migration source only) |

---

## 9. Areas to consider for improvement

This section lists candidate directions without prescribing a final design. The goal is to make the digital flow feel like one coherent toolchain rather than two glued together.

### 9.1 Consolidate the specs file

**Chosen approach (implemented in Phase 1):** Keep two authoritative files, one per
simulator, with clear ownership and per-signal merge:

- `Resources/SimSpcs/<module>.yml` — authoritative for Swift; edited by the Swift
  waveform editors and by hand.
- `Resources/IVerilogSpcs/<module>.yml` — authoritative for iVerilog; generated by
  the review dialog when `simulator: iVerilog` and edited by hand.

`sync_all_specs()` propagates shared sections between them with per-signal
`TimeSpcs` merge, so manual edits on untouched signals survive auto-generation
and waveform-editor saves.

### 9.2 Protect manual edits

Per-signal merge (Phase 1) already protects most manual edits: only signals that
the automatic tool explicitly touches are overwritten. If further protection is
needed, add a content-hash or `generated:` marker to auto-generated specs files
so `sync_all_specs()` can detect manual edits and warn before overwriting them.

### 9.3 Periodic / repeating input signals

Extend the spec YAML or the editors with a repeating-pattern primitive, e.g.:

```yaml
TimeSpcs:
  - tm: 0
    repeat:
      every: PER
      times: 16
      pattern: [0, 1, 0, 1]
    vls:
      - [DATA, $pattern]
```

This could be expanded by a small Python preprocessor before simulation, or supported natively by the Swift simulator.

### 9.4 Unify the waveform editors

`wave_edit.py` and the editable pane in `wave_display.py` already share the same canvas code (`waveform_edit.py`). Decide whether the standalone editor is the entry point or whether all editing happens inside `wave_display.py` after a first simulation.

### 9.5 Remove redundant pipeline invocations

`run_sim_ui.py` and `gen_verilog_tb.py` both call `run_pipeline()`. A single subprocess call that returns the paths and then opens the dialog would remove the duplicate work.

### 9.6 Make `ngui` digital mode more discoverable

Consider remembering the last-used mode per project, or defaulting to Digital when the symbol lives in a digital library (`std28_lib`, `dig_lib`).

---

## 10. Related documentation

- `verilogParse/CLAUDE.md` — pipeline overview, key directories, conventions
- `verilogParse/README_PIPELINE.md` / `PIPELINE_MAINTENANCE.md` — keeping the Verilog → CircuitLib pipeline up to date
- `verilogParse/wave_edit.md` — current waveform editor reference
- `TwosCmplt/tools/wave_display.md` — Swift waveform viewer reference
- `TwosCmplt/Simulation.md` — simulator architecture (Kahn's sort, nodes, slices, concats)
- `TwosCmplt/Sources/TwosCmplt/TwosCmplt.docc/CircDef.md` — assignment/slice/concat internals
- `TwosCmplt/ClaudeInstructions.md` — original staged plan for slice/concat refactoring
