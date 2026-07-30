# Bug: `decls` entries leak into `behav_blcks` for behavioral (assign-only) modules

## Symptom (Swift side)

Running `SimRun TST_ACCUM3` crashes while decoding `CircDef` for `DG_AND2_2X1`:

```
DecodingError.dataCorrupted / "Unknown behav_blcks kind: Input"
```
(surfaces as a Swift-error breakpoint stop in `YAMLDecoder.decode<CircDef>`, called from
`makeCircDef` at `Sources/TwosCmplt/CircDef.swift:197`, reached via
`TST_ACCUM3 → M1M_QDACCUM5 → CLA18 → DG_AND2_2X1`.)

`Sources/TwosCmplt/CircuitParse.swift:586-618` (`BehavBlckYAML.init(from:)`) only
recognizes these `kind` values inside `behav_blcks`:

```
specify, initial, always, assign, instance, subcirc, async, sync, gate, Reg, Integer
```

`Input` and `Output` are **not** valid `behav_blcks` kinds — they're `DeclYAML.kind`
values (`Sources/TwosCmplt/CircDef.swift:439-445`) and belong under `decls`, not
`behav_blcks`. Any `.yml` that puts an `Input`/`Output` entry inside `behav_blcks`
fails to decode.

## The malformed shape

`Resources/CircuitLib/DG_AND2_2X1.yml` (currently committed, broken):

```yaml
decls:
- null                     # <- decls is empty/absent; should hold the port decls
behav_blcks:
-   kind: assign
    lvalue: {kind: ident, name: OUT}
    rvalue: {kind: gt_expr, oper: 'BAnd:', args: [...]}
    delay: 11.5
-   kind: Input             # <- WRONG: belongs in decls
    name: A
    signed: 'False'
    width: [0, 0]
    length: []
-   kind: Input
    name: B
    ...
-   kind: Output
    name: OUT
    ...
```

The **correctly-formed** shape — e.g. `Resources/CircuitLib/dg_and2_2x1.yml` (same
gate, lowercase module name, still correct because it hasn't been regenerated
recently — see below):

```yaml
decls:
-   -   kind: Input
        name: a
        signed: 'False'
        width: [0, 0]
        length: []
    -   kind: Input
        name: b
        ...
    -   kind: Input
        name: vdd
        ...
    -   kind: Input
        name: vss
        ...
-   -   kind: Output
        name: out
        ...
behav_blcks:
-   kind: assign
    lvalue: {kind: ident, name: out}
    rvalue: {kind: gt_expr, oper: 'BAnd:', args: [...]}
    delay: 11.5
```

`decls` is `[[DeclYAML]]` — a list of *groups* of declarations (inputs grouped
together, outputs grouped together). `behav_blcks` should contain only the
behavioral statements (`assign`/`always`/`initial`/instances/gates) — never bare
port declarations.

## Scope — this is not a one-off

I scanned `Resources/CircuitLib/*.yml` for any `behav_blcks:` entry containing
`kind: Input|Output|Reg|Wire` and found **67 affected files**, essentially all of
them primitive digital-gate modules (`DG_*`) plus a handful of others:

```
DG_AND2_2X1.yml   DG_AND2_3X1.yml   DG_AND2_4X1.yml   DG_AND4_2X1.yml
DG_AND4_3X1.yml   DG_AND4_4X1.yml   DG_DER_3X2.yml    DG_DIFF_BFR.yml
DG_DRC_DIFF.yml   DG_DR_3X1.yml     DG_DR_3X2.yml     DG_DR_DIFF.yml
DG_DS_3X2.yml     DG_EMX_4X1.yml    DG_EXNOR1_2X1.yml DG_EXOR1_2X1.yml
DG_LTCHR_3X1.yml  DG_LTCHR_4X1.yml  DG_LTCHSN_4X1.yml DG_LTCHSN_5X1.yml
DG_LTCHS_3X1.yml  DG_LTCHS_4X1.yml  DG_MX1_3X1.yml    DG_MX2_3X1.yml
DG_MX4_3X1.yml    DG_MXN1_3X1.yml  DG_MXN2_3X1.yml    DG_MX_4X1.yml
DG_NABC_ABD.yml   DG_NAB_AC.yml    DG_NAB_AC_BC.yml   DG_NAB_C2.yml
DG_NAB_CDA_CDB.yml DG_NAC_AD_BC_BD.yml DG_NAND1_2X1.yml DG_NAND1_3X1.yml
DG_NAND1_4X1.yml  DG_NAND2_2X1.yml DG_NAND2_3X1.yml   DG_NAND2_4X1.yml
DG_NA_BC.yml      DG_NA_BCD.yml    DG_NA_BC_BD.yml    DG_NOR1_2X1.yml
DG_NOR1_3X1.yml   DG_NOR2_2X1.yml  DG_OR2_2X1.yml     DG_OR2_3X1.yml
DG_OR4_2X1.yml    DG_OR4_3X1.yml   DG_PRGT4.yml       DG_PRPA.yml
DG_PRPB.yml       DG_PRPF.yml      DG_RG_2X1.yml      DG_RG_3X1.yml
DG_S2DIFF_1X2.yml DG_SE2DIFF_1X2.yml DG_SNGL2DIFF_1X2.yml DG_TIHI.yml
DG_TILO.yml       FADDR_3X2.yml    HADDRA.yml         HADDRB.yml
HADDRC.yml        HADDR_2X2.yml    KM_EMX_4X1.yml
```

Every file in this list is uppercase-named. Most (but not all — `FADDR_3X2.yml`,
`HADDR_2X2.yml`, `HADDRA/B/C.yml` have none) have a **lowercase-named twin**
(`dg_and2_2x1.yml`, etc.) that is correctly formed. That's the key clue for
root-causing this:

## Root-cause evidence: this is a live regression, not stale output

Checked `git log` on the TwosCmplt side:

- `Resources/CircuitLib/DG_AND2_2X1.yml` was regenerated in commits
  `dbb0e9a` (2026-07-27) **and** `4b18509` (2026-07-30). `git diff dbb0e9a 4b18509 --
  Resources/CircuitLib/DG_AND2_2X1.yml` shows the file was **still correctly
  formed at `dbb0e9a`** (`decls` had two proper groups, `behav_blcks` had only the
  `assign` entry) and **broke exactly in the `4b18509` regeneration** — `decls`
  collapsed to `- null` and the five `Input`/`Output` entries were appended to
  `behav_blcks` instead.
- `Resources/CircuitLib/dg_and2_2x1.yml` (lowercase twin) hasn't been
  regenerated since `40e3feb` (2026-06-05) — it simply hasn't been re-run through
  the pipeline since before the regression, which is why it still looks correct
  on disk.

**So: the generation pipeline itself started producing this malformed shape
sometime between 2026-07-27 and 2026-07-30**, and every module that happened to
get regenerated in that window (mostly the `DG_*` uppercase primitives, likely
because `fix_circuit_params.py` — added 2026-07-28 — touched their Verilog
`circuit=` parameter and invalidated their cached pipeline artifacts) came out
broken. Modules that weren't reprocessed in that window still show old, correct
output.

## Where to look in `verilogParse`

I did not find a smoking-gun diff for the decls/behav_blcks split itself in that
window's commits, but two files are the right place to focus:

1. **`parse_mod.py`, `cnvrt_mdl()`, the `elif mod.get('behav_blcks') is not None:`
   branch (~line 496-504)**:

   ```python
   elif mod.get('behav_blcks') is not None:
       behav_blcks = mod['behav_blcks']
       for behav_elem in behav_blcks:
           if 'ports' not in behav_elem or 'module' not in behav_elem:
               if 'behav_blcks' not in unl_mdl:
                   unl_mdl['behav_blcks'] = [behav_elem]
               else:
                   unl_mdl['behav_blcks'].append(behav_elem)
               continue
           ...
   ```

   This copies *anything* in `mod['behav_blcks']` that isn't a sub-instance
   straight into `unl_mdl['behav_blcks']`, with no check for whether the entry
   is actually a decl (`kind: Input/Output/Reg/Wire`). Note also that
   `cnvrt_mdl()` never reads `mod['decls']` at all (grep confirms `decls` never
   appears in `parse_mod.py`) — the ast-level `decls` that `parse_ast.py`'s
   grammar populates (`p_module_def`/`p_module_def_fnc`, `decls: p[6]`) is
   silently dropped when building `unl_mdl`.

2. **`parse_unl.py`, `unl_to_mod()` (~line 435-462)** is what's supposed to
   reconstruct `decls` for the final `.mod`/`.yml` output:

   ```python
   mod = {
       ...
       'decls': (_decls_structural(unl_mod) if structural
                 else _decls_behavioral(unl_mod, port_names_set)),
   }
   ...
   mod['behav_blcks'] = unl_mod.get('behav_blcks')
   ```

   `_decls_behavioral()` (line 381-405) builds `decls` from `unl_mod['inPrts']`
   /`unl_mod['outPrts']`, grouping inputs and outputs into separate lists —
   this is the correct shape when it works. But `unl_mod['behav_blcks']` is
   passed through verbatim from whatever `cnvrt_mdl()` put there in step 1 — so
   if `cnvrt_mdl()` puts raw `Input`/`Output` decl entries into
   `unl_mdl['behav_blcks']` (as it does for purely-behavioral, assign-only
   modules — no `inPrts`/`outPrts` ever explicitly populated for that case
   either, hence `decls` also comes out empty/`[null]`), `unl_to_mod()` has
   nothing to catch it and the corruption passes straight through into the
   `.mod` file, and from there unchanged through `prepare_yml.py`'s text
   substitution into `Resources/CircuitLib/*.yml`.

**Hypothesis to verify:** for behavioral-only modules (no `components`, only
`behav_blcks` in the ast), `cnvrt_mdl()` never populates `unl_mdl['inPrts']`
/`unl_mdl['outPrts']` from the module's `io_ports`/`decls` — those lists stay
empty, so `_decls_behavioral()` in `parse_unl.py` has nothing to build `decls`
from later, and the raw ast-level `Input`/`Output` decl entries end up
surfacing only via the pass-through `behav_blcks` copy. Confirm by tracing
`cnvrt_mdl()` for a `kind: verilog` module whose ast has `decls` populated and
`behav_blcks = [{kind: assign, ...}]` (e.g. re-run `parse_mod.py` standalone on
`DG_AND2_2X1`'s `.ast`/`.mod` intermediate and inspect `unl_mdl['inPrts']`
/`unl_mdl['outPrts']`/`unl_mdl['behav_blcks']` right after the loop at line
496-504).

## Suggested fix

In `parse_mod.py`'s `cnvrt_mdl()`, when iterating `mod['behav_blcks']` in the
`elif mod.get('behav_blcks') is not None:` branch, entries with
`kind in ('Input', 'Output', 'Reg', 'Wire', 'Integer')` should be classified as
declarations (populate `unl_mdl['inPrts']`/`unl_mdl['outPrts']` the same way the
`components` branch above does via `parse_prts`, or otherwise route them so
`parse_unl.py`'s `_decls_behavioral()` picks them up) — not appended to
`unl_mdl['behav_blcks']`. Only true behavioral statements (`assign`, `always`,
`initial`, `specify`, `instance`/`subcirc`/`async`/`sync`, `gate`) belong in
`behav_blcks`.

## How to verify the fix

1. Regenerate `DG_AND2_2X1` (or any of the 67 affected modules) through the
   full pipeline and confirm the output `decls:` has proper `[[DeclYAML]]`
   groups and `behav_blcks:` contains only behavioral statements.
2. Re-run this scan from `Resources/CircuitLib/` in TwosCmplt — it should
   return zero matches once all affected files are regenerated:

   ```bash
   python3 - <<'EOF'
   import re, glob
   for fn in sorted(glob.glob('*.yml')):
       txt = open(fn, errors='replace').read()
       m = re.search(r'^behav_blcks:', txt, re.M)
       if not m:
           continue
       if re.search(r'-\s+kind:\s*(Input|Output|Reg|Wire)\b', txt[m.start():]):
           print(fn)
   EOF
   ```
3. `swift run SimRun TST_ACCUM3 Config.yaml` (or whatever config) should decode
   `DG_AND2_2X1` (and the other CLA18/M1M_QDACCUM5 dependencies) without
   hitting `DecodingError.dataCorrupted`.
