# CircDef

## Introduction

`CircDef` (`Sources/TwosCmplt/CircDef.swift`) is the decoded, in-memory
representation of a Verilog-derived module: its declarations, parameter
list, and a `BehavAST` describing every `assign`/`always`/`initial`/instance
block found in the module's YAML source. This page documents, in detail,
how the right-hand side (RHS) of an assignment statement is parsed and
turned into that representation, why `CircDef.exprs` and `CircDef.stmts`
sometimes appear so lopsided (one full, the other empty) at a breakpoint,
and evaluates a proposed algorithm for giving bit-slices and concatenation a
real, structural presence in the simulated netlist.

This document was written as the first step of a staged effort (see
`ClaudeInstructions.md` in the repository root) to fix how slices and
concatenation are handled during circuit parsing and simulation. A handful
of bugs found during this investigation were fixed alongside writing this
document (all "known issue" sections below say explicitly whether the
associated bug was fixed or left for a later pass); the larger structural
change described in Part 2 is **not** implemented yet and is left for a
follow-up.

## Part 1 — How RHS assignment expressions are parsed today

### The two arenas: `exprs` and `stmts`

`CircDef` holds two independent, append-only arrays (`CircDef.swift:665-693`):

```swift
public mutating func internExpr(_ e: Expr) -> ExprId { ... }   // appends to exprs
public mutating func internStmt(_ s: StmntAST) -> StmtId { ... } // appends to stmts
public func getExpr(_ id: ExprId) -> Expr { exprs[id.raw] }
public func getStmt(_ id: StmtId) -> StmntAST { stmts[id.raw] }
```

`ExprId`/`StmtId` are just wrapped integer indices into these arrays —
bump allocators, not trees. `StmntAST` cases hold `ExprId`s referencing into
`exprs`; expressions never reference back into `stmts`. Every subexpression,
including nested ones, gets its own entry in `exprs` — a single assignment
with a 16-bit concatenation of single-bit selects (see below) can intern
30+ expression entries.

### Why `stmts` can be empty while `exprs` keeps growing

This was the specific behavior observed at a debugger breakpoint that
prompted this investigation, and it turns out to be by design, not a bug:

`CircDef.stmts` is populated from exactly **one** call site in the entire
codebase: `StmntYAML.compileStmt(in:)` (`CircuitParse.swift:1454-1482`),
which is only reached while walking the body of a procedural block —
`always`, `initial`, `if`, `case`, a loop, etc. Top-level **continuous**
`assign` statements never go through this path. Instead,
`AssgnBlckYAML.toAST` (`CircuitParse.swift:1557-1567`) builds an
`AssgnBlckAST` directly and hands it to `CircDef.buildBehavAST()`
(`CircDef.swift:726-730`), which stores it straight into `CircDef.behav` —
`internStmt` is never called for it.

So a module built entirely out of continuous assigns (no procedural blocks)
will have an empty `stmts` array for its whole lifetime, while `exprs` grows
with every RHS subexpression from every assign. A concrete example already
in the resource library:
`Resources/CircuitLib/M1M_QDACCUM5.yml:826-898` is a continuous assign whose
RHS concatenates `C1R` with sixteen single-bit selects of `ADDR1R_`
(`ADDR1R_[15]` down to `ADDR1R_[0]`) — each becomes its own interned
`Expr.select`, but the whole statement never touches `stmts`.

This means "an assignment" is represented by two structurally different
mechanisms depending on where it appears (continuous vs. procedural) — a
real architectural wart, and the underlying reason `AssgnAST` needed to
exist in more than one shape (see next section). It was left as-is in this
pass; unifying continuous assigns and procedural single-assigns onto one
storage path would be a reasonable follow-up but is a larger change than
the scope here.

### `assgnst` / `concatst`, and why `AssgnAST`/`SingleConcatAST` were merged

`StmntAST` (`CircuitParse.swift:2235-2248`) has two cases for procedural
assignment-like statements:

```swift
case assgnst(AssgnBody)          // a single scalar-target procedural assign
case concatst(ConcatStmntAST)    // an explicit multi-part / concat-target procedural assign
```

These are not fully redundant in intent — `assgnst` represents one plain
target, `concatst` represents a statement whose target was written as an
explicit list of parts (e.g. a Verilog `{a, b} = x;`-style concat target) —
but their backing structs, `AssgnAST` and `SingleConcatAST`, were
field-for-field identical:

```swift
public struct AssgnAST {
    public let lvalue: LValueAST
    public var lwidth: Int = 1
    public let rvalue: ExprId
    public let delay: Double?
}
public struct SingleConcatAST {   // removed in this pass
    public let lvalue: LValueAST
    public let lwidth: Int = 1    // was `let`, AssgnAST's was `var`
    public let rvalue: ExprId
    public let delay: Double?
}
```

Both were genuinely instantiated — `AssgnAST` via `AssgnBlckYAML.toAST`
(continuous assign) and `SingleAssgnYAML.toAST` (one per element of a
procedural `AssgnStmntYAML.assgns` list), `SingleConcatAST` via
`SingleConcatYAML.toAST` (one per element of a `ConcatStmntYAML.concats`
list). **Fixed in this pass**: `SingleConcatAST` was deleted;
`ConcatStmntAST.concats` now holds `[AssgnAST]` directly, and
`SingleConcatYAML.toAST` constructs an `AssgnAST`. `assgnst`/`concatst`
were kept as two separate `StmntAST` cases, since they still represent a
meaningfully different statement shape (one target vs. an explicit list of
targets) even after the underlying per-part struct was unified.

### The `genAssignStmt` dropped-lvalue bug (fixed)

The codegen consumer of `.assgnst` was `genAssignStmt`
(`Compile.swift:1010-1024`). Before this pass, it only handled
`LValueAST.net`:

```swift
if case .net(let nd_nm) = ast.lvalue {
    ctx.code.append(Instruction(op: .storeSignal(nd_nm)))
} else {
    print("Not a net name")   // bitSelect/partSelect/indexedPartSelect/concat: silently emits nothing
}
```

Any procedural assignment whose target was a bit-select, part-select,
indexed-part-select, or concat would silently produce no bytecode at all.
By contrast, `.concatst`'s consumer, `genConcatStmt`
(`Compile.swift:1104-1111`), and the continuous-assign consumer,
`genAssgnStmtCode` (`Compile.swift:853-868`, used via `generateAssignBlock`),
both handle every lvalue kind correctly — `genAssgnStmtCode` does so by
emitting a generic `.assgn(lvalue, delay)` opcode that the VM executes via
`setLeftNet` (`Sim.swift:1255-1300`), which switches on every `LValueAST`
case.

**Fixed in this pass**: `genAssignStmt` now mirrors `genAssgnStmtCode` —
it emits the same `.assgn(lvalue, delay)` opcode instead of a
net-only special case, so it now correctly supports every lvalue kind via
the already-proven `setLeftNet` path, rather than adding a third
independent (and error-prone) implementation of lvalue dispatch.

Note for future readers: as of this writing, **no YAML file anywhere in
`Resources/CircuitLib` actually uses `kind: assgnst` or `kind: concatst`**
(both are procedural-statement kinds; every procedural assignment in the
current circuit library is written using `kind: blckst`/`noblckst`
instead, i.e. plain blocking/non-blocking assignment statements, whose
codegen — `genBlockStmtCode`/`genNonBlockStmtCode` — was never affected by
this bug). So this was a live, real defect, but not one that has been
silently corrupting any circuit in the current library; it's now fixed
regardless, and a regression test (see Verification below) exercises the
previously-broken path directly.

### Slice/select expression representation

There is no dedicated slice/bit-select case in `Expr`/`ExprYAML` — every
bit access, part-select, and identifier-with-bounds funnels into one case:

```swift
case select(name: String, args: [ExprId])     // Expr
case select(name: String, args: [ExprYAML])   // ExprYAML
```

The YAML `kind` tags `bit`, `slice`, and `ident` (when `ident` carries a
non-empty `sgmnts` list) all decode into `.select` (`CircuitParse.swift:
157-208`). A single-index bit access (`ADDR1R_[3]`) is normalized to a
duplicated two-argument form (`[3, 3]`) at intern time
(`CircuitParse.swift:472-476`, in `ExprYAML.toExprId`), so every downstream
consumer of `Expr.select` can assume a uniform `(msb, lsb)` two-arg shape.

### The `kind: concat` mis-decode in `ExprYAML` (fixed)

`ExprYAML` has its own proper `.concat(args: [ExprYAML])` case (used, for
example, by `RValueYAML`'s handling of an `rvalue: { concats: [...] }`
block — see `M1M_QDACCUM5.yml:830-898` above, which is the common,
correctly-working shape for a concatenated RHS). Separately, `ExprYAML`'s
own YAML `Kind` enum also declares a `.concat` tag
(`kind: concat` with sibling keys `name:` + `concats:`), whose decode body
was:

```swift
case .concat:
    let name  = try c.decode(String.self, forKey: .name)
    let concats = try c.decode([ExprYAML].self, forKey: .concats)
    self = .select(name: name, args: concats)   // wrong: builds a .select, not a .concat
```

This looks like a copy/paste error — it silently produced a `.select`
expression carrying the concatenated parts as its `args`, instead of a
`.concat` expression. **Investigated and fixed in this pass.** A repo-wide
search confirmed this exact shape (`kind: concat` at the `ExprYAML` level,
i.e. inside an expression position, together with a `name:` key) does not
occur anywhere in `Resources/CircuitLib` today — every real `kind: concat`
occurrence in the library (28 files) is a `PortNodeYAML` value inside an
`instance`'s `ports:` list (a structural gate/port-wiring context, decoded
by a separate, unrelated, and already-correct decoder,
`CircuitParse.swift:847-934`), and every real *expression*-level concat
uses the untagged `{ concats: [...] }` shape handled directly by
`RValueYAML`. So this bug was unreachable with current data — but it was
still wrong, and trivial to fix correctly:

```swift
case .concat:
    let concats = try c.decode([ExprYAML].self, forKey: .concats)
    self = .concat(args: concats)
```

### The tree-walking `.select` evaluator bug (fixed)

There are two independent evaluators for expressions, and — before this
pass — they disagreed about `.select`:

- **Bytecode/VM path** (used for continuous assigns and, via
  `genBlockStmtCode`/`genNonBlockStmtCode`, for `blckst`/`noblckst`
  statements): `genExpr`'s `.select` case (`Compile.swift:924-929`) emits
  a `.select(name, argCount)` opcode, executed by the VM
  (`Sim.swift:1351-1372`) via `ctx.getSelect(name, msb:, lsb:)` — correct.
- **Tree-walking interpreter path** (used by `evalStmt`/`doBlcklUpd`/
  `doNoBlcklUpd` for statements reached via `.ifst`/`.whlst`/`.casest`
  bodies): `evalExpr`'s `.select` case (`Compile.swift:247-249`) instead
  called `ctx.syscall("select_\(name)", args:)`. `Context.syscall`
  (`Sim.swift:766-778`) has no `"select_"`-prefixed case and falls through
  to `default: return .int(-1)` — **any slice read evaluated through this
  path silently returned `-1`** instead of the correct bits.

**Fixed in this pass**: `evalExpr`'s `.select` case now evaluates its two
arguments (`msb`, `lsb`) and calls `ctx.getSelect(name, msb:, lsb:)`
directly, matching the VM path's already-correct behavior, instead of
round-tripping through the syscall dispatcher.

### Write-side duplication (fixed in a later cleanup pass) and the `genConcatStmt` stack-discipline bug (fixed)

Writing to a slice/concat lvalue used to be implemented in two parallel,
near-identical functions: `assignToLValue` (`Sim.swift`, used by the
tree-walking interpreter and by `genConcatStmt`) and `setLeftNet`
(`Sim.swift`, used by the VM's `.assgn`/`.blckAssign`/`.noblckAssign`
opcodes). Both switched on every `LValueAST` case and did essentially the
same bit-masking arithmetic against real circuit nodes
(`ctx.circ!.setNode(...)`), and both were already correct — the duplication
was in the arithmetic, not a bug.

There was a plain-text, non-compiled design note in the repository,
`Sources/TwosCmplt/Compose` (since deleted), that was worth understanding
but was **not** a description of this duplication — it quoted an older,
already-superseded version of `assignToLValue` that wrote into
`ctx.vars: [String: Value]` instead of a real circuit node. That was a
legitimate concern about *that* older code, already resolved by the time
this investigation started; `Compose` was deleted once this distinction was
captured here, since its concern no longer applies to any current code.

**Fixed**: the duplicated per-case bit-masking arithmetic (`.bitSelect`/
`.partSelect`/`.indexedPartSelect`) was extracted into one shared private
helper, `applySliceWrite(_:val:updTm:ctx:)` (`Sim.swift`), which both
`assignToLValue` and `setLeftNet` now call. The two public functions kept
their own distinct contracts rather than being forced into one signature —
`assignToLValue` takes an absolute timestamp and also advances
`ctx.simTime` as a side effect (used by the tree-walking interpreter and
scheduled-update processing); `setLeftNet` takes an optional delay relative
to `ctx.simTime` (used by the VM's opcodes) and doesn't touch `ctx.simTime`
itself. Unifying those two contracts would have been a real behavior
change to core simulation timing, not a safe refactor, so only the
genuinely-identical arithmetic was consolidated.

A second, independent bug was found in `genConcatStmt` (`Compile.swift`),
the consumer of `.concatst`: it called `genExpr` (which only appends
`Instruction`s to `ctx.code` during code generation — it never pushes onto
`ctx.stack`, the array `Context.push`/`pop` operate on, which is only
meaningfully populated later during actual VM execution) and then
immediately called `ctx.pop()`, which had nothing to legitimately pop.
**Fixed**: `genConcatStmt` is now purely bytecode-emitting, mirroring
`genAssgnStmtCode`/`genAssignStmt` — it emits a `.assgn` opcode per part
instead of calling `assignToLValue` synchronously mid-codegen. As with
`assgnst`/`concatst` themselves, no YAML file in `Resources/CircuitLib`
currently uses `kind: concatst`, so this was a real, confirmed, but dormant
defect — a synthetic test (`testGenConcatStmtWritesAllParts`) exercises it
directly since no production circuit does.

## Part 2 — Evaluating the proposed slice/concat-gate algorithm

The following six-point algorithm was proposed (see `ClaudeInstructions.md`)
as a way to give bit-slices and concatenation a first-class, structural
presence in the simulated netlist, rather than being purely a parsing/VM
concept:

1. Each assignment statement is realized in a Circuit using a concat gate.
2. Each concat gate has a single multi-bit output port.
3. The output of a concat gate goes to a simple node connected directly to
   one or more component input ports.
4. The input ports of concat gates come from `.slice` nodes; each input
   port comes from one `.slice` node.
5. The sum of the bit counts of all the `.slice` nodes must equal the bit
   count of the `.simple` node connected to the concat output.
6. Each concat is an async gate, included in sorting, and ends up in
   `evalOrder`.

### Point-by-point evaluation against the current implementation

- **Points 1-3** already match the existing `.join` gate kind
  (`Gate.swift:158-171`): its `eval()` case loops over an arbitrary number
  of input nodes, shift-ORs each one in by its own bit width, and writes a
  single result to one output node — no truth table involved, and already
  arbitrary-width/arity (it's used with 3 and 4 inputs today in
  `Resources/CircuitLib/CNTR3.yml`/`CNTR4.yml`). No change to `.join`
  itself is needed to satisfy points 1-3.
- **Point 4 is not true today.** `.slice`-producing nodes exist (built via
  `addSeg`/`circSeg`, `CircuitIO.swift:24-60`, backed by the async `.seg`
  gate kind) but they commonly feed directly into an ordinary gate's input
  — `inPort2Indxs`'s `.bus` case (`CircuitIO.swift:62-102`) mixes
  `addSeg`-produced slice-node indices straight into a flat `inps` array
  used by whatever ordinary gate the port belongs to. There is also no
  `Nod.kind` field at all today — the `NdKind` enum (`.simple`/`.slice`,
  `Circuit.swift:126-129`) that this proposal's vocabulary matches is
  declared but completely unused anywhere in the codebase. Making point 4
  true is genuinely new work, not a bug fix.
- **Point 5** is a simple, cheap invariant to assert wherever a concat
  gate's `inps` list is assembled — not implemented yet since it depends on
  point 4 existing first.
- **Point 6 is already true.** `initializeCmpCnts`/`sortCmpRefs`
  (`Circuit.swift:431-613`) never special-case `.join` or `.seg` — they get
  an ordinary `CmpRef(kind: .aCirc, ...)`, are ref-counted like any other
  async gate, and are evaluated in the normal `evalOrder` loop. The
  scheduler needs no changes to support this proposal.

### Comparison with other simulators, and a recommendation

Mainstream Verilog tools (Icarus Verilog, Verilator) generally do **not**
reify every bit-select/concat as its own structural cell in the general
case — a purely combinational, constant-indexed `{a, b[3:0], c}` is
typically folded into one expression-level "select-and-merge" operation at
compile time, since (from a synthesis/simulation-performance point of
view) a plain value-level bit manipulation has no observable timing
difference from a physical concat cell, and reifying one for every small
select would explode gate/node counts for circuits like
`M1M_QDACCUM5` (sixteen single-bit selects in one assignment).

That comparison, however, is optimizing for a different goal than this
project has. This simulator's central purpose is exposing a real,
waveform-inspectable structural netlist (VCD output via
`Glbls.nodeChngs`) — being able to individually name and probe a slice
node in a waveform viewer has direct value here that a synthesis-focused
tool's compiler pass doesn't care about. **Recommendation: adopt the
proposed algorithm**, scoped specifically to Verilog-derived assignment
statements, where there is a real gap to close today — those statements
currently produce **no netlist-level representation of concatenation at
all**. Concatenation there is purely a bytecode-VM value operation
(`TwoCmplt.joinBts`, driving the `.concat` opcode, `Sim.swift` ~1290+),
invisible to VCD output and to anything that walks the structural netlist.
The existing gate-level `.join` mechanism (used today only by the native,
non-Verilog `CNTR3.yml`/`CNTR4.yml`-style circuit YAML) is exactly the
right building block to reuse for this — it should remain a single,
separate mechanism from the VM-internal `joinBts` path, not be merged with
it; the two serve different layers (structural netlist vs. procedural
expression evaluation) and conflating them would be a mistake.

One open design question this document originally surfaced without
resolving: should **every** slice always get its own concat gate, even when
a port is fed by exactly one slice (the literal reading of point 4), or only
when a port's connection is a genuine concatenation of two or more slices
(avoiding a degenerate one-input "concat" gate for the common single-bit-
select case)? **Resolved: the latter ("Option B").** A port fed by exactly
one slice wires that slice directly, with no gate in between; a port fed by
two or more slices gets a real `.join` gate concatenating them.

## Part 3 — What was actually implemented, and what wasn't

Two follow-up investigations narrowed Part 2's recommendation further
before any code was written:

- **Verilog-derived circuits were excluded from this work entirely.**
  Making Verilog-derived `assign`/`always` bodies produce real structural
  nodes/gates would require inventing a new structural execution model for
  that whole subsystem — today, *nothing* about their behavior is
  structural (not just concatenation; every expression, binary op, and
  conditional is opaque bytecode run by the VM each timestep, invisible to
  `evalOrder`). That's a much larger project than "add slice/concat gates,"
  so it was deliberately left out of scope. Only the native gate-level
  format (`kind: subcirc` YAML, built via `Circuit.make`/`MakeCircuit` in
  `CircuitIO.swift`) has any structural representation to retrofit at all.
- **The native format's own scope is very small.** Only three files in the
  entire circuit library use `kind: subcirc`: `CNTR3.yml`, `CNTR4.yml`, and
  `JKFF.yml` — and none of them use bit-slices in their gate `inPrts:`, only
  whole-node references. So this work has **zero observable effect on any
  circuit that exists today**; it's forward-looking correctness work for a
  code path that's real and reachable (`inPort2Indxs`'s `.segmented` case,
  `CircuitIO.swift:62-102`) but currently dead.

What was implemented, in `CircuitIO.swift`/`Node.swift`/`Circuit.swift`:

- `Nod` (`Node.swift`) gained a real `kind: NdKind` field (default
  `.simple`), reviving the previously-dead `NdKind` enum
  (`Circuit.swift:126-129`).
- `addSeg`/`circSeg` (`CircuitIO.swift`) now tag the slice node they produce
  `.kind = .slice`, and — two latent bugs found while touching this code —
  now correctly set that node's `nodeDrvr` and its source node's
  `nodeSinks`, and now register the new node's name in `circuit.nodeLU`.
  Previously neither the driver/sink edges nor the `nodeLU` entry were set
  at all: since `initializeCmpCnts` (`Circuit.swift:558-561`) skips
  ref-counting through a node whose driver is `.none`, nothing reading a
  slice node was ever told it must wait for the `.seg` gate that produces
  it; and since `Gate.eval()`'s `.seg`/`.join` cases write their output via
  the name-based `circuit.setNode(name:...)`, a node missing from `nodeLU`
  would silently fail to update at all (`setNode` prints a warning and
  no-ops on an unknown name) — the slice/join node's value would have stuck
  at its initial `0` forever. Both were genuine, if currently unexercised,
  correctness hazards, caught by the new tests below.
- A new helper, `addJoin(segIndices:circuit:)`, synthesizes a real `.join`
  gate plus a `.simple`-kind output node whenever `inPort2Indxs`'s
  `.segmented` case sees ≥2 segments that need concatenating — the output
  node's `nbits` is the sum of the inputs' `nbits` by construction,
  satisfying point 5 of the algorithm, and it registers the output node in
  `nodeLU` the same way. `.bus`'s `.bit`/`.slc` sub-cases were left
  unchanged: each element there already maps 1:1 to one input slot of the
  *enclosing* gate (this is exactly how `.join`-kind gates like `CNTR3`'s
  already declare real concatenation, e.g. `inPrts: [Q2, Q1, Q0]`), so no
  gate-insertion logic was needed there.
- No changes were needed to `Circuit.swift`'s Kahn's-algorithm sort — a gate
  appended to `circuit.aCircs` with correct `nodeDrvr`/`nodeSinks` is picked
  up generically by `makeCmpRefs`/`initializeCmpCnts`, exactly like any
  other gate.
- A third, more serious bug was found once the above made it possible to
  actually exercise a `.seg` gate for the first time: `Gate.eval()`'s
  `.seg` case (`Gate.swift`) never read `self.seg` (the stored `(msb, lsb)`
  range) at all — it looped over the *source* node's full bit width and
  rebuilt the output by reading bits `0, 1, 2, ...` in order, which
  bit-*reverses* the entire source value rather than extracting `[msb:lsb]`.
  A `.seg` gate never actually sliced anything. **Fixed**: it now computes
  `nd.selBits(n1: msb, n2: lsb).value`, reusing the same correct,
  already-used-elsewhere `TwoCmplt.selBits` helper (`SharedTypes/
  TwoCmplt.swift:241-248`) that `Sim.swift`'s `extractSlice` also uses. This
  bug was caught by a test with a genuine partial, asymmetric slice — a
  full-width "slice" (the only kind exercised while first writing this
  code) can't distinguish a reversal from a correct extraction, since
  reversing all of a node's bits and extracting all of a node's bits differ
  only when the requested range is a strict subset.

`PortDef.sgmnts`/`resolveCircPort`'s `.segmented` case — sub-circuit
*boundary* port wiring, a different layer from gate-level `inPrts:` — was
left untouched in this pass; it was already confirmed dead in Part 1's
investigation. (It was deleted in a later cleanup pass — see "Later cleanup
pass" below.)

## Verification

New tests were added under `Tests/TwosCmpltTests/` covering:
- The consolidated `AssgnAST` shape being produced consistently by all
  three of its construction call sites (continuous assign, procedural
  single-assign, procedural concat-assign).
- `genAssignStmt` now correctly emitting code for a bit-select lvalue
  (previously silently dropped).
- The tree-walking `.select` evaluator now agreeing with the VM path for
  the same slice read (previously returned `-1`).
- A `CNTR3`/`CNTR4` regression check (the only current users of the
  native-format `.join` gate) confirming the LogicLib YAML cleanup changed
  no simulated behavior.
- Synthetic (no real circuit exercises this path) coverage of `addSeg`'s
  `.slice` tagging and `nodeDrvr`/`nodeSinks` wiring, and of
  `inPort2Indxs`'s `.segmented` case under Option B: one segment wires
  directly with no new gate, two or more produce exactly one `.join` gate
  whose output is `.simple`-kind, correctly-sized, and evaluates to the
  correct concatenation.
- A regression check that `CNTR3`/`CNTR4`/`JKFF` — the only native-format
  circuits — still load and simulate identically.
- `testGenConcatStmtWritesAllParts`, exercising the fixed `genConcatStmt`
  end-to-end against a synthetic `ConcatStmntAST` (no production circuit
  uses `kind: concatst` today).

### Later cleanup pass

Alongside the above, several small, independently-diagnosed items were
resolved with no known live-production impact:
- `assignToLValue`/`setLeftNet` duplication reduced to one shared helper
  (`applySliceWrite`), as described above.
- `genConcatStmt`'s stack-discipline bug fixed, as described above.
- `PortDef.sgmnts` and `resolveCircPort`'s `.segmented` case
  (`Circuit.swift`) deleted — confirmed dead (written, never read), and the
  `PortDef` it used to produce (`node: "", nbits: 0, extlIndx: -1`) was
  never a usable value in the first place. Segmented sub-circuit-boundary
  port connections now fail loudly (`preconditionFailure`) instead of
  silently producing an inert `PortDef`.
- `setOutNd` (`Circuit.swift`) deleted — confirmed zero callers anywhere in
  the codebase. It mutated a local copy of a `Nod` read from
  `circ.parent!.nodes[...]` and never wrote it back (a classic Swift
  value-type bug), and called `saveChng` with the wrong circuit reference;
  neither defect had any effect since nothing ever called it. The actually-
  used output-propagation path is `Circuit.eval`'s own
  `self.parent!.setNode`/`setNodeBit` calls, which are correct and
  untouched.
- `Sources/TwosCmplt/Compose` deleted (see above).

## Part 4 — Kahn's-order scheduling for continuous assigns

Gate/instance scheduling (`kind: instance`/`subcircblck`/`asyncblck`/
`syncblck` entries inside a `kind: verilog` module) already used Kahn's
algorithm — `CircDef.toCircuit()` wires each instance's ports and
`makeCmpRefs`/`initializeCmpCnts`/`sortCmpRefs` build a real topological
`evalOrder` across sibling instances. Continuous `assign` statements did
not: they were compiled to bytecode (`CircDef.assgnBlcks`) and run
unconditionally, in raw declaration order, every timestep
(`runAllAssignBlcks`) — with no dependency ordering, and no relationship to
the `evalOrder` scheduler at all.

### What changed

- `Nod`/`Circuit` gained no new per-node representation, but `Circuit`
  gained `assgnBlkWrites: [[Int]]`/`assgnBlkReads: [[Int]]` — one entry per
  continuous-assign block, recording which nodes it writes and reads.
- `CmpType` gained a `.assgnBlk` case. `makeCmpRefs`, `getOutRefs`, and the
  `shw_ordr` debug helper (`Utilities.swift`) were updated for it.
- Two new pure functions in `Compile.swift`: `lvalueBaseNames(_:)` (like the
  existing `lvalueBaseName`, but decomposes a `.concat` lvalue into every
  node it writes instead of collapsing it to a placeholder) and
  `referencedNodeNames(_:in:)` (walks an `Expr` tree via `ExprId`s,
  collecting every `.node`/`.select` name referenced, recursing through
  `.binary`/`.unary`/`.gate`/`.cndtn`/`.syscall`/`.concat` args).
- `CircDef.toCircuit()` now has a wiring step, right after the existing
  instance-wiring loop and before `gateSlots()`, that walks `self.behav`'s
  `.assgnblck` entries (not `circDef.assgnBlcks`, which isn't populated
  until `self.Compile(circ)` runs later in the same function — a
  sequencing constraint that had to be worked around, not reordered, since
  `Compile()` also populates `alwaysStates`/`initStates`), computes each
  one's write/read node sets via the two functions above, and wires
  `nodeDrvr`/`nodeSinks` exactly like the existing `aCircs`-wiring loop
  does for ordinary gates. The `.assgnBlk` index assigned is "the Nth
  `.assgnblck` encountered in `self.behav`" — confirmed to match
  `copyBehav()`'s later population of `circDef.assgnBlcks` (a simple
  append-in-encounter-order, always correct regardless of interleaving with
  other behav-block kinds).
- `runAllAssignBlcks` was replaced by `runAssignBlck(_:ctx:)`, which runs
  one indexed assign block's compiled code. `Circuit.eval()`'s two
  `evalOrder` dispatch loops gained a `.assgnBlk` case: the async branch
  calls `runAssignBlck`; the sync branch is a no-op (continuous assigns are
  combinational, like `.aCirc`, not re-evaluated on the sync pass). The
  four old unconditional call sites (`eval()` before the dispatch loop,
  `eval()` again after always-blocks fire, `simVrlgInits`, and a
  presumed-dead call in `simVrlgAlwys`) were all removed.

### A dormant, separate bug found along the way

`generateAllBlcks` (`Compile.swift`) computes a `typeIdx` for writing
compiled bytecode into `circDef.assgnBlcks`/`initBlcks`/`alwaysBlcks` by
tracking *consecutive runs* of the same behav-block kind, not an overall
per-kind counter — it resets to 0 whenever the kind changes. If a module's
`behav_blcks` ever interleaved, say, `assign, instance, assign, assign`,
the second and third assigns would both compute `typeIdx == 0`/`1`
starting from the interleaved reset rather than continuing from the first
assign's `typeIdx`, misassigning compiled code into the wrong
`assgnBlcks[i]` slot. Checked all 203 `assign`-containing files in
`Resources/CircuitLib`: every one has at most two contiguous groups of
behav-block kinds (e.g. all instances then all assigns, or pure-assign-only)
— never true interleaving — so this is real but currently dormant. Not
fixed here (orthogonal to scheduling order); the new `.assgnBlk` wiring
avoids inheriting it by counting assign blocks the simple, always-correct
way `copyBehav()` does, not by copying `typeIdx`'s logic.

### The reactivity question, and why always-block-driven nodes need no special case

Continuous assigns are meant to react immediately to any input change,
including one an always-block just made in the same timestep. The old
"run every assign again after always-blocks fire" call existed to
approximate this. Kahn's-order dispatch has no equivalent mechanism —
each component runs once, at its sorted position — so simply deleting that
second run risked silently dropping reactivity for an assign depending on
an always-block's output.

It turns out no special-casing was needed: a node is only ever given a
structural `nodeDrvr` during build-time wiring (native gates, instance
ports, `addSeg`/`addJoin`, and now assign blocks) — `setNode`, which is
what an always-block's procedural writes go through at simulation time,
never sets `nodeDrvr`. So a node written only by an always-block already
has `nodeDrvr == .none`, and `initializeCmpCnts` already skips creating a
dependency edge for `.none`-driven nodes (the same skip it already applies
to `.iPrt`- and sync-driven nodes). An assign reading such a node simply
isn't blocked by it — it runs at its own Kahn-sorted position and reads
whatever value is currently there, "stale until next trigger," exactly
matching how sync/register dependencies are already treated elsewhere.
This is a deliberate, user-confirmed semantic choice, not an accident of
the implementation.

### Verified regression-free

`MULT_25P125.yml` (`Resources/CircuitLib`) has three real continuous
assigns with a genuine dependency — `OUT` reads `sum`, which an earlier
assign writes. Confirmed via `AssignSchedulingTests.testRealCircuitAssignsScheduledInDependencyOrder`
that the `sum`-writing
assign is scheduled before the `OUT`-writing one. `TST_ACCUM3` (which
instantiates `M1M_QDACCUM5`, the circuit with the 16-bit-concat-of-selects
continuous assign cited in Part 1) was run end-to-end before and after this
change (by temporarily stashing the `Circuit.swift`/`CircDef.swift`
scheduling changes and re-running) and produced byte-for-byte identical
results — `QD_` ends at value `0x30000`, `updTm=12`, in both cases. This is
now a permanent regression test, `TSTACCUM3RegressionTest`.

`QD_DDFS5`/`Sine5` (the circuit behind the still-open `FINE[7:0]`
investigation) has **no** continuous assigns at all — its entire
`COS_LU5`/`SIN_LU5` pipeline is built from structural instances — so this
phase has no bearing on that investigation either way; confirmed its test
output is byte-for-byte unchanged.
