# Simulation timing: why node writes arrive out of time order

**Where:** `/home/Dropbox/programming/Swift/TwosCmplt/SIM_TIMING.md`, TwosCmplt
branch **`ooo-trace`** (branched from `swift-compat-input-times` at 4a2229f).
**Date:** 2026-10-28. **Plan:** `~/.claude/plans/fancy-enchanting-marshmallow.md`.

This is an investigation. The simulation is unchanged. The branch only adds an
opt-in log (`SWIFT_OOO_LOG`, §8). With the log on and off, the dumps of
TST_CNTRM8, TST_CLA4 and TST_LTCHR_3X1 are equal as data. All 131
characterization testbenches gave the verdicts and change counts committed in
SimLib a36d7f9. The one exception is TST_CNTR8D, whose spec is now
16 periods long instead of 513.

Contents:
1. The question
2. Summary of the answer
3. What `sortCmpRefs` guarantees, and what it does not
4. Cause A, several writers of one bus: TST_CLA4, CLA8, CLA16, ACCUM3
5. Cause B, a false cycle at instance granularity: TST_CNTRM8, CNTR8G
6. Counts over all 131 testbenches
7. Proposals: evaluation without out-of-order writes
8. How to reproduce: testbenches, commands, breakpoints, the log
9. Files

---

## 1. The question

Two repairs exist in `Sources/TwosCmplt/Circuit.swift`:

- **`setNode`, the `supersede` branch.** It is at line 1145 on
  `swift-compat-input-times` and line 1147 on `ooo-trace`, and was added in
  commit `b857af8`. A combinational write (an assign, or a blocking
  assignment without a clock edge) that is stamped earlier than the node's
  latest change replaces that change, via `mergeBits(..., overwriteLater:
  true)`.
- **`mergeBits`** (commit `4d312a1`). A bit or slice of a bus that is written
  for an earlier time is merged into the bus's history at its own time. It is
  reached from `setNodeBit` and `setNodeBits`: a child's output port driving
  one bit or slice of a parent bus.

`sortCmpRefs` (line 547) orders each circuit's children so that every child is
evaluated after the children that drive it. If evaluation is ordered, why do
writes ever arrive stamped earlier than what is already recorded?

## 2. Summary of the answer

`sortCmpRefs` works as designed. It orders by **dependency**, which gives
**causality**: a child sees the final values of its drivers for the sweep. It
does not, and no fixed order can, give **time order** of the writes to one
node. Over all 131 testbenches, every early write that changes the recorded
history has one of two causes:

| Cause | Repair that fires | Testbenches | History-changing writes |
|---|---|---|---|
| **A. Several writers of one bus.** Each bit is driven by a different child instance. Each write is correctly ordered against its own drivers, but the children's output times are unrelated. | `mergeBits` | TST_CLA4, TST_CLA8, TST_CLA16, TST_ACCUM3 | 455 |
| **B. A false dependency cycle.** `CNTRE4`'s `COUT` does not depend on its `L` input, but `sortCmpRefs` treats an instance as one block (any input to any output). So `CNTR1 → COUT1 → NAND1 → INV1 → LD → CNTR1.L` looks like a cycle. It is evaluated in declaration order with repeated passes (`hasLoop`). The first pass uses a stale `L` and stamps `L0_IN` too late; the repeat writes the correct, earlier time. | `setNode` supersede (line 1145) | TST_CNTRM8, TST_CNTR8G | 27 |

There were 166,998 more early writes, in 13 testbenches, and **none changes
anything**. In each one, a child re-copies an unchanged output bit to a bus
with the bit's own older time stamp, after another bit changed later. The
value at that time is already right, so `mergeBits` returns.

The hypothesised backward plain commit (`setNode` without `supersede`
committing an earlier time) **never happens** in the 131 testbenches. Nor do
early writes caused by the sync/async pass order, the `evalEarlierInputs`
sub-sweeps or a sync leaf cell, other than as consequences of cause B (§6).

## 3. What `sortCmpRefs` guarantees, and what it does not

SimRun is a **levelized (sweep) simulator**. iVerilog is **event-driven**.

| | iVerilog (event-driven) | SimRun (sweep) |
|---|---|---|
| Unit of work | one event, processed at its own time | one evaluation of each child per pass of a half period |
| Order | time order (the event queue) | dependency order (`sortCmpRefs`: Kahn's algorithm over child instances) |
| Time of an output | the event's time + the delay | the latest input time read + the delay (`asgnReadTm`, Sim.swift:937; `updTm` of the inputs) |
| Glitches | every intermediate event | only the final value of each input per pass |

How one half period runs (`simCircuit`, Sim.swift:1608):
1. `evalEarlierInputs` (Sim.swift:1595) applies the inputs at each time before
   the window's last change, with an async pass at each such time.
2. `setInputs` is applied at the last time.
3. Then, depending on the half: `eval(async: true)` followed by
   `eval(async: false)`; or `eval(async: false)` followed by
   `eval(async: true)`.

Inside `Circuit.eval` (Circuit.swift:1253):
1. Input ports are copied from the parent in port order (line 1281 on
   `ooo-trace`).
2. Children are evaluated in `evalOrder`, repeated while something changes if
   `hasLoop` (line 1376).
3. Always blocks and assigns run.
4. Output ports are copied to the parent (line 1465), with the child node's
   `updTm`.

**Why dependency order is not time order.** The time a write is stamped with
comes from the delays along the path that produced it. Two writes to one node
from children that do not depend on each other can be evaluated in either
order, and either can be the earlier in time. The same is true when one
depends on the other through a different output. Which of them is earlier
also depends on the data: which inputs changed in this sweep, and therefore
which paths are active. So no order computed once at start-up can put every
node's writes in time order. Only an event queue sorted by time can. The
sweep simulator substitutes two repairs: insert a late-arriving write at its
own time (`mergeBits`), and let a correct earlier write replace a wrong later
one (supersede).

**What `sortCmpRefs` needs in order to give causality.** The dependency graph
must have no cycles. `initializeCmpCnts` (Circuit.swift:567) removes edges
out of **leaf** sync cells, the behavioural flip-flops. This is right: their
outputs change only at clock edges (`isSync`, line 1832 on `ooo-trace`). A
**composite** sync cell (a counter built from flip-flops and gates) keeps
all its edges, because it can have combinational input-to-output paths
(CNT → COUT). Where it has none on a given output, the edge is false, and a
false edge can close a false cycle (cause B).

## 4. Cause A, several writers of one bus: TST_CLA4 (also CLA8, CLA16, ACCUM3)

### Circuit

`CLA2` (`~/.xschem/verilogParse/ver_lib/CLA2.v`):

```
CLA1 CLA1_0 ( A[0], B[0], CI,  C_0, G0, P0, S[0], VDD, VSS );
CLA1 CLA1_1 ( A[1], B[1], C_0, C_1, G1, P1, S[1], VDD, VSS );
```

`CLA1_1` takes its carry in, `C_0`, from `CLA1_0`. So `sortCmpRefs` correctly
evaluates `CLA1_0` first. Each instance then writes one bit of the same
2-bit node `S`, via its output-port copy (`setNodeBit`, Circuit.swift ~1470 on `ooo-trace`).

### Critical paths

- `S[0]` (in `CLA1_0`): the path through the carry in, `CI` → sum. This is
  the longer path. `CLA2_1`'s `CI` comes from `CLA2_0`'s carry chain.
- `S[1]` (in `CLA1_1`): the change comes from its own `A[1]`/`B[1]`, a shorter
  path, so it is stamped earlier. Its carry-in path doesn't change in this
  sweep.

### Timeline

TST_CLA4: node `Top.CELL.CLA2_1.S`, sweep at 10500 ps (half period 83, the
`sync-then-async` half). The rows below are in the order of evaluation.

| Order | Writer (evaluation stack) | Bit | Time stamped | Recorded bus |
|---|---|---|---|---|
| 1 | `CELL(CLA4) / CLA2_1(CLA2) / CLA1_0(CLA1) / out-ports` | S[0] | **10532 ps** | S = 0 at 10532 |
| 2 | `CELL(CLA4) / CLA2_1(CLA2) / CLA1_1(CLA1) / out-ports` | S[1] | **10504 ps** | early by 28 ps → `mergeBits` |

Before `4d312a1`, bit 1 was merged into the *latest* value. That recorded
S = 2 at 10504 ps (it was 3) and S = 0 at 10532 ps (it was 2). sim_compare
then failed TST_CLA4, CLA8 and CLA16, and the change counts were off.

The same pattern occurs at higher levels:
- in TST_CLA8: `Top.CELL.S`, `CLA8_0` then `CLA8_1`, 254 ps after 304 ps;
- in TST_CLA16;
- in TST_ACCUM3: `M1M_QDACCUM5` drives each bit of `QD_[17:0]` from its own
  buffer or inverter (`BUF16`, `INV2`, `BUF2`…; ver_lib/M1M_QDACCUM5.v
  lines 36–54). For example, `QD_` gets 4049 ps from `BUF16` after 4050 ps
  from `INV2`.

Had each bit been its own node, every node would have had a single writer and
there would have been no early write. The early write is an artifact of
representing a bus written by several instances as one node.

## 5. Cause B, a false cycle at instance granularity: TST_CNTRM8 (also CNTR8G)

### Circuit

`CNTRM8` (`ver_lib/CNTRM8.v`). `CNTR8G` (`ver_lib/CNTR8G.v`, in TST_CNTR8G) is
the same circuit with `KM_CNTR4G` as `CNTR0`.

```
KM_CNTR4E    CNTR0 ( VDD,   COUT0, CP, CN, D[3:0], INIT, LD, QN[3:0], QP[3:0], VDD, VSS );
CNTRE4       CNTR1 ( COUT0, COUT1, CP, CN, D[7:4], INIT, LD, QN[7:4], QP[7:4], VDD, VSS );
DG_NAND2_2X1 NAND1 ( COUT0, COUT1, LD_N, VDD, VSS );
DG_INV4_1X1  INV1  ( LD_N,  LD, VDD, VSS );
```

`CNTRE4`'s port order is `(CNT, COUT, CP, CN, D, INIT, L, QN, QP)`, from
`ver_lib/CNTRE4.v`. Inside it:

```
DG_INV4_1X1  INV1  ( CNT,   CNTN );             CNT  -> CNTN
DG_NOR2_2X1  NOR1  ( CNTN,  QP[0], T1 );        CNTN, QP[0] -> T1   (T of TLD1)
DG_NAND2_2X1 NAND3 ( QN[2], QN[3], ND1 );
DG_NOR2_2X1  NOR5  ( QP[1], ND1,  ND2 );
DG_NAND2_2X1 NAND4 ( QN[0], ND2,  ND3 );
DG_INV4_1X1  INV_0 ( ND3,   COUT );             COUT from QN/QP only
DG_TDER_6X2  TLD1  ( L, D[1], T1, INIT, CBP, CBN, QP[1], QN[1] );   (sync leaf)
```

`COUT` depends only on the flip-flops' outputs (`QN`, `QP`). It depends on
neither `L` nor `CNT`. Seen as gates, `COUT1 → NAND1 → INV1 → LD → L` is
therefore not a loop: `L` reaches only the flip-flops' `L` inputs.

`sortCmpRefs` sees `CNTR1` as one node. To it, every input feeds every
output, so `CNTR1 → NAND1 → INV1 → CNTR1` is a cycle. `CNTRE4` is a sync
*composite*, so `isSync` keeps its edges. `initializeCmpCnts` (lines 607–621)
finds the cycle:
- it appends the members in declaration order (`circ.evalOrder += missing`,
  line 619), with `CNTR1` before `NAND1` and `INV1`;
- it sets `hasLoop`, and `eval` repeats the async pass until nothing changes.

`DG_TDER_6X2` (`ver_lib/DG_TDER_6X2.v`, instance `TLD1` in `CNTR1`):

```
assign L0_IN = (L ? LI : (T ? ~STATE : STATE));
always @(L0_IN or STATE) ENBL = (L0_IN != STATE);
```

An assign is stamped with the latest `updTm` among the inputs it actually
**reads** (`asgnReadTm`, Sim.swift:937). With `L = 0` it reads `L`, `T` and
`STATE`; with `L = 1`, only `L` and `LI`.

### Critical paths (at start-up, the `init` phase, sweep time 0)

- **T path:** `CNTR0.COUT0` (44 ps) → `CNTR1.CNT` → `INV1` → `CNTN` → `NOR1`
  → `T1` (70 ps) → `TLD1.T` → `L0_IN`.
- **L path:** `CNTR0.COUT0` and `CNTR1.COUT1` (44 ps) → `NAND1` → `LD_N`
  (53 ps) → `INV1` → `LD` (65 ps) → `CNTR1.L` → `TLD1.L` → `L0_IN`.

In time, `L` rises at 65 ps, before `T` rises at 70 ps.

### Timeline (the dump's record order is the order of writing)

| Write | `CNTRM8` loop pass | Node | Value | Time stamped |
|---|---|---|---|---|
| 1 | 1 or 2 | `COUT0` (from `CNTR0`) | 1 | 44 ps |
| 2 | 2 | `CNTR1.T1`, `TLD1.T` | 1 | 70 ps |
| 3 | 2 | `TLD1.L0_IN`: reads `L` = 0 (**stale**; the new `LD` isn't computed yet), so the `T` branch, stamped with T's time | 1 | **70 ps** |
| 4 | 2 | `COUT1` (`CNTR1` out-ports) | 1 | 44 ps |
| 5 | 2 | `LD_N` (`NAND1`, after `CNTR1` in declaration order) | 0 | 53 ps |
| 6 | 2 | `LD` (`INV1`) | 1 | 65 ps |
| 7 | 3 | `CNTR1.L`, `TLD1.L` | 1 | 65 ps |
| 8 | 3 | `TLD1.L0_IN`: reads `L` = 1 and `LI`, stamped with L's time | 1 | **65 ps** → supersede, line 1145 |

The logged entry for write 8 reads:

```
node: Top.CNTRM8.CNTR1.TLD1.L0_IN, path: setNode-supersede, new_tm: 65, cur_tm: 70,
writer: 'loop-repeat 3 / CNTR1(CNTRE4) async tm=0 / TLD1(DG_TDER_6X2) async tm=0 / assign[0]',
collides_with: {tm: 70, writer: 'loop-repeat 2 / … / TLD1(DG_TDER_6X2) … / assign[0]'}
```

An event-driven simulator processes `LD` at 65 ps, so `L0_IN` follows `LI`
from 65 ps, and `T`'s change at 70 ps never reaches it. SimRun evaluated
`CNTR1` before the gates that compute its own `L` input. The pass with the
stale input wrote a value and time that iVerilog never produces, and the
repeat pass corrected it.

Before `b857af8`, write 8 was committed *after* write 3 (time going 70 → 65).
iVerilog's `ENBL` disagreed in period 2, and TST_CNTRM8 failed.

The same happens in `TLD2` and `TLD3`. `TLD3` gives `L0_IN = 0` and
`ENBL = 0` at 65 ps, where the 70 ps record had 1. The same structure in
TST_CNTR8G gives 6 entries.

Of TST_CNTRM8's 21 entries:
- 7 are this loop repeat, at start-up.
- 14 are "earlier sweep". These are the same 65 ps `L0_IN` value rewritten
  in the first sweeps (the 10 ps sub-sweep and the 50 ps half period), still
  colliding with the 70 ps record left by pass 2 at start-up. They are
  consequences of the same cycle, not a separate cause.

## 6. Counts over all 131 testbenches

The run used SimLib `sim_compare.py --all-characterization` with
`SWIFT_OOO_LOG=<dir>` and the release build of `ooo-trace`. The 78 MB of logs
are not kept. The summary is in `Tools/ooo/summary_2026-10-28.txt`, and the
scripts that produce it are beside it.

History-changing early writes (all others are `effect: none`):

| Testbench | Count | Cause | Path |
|---|---|---|---|
| TST_CLA8 | 193 | A: `CLA8_0`/`CLA8_1`, `CLA2_x`/`CLA1_x` bus `S` | `mergeBits` |
| TST_CLA16 | 179 | A | `mergeBits` |
| TST_ACCUM3 | 64 | A: `M1M_QDACCUM5` `QD_[17:0]`, one buffer per bit | `mergeBits` |
| TST_CNTRM8 | 21 | B: `CNTRE4` instance-level cycle | supersede |
| TST_CLA4 | 19 | A: `CLA2_1.S` | `mergeBits` |
| TST_CNTR8G | 6 | B | supersede |
| **Total** | **482** | | |

All early writes per testbench, 167,480 in 13 testbenches (166,998 harmless `effect: none` plus the 482 above):

| Testbench | Count |
|---|---|
| TST_ACCUM3 | 40,394 |
| TST_CNTRM8 | 34,033 |
| TST_CNTR8G | 32,210 |
| TST_CLA8 | 24,807 |
| TST_CLA16 | 13,437 |
| TST_CLA4 | 11,216 |
| TST_PRGT4 | 4,150 |
| TST_CLA2 | 3,869 |
| TST_CMPL12 | 2,104 |
| TST_CNTR8D | 596 |
| TST_PRPA | 262 |
| TST_PRPF | 262 |
| TST_PRPB | 140 |

The other 118 testbenches have no early writes.

**Other paths:**
- `setNode-plain` (a backward commit without supersede): 0.
- Latches (TST_LTCHR_3X1 and the others fixed by `b857af8`): 0. Their fix was
  the assign re-run after always blocks, not the supersede.

## 7. Proposals: evaluation without out-of-order writes

These are proposals only; nothing is implemented. They are ordered by how
much they change, smallest first.

### 7.1 Port-level dependencies in `sortCmpRefs` (removes cause B)

**Idea:** order children by which input reaches which output inside each
child, not by whole instances.

**Steps:**
1. **Per module, once, cached with the `Circuit` in `circuitCache`:** compute
   the combinational reachability from each input port to each output port.
   Treat leaf sync cells as cuts, as `isSync` already does. For `CNTRE4`:
   - `COUT` is reached from no input (a *state-only* output);
   - `QP` and `QN` are reached from none either;
   - `CNT` reaches only the `T` inputs of the flip-flops.
2. **In `initializeCmpCnts`** (Circuit.swift:571–595): where a node's driver
   is a child output port that no input of that child reaches, skip the node,
   exactly as for a leaf sync cell's output today (the `isSync` test at line
   578). For a port reached only from some inputs, keep the edge. This
   already removes the false cycle, because `COUT1` adds no edge
   `CNTR1 → NAND1`.
3. **Result for CNTRM8:** no cycle and no `hasLoop`. `evalOrder` puts `NAND1`
   and `INV1` before `CNTR1`, so `CNTR1` sees `LD` at 65 ps in its single
   pass. `L0_IN` is written once, at 65 ps, the same as iVerilog. The repeat
   passes also go away (faster).

**Why it's safe:** a state-only output changes only when the child's
registers change. Those changes reach the parent through the existing
`eval(async: false)` → `eval(async: true)` sequence ("async after regs",
Sim.swift ~1660), which is how leaf flip-flop outputs already propagate.

**Cost:** one reachability pass per module, over the module's own gates and
children. Composites use their children's cached port maps recursively.

**Limit:** a *real* combinational loop through a composite (an input that
reaches an output that feeds back to it) still needs `hasLoop`. That is
correct, because it is a real loop.

**Check:**
- TST_CNTRM8 and TST_CNTR8G: 0 supersede entries in the log, and the same
  verdicts.
- All 131: the same verdicts, and power within 1 %.
- Success: 0 supersede entries in cause B testbenches. Failure: any verdict
  worse.

### 7.2 Time-ordered writes for multi-writer buses (removes cause A)

Either of two ways:

- **(a) Per-bit nodes.** Split a bus whose bits are written by several child
  instances into one internal node per writer's slice, and join them for
  readers and for the dump. Each slice then has a single writer and no early
  writes. This is the larger change: `setNodeBit`/`setNodeBits`, the readers'
  `selBits`, `saveChng`, and the Map/Chngs dump.
- **(b) Deferred commit per parent evaluation.** In `Circuit.eval`, collect
  the children's output-port writes to a multi-writer bus during the pass.
  At the end of the pass (before the parent's own output copy), sort them by
  time and apply them with `commit`/`saveChng`. That is a small event queue
  per bus per pass. `mergeBits` would then never see an early write from
  that pass.

  The catch: a sink evaluated later in the same pass reads the bus before the
  sorted commit. Today it reads the latest merged value, so the reader would
  have to be ordered after the commit. That is natural if the bus is
  committed as soon as its last writer in `evalOrder` has run.

Both keep the sweep simulator. `mergeBits` stays as a safety net, and the
log's `mergeBits` count becomes the measure (target: 0).

### 7.3 Copy only changed outputs (removes the harmless entries)

In the output-port copy (Circuit.swift ~1465), skip a port whose internal
node did not change during this evaluation; compare `updTm` with the value it
had at entry. All 166,998 `effect: none` entries are such re-copies of
unchanged bits with old times. Removing them saves work: `mergeBits` walks
`hist`, and up to 4096 entries of `nodeChngs` for each early write. It
changes no result. This is the cheapest of the three proposals.

### 7.4 An event queue (removes both, by construction)

Replace the sweep with a time-ordered queue of node changes, evaluating each
child when one of its inputs changes, at that time. This is what iVerilog
does. It would also keep glitches (§3), which explains part of the Swift vs
iVerilog power difference noted in SimLib's project memory. It is a rewrite
of `Circuit.eval` and `simCircuit`, and the largest change. 7.1 + 7.2 + 7.3
remove all the observed out-of-order writes without it.

**Recommendation:** 7.3, then 7.1 (it fixes the only case where a *wrong*
value was written: `L0_IN`/`ENBL` from a stale `L`), then 7.2(b) if the
`mergeBits` path is to be retired. Cause A writes only correct values late;
`mergeBits` already handles it exactly.

## 8. How to reproduce: testbenches, commands, breakpoints, the log

### Build (TwosCmplt directory)

```
cd /home/Dropbox/programming/Swift/TwosCmplt
git switch ooo-trace
swift build --product SimRun                 # .build/debug/SimRun (for lldb)
swift build -c release --product SimRun      # .build/release/SimRun (Config.yaml's simRunner: the UI and sim_compare use this)
```

On g23, a non-interactive ssh needs `~/.local/share/swiftly/bin/swift`. When
you're done, go back to `git switch swift-compat-input-times` and rebuild the
release build. The log is off unless `SWIFT_OOO_LOG` is set, so leaving the
`ooo-trace` build in place changes nothing.

### Which testbenches to run

| To see | Testbench | Spec |
|---|---|---|
| Cause B (supersede, line 1145), the clearest | **TST_CNTRM8** | `~/IC_Design/Testbenches/NgSpice/SimLib/Testbenches/TST_CNTRM8/VerilogSpecs/TST_CNTRM8.yml` |
| Cause B, the same circuit | TST_CNTR8G | `…/SimLib/Testbenches/TST_CNTR8G/VerilogSpecs/TST_CNTR8G.yml` |
| Cause A (`mergeBits`), the smallest | **TST_CLA4** | `…/SimLib/Testbenches/TST_CLA4/VerilogSpecs/TST_CLA4.yml` |
| Cause A, another circuit | TST_ACCUM3 | `…/SimLib/Testbenches/TST_ACCUM3/VerilogSpecs/TST_ACCUM3.yml` |
| A latch: no early writes at all | TST_LTCHR_3X1 | `…/SimLib/Testbenches/TST_LTCHR_3X1/VerilogSpecs/TST_LTCHR_3X1.yml` |

The command is the one `run_sim_ui.py` uses (line 9923):

```
S=~/IC_Design/Testbenches/NgSpice/SimLib/Testbenches
.build/debug/SimRun TST_CNTRM8 Config.yaml --spec $S/TST_CNTRM8/VerilogSpecs/TST_CNTRM8.yml
```

It takes about 7 s; TST_CLA4 about 20 s.

### Breakpoints (lldb, debug build; line numbers on `ooo-trace`)

```
lldb -- .build/debug/SimRun TST_CNTRM8 Config.yaml --spec $S/TST_CNTRM8/VerilogSpecs/TST_CNTRM8.yml
(lldb) br set -f Circuit.swift -l 1147 -c 'ndNm == "L0_IN"'   # supersede (1145 on swift-compat-input-times)
(lldb) run
(lldb) bt                    # TLD1.eval <- CNTR1.eval <- CNTRM8.eval: the hasLoop repeat (line 1376)
(lldb) p tm                  # 65
(lldb) p self.nodes[ndIndx].updTm    # 70
```

To see the stale read, also break where `L0_IN` was stamped 70. That is the
same assign, in the pass before: `br set -f Sim.swift -l 1320` with condition
`name == "L0_IN"`. Then step into `CNTRM8`'s `evalOrder` and see `CNTR1`
listed before `NAND1` and `INV1`.

For TST_CLA4:

```
(lldb) br set -f Circuit.swift -l 1204    # mergeBits after the in-order return (1199 on swift-compat-input-times)
(lldb) br modify -c 'tm == 10504' 1
```

### The log

`SWIFT_OOO_LOG=<file>` writes one YAML line per early write. If it names a
directory, the file is `<dir>/ooo_<pid>.yml`; use this with `sim_compare.py`,
which runs many testbenches. Each line has these fields:

| Field | Meaning |
|---|---|
| `n`, `tb`, `phase` | Entry number, testbench, and sweep: `init`; `hp <k>` (half period); `async-then-sync` / `sync-then-async` / `early t=` (evalEarlierInputs) with the sweep time |
| `node` | The full instance path |
| `path` | `setNode-supersede`, `mergeBits` (`mask` gives the bits) or `setNode-plain` |
| `new_tm`/`new_val` | The early write |
| `cur_tm`/`cur_val` | The node's latest change at that moment |
| `effect` | `merge` (history changed), `none` (value already right) or `commit-backwards` (setNode-plain) |
| `writer` | The innermost four levels of what is being evaluated: cells `name(module) async/sync tm=`, then `in-ports` / `out-ports` / `gate[i]` / `assign[i]` / `always`; `loop-repeat n` marks a `hasLoop` pass |
| `collides_with` | The record it lands before: its time, value, writer and phase |

Summaries (`Tools/ooo/`):

```
vy Tools/ooo/classify.py <file.yml>      # one log: counts by path, cause and effect
vy Tools/ooo/summarize.py <dir>          # a directory of logs: per testbench and first example of each
```

## 9. Files

**Changed on `ooo-trace` (log only; every hook is `if OooLog.on`):**
- `Sources/TwosCmplt/OooLog.swift` (new): the log; the writer stack (`push`/`pop`); the last writer per node (`wrote`); `early`.
- `Sources/TwosCmplt/Circuit.swift`:
  - `saveChng`: `wrote`;
  - `setNode`: supersede and plain-backward hooks;
  - `mergeBits`: early-write hook;
  - `eval`: the stack (cell, `in-ports`, `gate[i]`, `loop-repeat`, `out-ports`);
  - `simVrlgAlwys`: `always`;
  - `runAssignBlck`: `assign[i]`.
- `Sources/TwosCmplt/Sim.swift`: `simCircuit` and `evalEarlierInputs` set
  `OooLog.tb` and `OooLog.phase`.
- `Tools/ooo/classify.py`, `Tools/ooo/summarize.py`,
  `Tools/ooo/summary_2026-10-28.txt`.

**Read for this report:**
- **TwosCmplt:**
  - `Circuit.swift`: `sortCmpRefs` 547, `initializeCmpCnts` 567–621,
    `setNode`, `setNodeBit`, `setNodeBits`, `mergeBits`, `eval`, `isSync`;
  - `Sim.swift`: `setLeftNet` ~1295 (supersede flag), `asgnReadTm` 937,
    `evalEarlierInputs`, `simCircuit`;
  - `Node.swift`: `Nod.commit`, `value(at:)`, `histDepth`.
- **verilogParse `ver_lib/`:** `CLA2.v`, `CLA1.v`, `CNTRM8.v`, `CNTR8G.v`,
  `CNTRE4.v`, `DG_TDER_6X2.v`, `M1M_QDACCUM5.v`.
- **Git history:**
  - `4d312a1` (2026-10-27, `mergeBits`, TST_CLA4/8/16 FAIL → GLITCH-ONLY);
  - `b857af8` (2026-10-28, supersede, assign re-run, combinational always at
    `trigTm`; TST_CNTRM8 FAIL → GLITCH-ONLY);
  - SimLib `e78593a` (the verdicts before and after `b857af8`).
