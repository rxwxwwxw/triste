# Q1 — fixed entry cost ladder

Run `python3 performance/scripts/entry_ladder.py` from the repository. The second
retained run has the canonical raw schema; the initial exploratory run retains
its original layer-oriented CSV. Both contain all 21 samples after 3 warmup
blocks, each measuring one million calls. Layer order rotates per block.

The grammar accepts empty input or exactly `a`. Each rung returns the same
validation-mode `Observation` as `check!entry`, verified before timing. The floor
is an empty function returning an accepted observation; it is applicable only to
these valid fixtures. Colocated tests also exercise `b`, `aa`, embedded NUL and
mutated hash/status negative controls. A failed observation comparison aborts
before timing. This measures the existing validation observation contract; it
makes no claim of identical work units or diagnostic positions for lower rungs.

Layers are floor, handwritten validation, CheckResult/Arena lifetime, State and
ParseContext setup, rule/ruleBody with the primitive body, defined/DFA wrapper
inside that rule, and public check. DFA is an alternative body, not an additional
cost on top of the primitive body. All calls include common dynamic rung dispatch,
opaque-input and checksum overhead. Construction is measured as optimized by the
release compiler, including permitted dead-store elimination. Timings are local
microbenchmark costs, not estimates of arbitrary grammar performance.

On the initial run full check cost 17.24/17.19 ns (empty/one-byte), handwritten
3.55/3.56 ns, result/arena 5.76/5.81 ns, state/context 10.83/10.92 ns and
rule/body 17.52/17.12 ns. The floor measured 3.75/3.78 ns, slightly above the
handwritten rung: floor-subtracted ratios are explicitly N/A when the denominator
is nonpositive. Raw ratios remain untouched. No gate threshold or baseline changed.
This limits attribution precision at the sub-nanosecond scale. Setup and the rule
boundary are measurable targets for S3; no speedup is claimed by Q1.

Validation:
- LDC and DMD: focused debug unit executables each passed 8 modules, including
  two new colocated blocks (valid/rejected fixtures and negative controls).
- `python3 tests/test_entry_ladder.py`: bounded cross-module runner passed.
- `dfmt -i benchmark/entry_ladder.d`: formatted.
- `ldc2 -c -vgc`: only the three CTFE automaton array literals were diagnosed;
  no runtime GC allocation; the complete harness is @nogc nothrow.
- LDC ASan/LSan: focused unit executable passed outside sandbox tracing with
  `ASAN_OPTIONS=detect_leaks=1 timeout --kill-after=2s 60s build/Q1/tests-asan --DRT-testmode=test-only`.
  The sandboxed attempt passed tests but LSan could not inspect threads.
- Valgrind: not run successfully; startup requires loader memcmp debug symbols.
  Trying the cached matching build-id debug file did not resolve startup.
- Coverage: N/A for new benchmark/test/script files; no src module changed.
- A4: see final validation entry below.

Existing 171-workload results, p90, within-target count and trends are unchanged:
this is an added diagnostic benchmark, with no parser implementation change.
Generation/native compile/RSS deltas against an earlier ladder are N/A (new
harness). Exact compiler command and source checksums are in each metadata.json.
DMD now runs on this host; historical DMD failures in the Phase 1 ledger do not
apply to this new focused run.

A4 final validation: `DC=ldc2 bash scripts/differential.sh` passed 25 modules,
including existing dense step/depth/output-limit sweeps. These validate unchanged
parser behavior; the ladder's own parity checks cover the new diagnostic harness.

Pre-commit repair: H01's `tests/eligibility_sources.json` was last refreshed at
ac5f3cc, before the completed Phase 1 codegen changes. With src unchanged from
c667f015f5, 18/72 snapshots (direct backend only) differed. Regenerated them using
`COMPILERS=ldc2 BASELINE=1 bash scripts/eligibility-check.sh`; the ordinary checker
then passed all 72 reports, policy combinations and byte hashes. No production
code or checker assertion was changed to accommodate this pre-existing drift.
