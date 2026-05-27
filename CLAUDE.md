# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build the whole package
swift build

# Build a specific target
swift build --target Filter3A

# Run tests
swift test

# Run a single test class or method
swift test --filter TwosCmpltPackageTests/testInit

# Run an example executable
swift run CoeffMltply
swift run Filter3A

# Build with logging
swift build 2>&1 | tee swift-build.log

# Generate documentation (see scripts/)
./scripts/build-doc.sh
```

## Architecture

**TwosCmplt** is a Swift library for simulating fixed-point digital hardware circuits using two's complement arithmetic. It models circuits at the gate/register level, evaluates them in topological order, and can emit VCD waveform output.

### Package targets

- **SharedTypes** — foundational types used everywhere: `TwoCmplt` (the core fixed-point integer type), `States` (global arithmetic modes), `MixedValue`, and the `Value`/`ScheduledUpdate` types used by the bytecode VM.
- **TwosCmplt** — the main library. Depends on `SharedTypes`, `Yams`, `SwiftPrettyPrint`, and `swift-configuration`.
- **ExamplesShared** — shared helpers for example executables.
- **ExamplesDoc** — documentation-focused examples.
- Many **executable example targets** under `Examples/`: `CoeffMltply`, `CmplxMltply`, `Filter3A`–`Filter3E`, `Filter5A`, `Filter5B`, `Filter9A`, `Osc1`–`Osc4`, `CmplxFilter*`, `Cordic1`, `Cordic2`, `Gates`, `Circuits`, `Interpret`, etc.
- **TwosCmpltTestingRunner** — standalone test runner executable.
- **TwosCmpltTests** — XCTest suite.

### Core types (SharedTypes)

`TwoCmplt` (`Sources/SharedTypes/TwoCmplt.swift`) is the central numeric type. It carries `value: Int`, `nbits`, `prec` (fractional LSBs), `signed`, `ovflw`, and `crry`. Arithmetic operators are defined in `Sources/TwosCmplt/Operators.swift`. Global arithmetic behavior (multiply truncation, add saturation, precision mode, rounding) is controlled via static properties on `States`.

### Circuit simulation model

A **`Circuit`** (`Sources/TwosCmplt/Circuit.swift`) is a hierarchical, event-driven gate-level netlist:

- **Nodes** (`Nod`) — named wires carrying a `TwoCmplt` value and a timestamp.
- **Gates** (`Gate`) — combinational elements (inv, buf, and, nand, or, xor, full-adder, etc.) with truth tables loaded lazily from YAML in `Resources/LogicLib/`.
- **Registers** (`Reg`) — synchronous flip-flops/registers.
- **Sub-circuits** — `aCircs` (async), `sCircs` (sync registers), `vCircs`/`cCircs` (Verilog-derived or composed sub-circuits).
- **Evaluation order** — determined at build time by topological sort (`initializeCmpCnts` / `sortCmpRefs`). Components are then evaluated in `evalOrder` each simulation step.

Circuit definitions are YAML files in `Resources/CircuitLib/` (subcircuits) and `Resources/LogicLib/` (primitive gates). `Circuit.make()` loads, parses, wires, and caches a circuit from YAML. `Circuit(module:name:)` uses a static cache so repeated instantiation avoids re-parsing.

### Verilog-derived circuits

`CircDef` (`Sources/TwosCmplt/CircDef.swift`) is a decoded YAML representation of a Verilog-derived module. It holds `alwaysBlcks`, `initBlcks`, `assgnBlcks`, and a set of component instances. `Compile.swift` generates bytecode (`[Instruction]`) from `CircDef` behavioral blocks. The bytecode VM lives in `Sim.swift`; `Context` holds the circuit reference, program counter, and operand stack during execution.

### Simulation specification

Simulation runs are described by YAML files in `Resources/SimSpcs/`. `SpecStruct` (`Sources/TwosCmplt/Sim.swift`) decodes clocks, finish time, input stimulus (`TimeSpcs`), and nodes to save. Time expressions support `PER` as a named constant (e.g., `"12*PER"`).

### DSP / arithmetic extensions

`TwosCmplt.swift` (the main module, not SharedTypes) extends `TwoCmplt` with carry-save adder variants (`csAdd`, `csA2S`, `csAddN`, `csAdd2Subt1`, etc.) used in the filter and coefficient-multiply examples. `CoeffMult.swift` and `CoeffMltply.swift` show fixed-coefficient multiplication strategies. Complex arithmetic lives in `cmplx_mult.swift`.

### Global state

`Glbls` (`Sources/TwosCmplt/Glbls.swift`) is the process-wide registry:
- `Glbls.register(_:)` / `Glbls.circDef(for:)` — `CircDef` dictionary.
- `Glbls.circLibDir`, `logicLibDir`, `simSpcsDir` — URL paths derived from `#filePath` at compile time.
- `Glbls.nodeChngs`, `allChngs` — simulation change log used for VCD output.
- `Glbl` — arrays (`a0_`–`a3_`, `arry`) used by DSP examples as scratch space.

### VCD output

`writeVcd.swift` produces VCD (Value Change Dump) waveform files from `Glbls.nodeChngs`. VCD output paths and signal declarations are configured in YAML or programmatically.

### Resources layout

```
Resources/
  CircuitLib/   # subcircuit YAML definitions (ADDR.yml, CNTR3.yml, …)
  LogicLib/     # primitive gate truth-table YAML (And2.yml, Buf.yml, …)
  SimSpcs/      # simulation specification YAML (clocks, stimulus, …)
```

### Concurrency notes

The library targets Swift 6.1 with `-strict-concurrency=minimal` on the `TwosCmplt` target and `StrictConcurrency=targeted` on example targets. Most global state is marked `nonisolated(unsafe)` to satisfy the compiler while retaining single-threaded simulation semantics.
