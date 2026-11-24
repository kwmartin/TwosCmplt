To be done. For now, have a look at <project_dir>/scripts

specify module in .vscode/launch.json where name is Debug SimRun. A working project is "args": ["QD_DDFS5", "Config.yaml"],

We are going to work on TST_ACCUM3

There is no run_sim executable in the TwosCmplt directory — the binary is named SimRun (no underscore). But yes, SimRun TST_ACCUM3 is exactly the right entry point for debugging this in VSCode.

Why SimRun is the right entry point

SimRun.swift follows a clean 4-step pipeline:

1. makeCircDef("TST_ACCUM3") — loads CircuitLib/TST_ACCUM3.yml and recursively resolves all sub-modules (CLA18, FADDR, AND, INV, etc.)
2. circDef.toCircuit() — converts the static definition into a runnable circuit graph; this is where the sync/async flags drive evaluation-order sorting and where the "Evaluation order not determined" crash we hit earlier originates
3. loadSpecs(...) — reads modules/TST_ACCUM3.yml for TimeSpcs, Clock, FinishTime
4. simCircuit(circuit, ...) — runs the actual event-driven / combinational simulation

Where to set breakpoints in VSCode

┌───────────────┬──────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────┐
│   Function    │        File (likely)         │                                  What to inspect                                   │
├───────────────┼──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ makeCircDef   │ CircDef.swift                │ Check that params["circuit"] is read correctly from every sub-module YAML          │
├───────────────┼──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ toCircuit()   │ CircDef.swift                │ Step through the evalOrder sort; look for the cmpRefs / initializeCmpCnts call     │
│               │                              │ that crashed when CLA modules were async                                           │
├───────────────┼──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ simCircuit    │ Circuit.swift                │ Step into the first time-step; watch how ADDR0R.A = 0x4000 and B = 0 propagate     │
│               │                              │ through the adder tree                                                             │
├───────────────┼──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ Gate          │ LogicLib/Faddr.yml or        │ Check if the truth-table lookup returns SUM = 1 for all inputs, or if only bit 0   │
│ evaluation    │ Circuit.swift                │ of the bus is being used                                                           │
└───────────────┴──────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────┘

A quick sanity check before you dive in

You can verify whether the bug is in circuit construction (step 2) or simulation execution (step 4) by running:

cd /home/Dropbox/programming/Swift/TwosCmplt
.build/debug/SimRun TST_ACCUM3 Config.yaml --rebuild

--rebuild stops after toCircuit() and saveDefMap() — it never calls simCircuit. If this succeeds without crash, the circuit graph builds correctly and the bug is in the simulator's event/combinational scheduler. If it crashes, the problem is earlier (eval-order sorting or module parameter resolution).

Summary

- Executable: .build/debug/SimRun (not run_sim)
- Command: SimRun TST_ACCUM3 Config.yaml --spec /home/martin/.xschem/modules/TST_ACCUM3.yml
- Entry point: SimRun.swift:50 (circDef.toCircuit())
- Key files: CircDef.swift, Circuit.swift, and the logic-gate evaluator

Go ahead and launch it in VSCode. If you find a suspicious value during toCircuit() or simCircuit(), paste the stack frame / variable here and I can help interpret it.
