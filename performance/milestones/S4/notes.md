# S4 — Scanner calls native to the cursor — COMPLETE (exact; default on)

Change: `dfaToken.cursor` (src/npegged/dfa.d) takes the cursor's `_steps`/`_live` by `ref`; direct-backend
cursors call it instead of `s.steps = _steps; dfaToken(s,pos); _steps = s.steps; _live = ...`. A scan the table
settles charges exactly the `examined - pos + 1` units `opCall` charges, without touching `s.steps`/`s.status`;
every other outcome (state not ok, limit/depth edge, trace, unsettled scan, tree mode, metrics build, invalid
table, inner records) syncs and replays through `opCall`. `cursorShared` serves the shared-counter variant.
`pos <= input.length` is kept (cheap, safety over a micro-gain).

Tests: colocated unit sweep in dfa.d (step limit 0..8 x depth limit 0..3 x 5 inputs x all start offsets x
ReferenceDepth 0/2: end, failEnd, steps, live, status identical to `opCall`). A4 `scripts/differential.sh`
(dense step/depth/memory/output sweeps, both backends) passes on LDC. All 24 modules' unittests pass (LDC).
DMD: not run (segfaults on this host). Coverage tooling, ASan/LSan, Valgrind: not run for this milestone.

Benchmarks (Apple M1, LDC 1.43, direct backend, validation+spans; 3 interleaved repetitions of 9 samples x 20000,
median of repetitions; baseline runner = pre-S4 tree): raw JSON in this directory (`s8_base_runner-*` vs `s4_runner-*`).
- PEGGrammar spans: Empty -20.2%, Permissive -9.0%, Trailing -5.5%, Truncated -4.7%, Small -4.1%; Deep/validation -4.7%.
- CSV.Flat/spans +3.0%, CSV.MultiLine/spans +3.0%, Numbers.Binary/validation +3.5% (no reproducible >5% regression;
  these are disclosed). CSV records do not improve here: O1/O3 target them.
- Every other measured Numbers/CSV/Arithmetic/PEGGrammar case is within +-2%.
JSON was not part of the rerun (the runner's `--workloads` filter excludes it). Full 171-workload gate not rerun.
