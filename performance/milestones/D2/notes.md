# D2 — Work-unit contract: coarser model (maintainer-approved), implemented on all backends

Decision: the maintainer chose "Allow coarser" on 2026-10-20. The contract is `docs/WORK_UNITS.md` (model v2): units for rule
calls, repetition attempts and DFA scanners; terminals, sequences, choices and lookaheads are free but observe the status.
This also closes S6 (slack-guarded tick regions) as superseded: there are no per-node ticks left to guard.

Ceilings first (unsound experiments; raw data `ceiling-tick-*` and `ceiling-depth-*`, baseline = Q2 runner):
- all cursor ticks reduced to `_live`: validation -16..-22% on PEGGrammar/Arithmetic, CSV.MultiLine/spans -16%
  (Arithmetic spans/tree were +8..+16% in that experiment: an inlining effect, see below);
- depth check removed from `recognizeRuleTicked`: -4..-10% on rule-heavy validation (S5/W3 candidate).

Implementation:
- `src/npegged/peg.d`: `State.alive()`; terminals (`any`, `literal`, `charRange`, `charClass`, `caseInsensitiveLiteral`),
  `and`, `predictiveChoice`, `predictiveNot` use it instead of `tick()`; every `byteSteps` is 0 (byte fast paths only pay the
  repetition attempt). `recognizeRecordedRule` gains a `Ticked` mode and a cheaper `-2` (no own record) transaction.
- `src/npegged/grammar.d`: cursors test `_live` instead of `_tick()` at fine-grained sites; L3 guard replays no ticks;
  records-mode calls of record-free rules (`-3L`) use the register tick (`recognizeRuleTicked`) like validation;
  `emptyCostThreshold` 1; cursors without ticks but with >= 4 liveness tests keep the counters in registers.
- `tests/eligibility_sources.json` golden hashes refreshed (generated direct sources changed; combinator sources did not).
- Unit tests updated to the new model (they now assert that terminals are free and fail once a limit has fired); new tests for
  `recognizeRecordedRule` (`-2` rollback, `Ticked`).

Verification: A4 differential (both backends, all memo policies, dense step 0..80 / depth / memory / output limit sweeps,
recognition/borrowed/owned/tree) passes; 24-module unit tests pass; scripts/build.sh (unit + integration + examples, LDC)
passes; entry/shared-records/rule-effects/prefix-discrimination/phrase-cache/recursive-ascent/active-fixtures/
empty-scanner/scanner-report/eligibility checks pass on LDC (macOS shims for `prlimit`, `mapfile`, `ulimit -v`: memory caps are
NOT enforced for those runs). DMD, ASan/LSan, Valgrind, coverage tooling: not run (DMD segfaults here; others unavailable).

Benchmarks (Apple M1, LDC 1.43, direct backend, validation/spans/tree for CSV, PEGGrammar, Arithmetic, Numbers; 3 interleaved
repetitions x 9 samples x 20000; baseline = Q2 runner, i.e. S4+O2+O3 without D2): `o1_q2_runner-*` vs `o1_d2_runner-*`.
Validation: Arithmetic -11..-14%, PEGGrammar -10..-11%; spans: Arithmetic -11..-15%, PEGGrammar.ManyRules -12%,
CSV.Flat -10%; median over 132 workload/mode pairs -1.8%. Reproducible regressions (4 alternating reruns, disclosed):
Arithmetic.Flat/tree +5.5% (23.2 -> 24.5 us), PEGGrammar.Permissive/spans +5.3% (146 -> 153 ns), CSV.Empty/spans +4% (68 -> 71 ns).
Note: the first D2 build made Arithmetic spans/tree 10-20% SLOWER although the cursor code only lost work; the cause was
inlining/layout in records mode (nm/sample show the hot split moving between `_Root` and `recognizeRule!_cursor_Primary`). The
record-free `-3L` register tick and the lean `-2` transaction recovered it. Layout sensitivity is real: treat +-5% on single
records workloads as noise-adjacent.
