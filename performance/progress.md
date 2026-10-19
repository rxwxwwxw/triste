Last updated 2026-10-19.

| Milestone | State | Evidence |
|---|---|---|
| A1 harness + LDC baseline | done | `baselines/20261019T204823Z-9bba1f268` |
| P6 (state-code DFA scanner, <=48 states) | done, enabled by default | `milestones/P6{a,b,c,d}`; P6d is the final form |
| F1 (neverFails/neverAdvances proofs), F2 (FOLLOW), F3 (conflict diagnostics) | done, report-only (no codegen change) | `docs/ANALYSIS_FACTS.md`, analysis.d/tests/prefix_discrimination.d |
| A2 per-rule counters (instrumented build) | done | `tests/rule_metrics.d`, `milestones/A2/` |
| A3 strategy fields in eligibility report | done | `tests/eligibility_report.d`, grammar.d unittest |
| A4 differential gate (portable script, DFA string fixtures, `performance/scripts/run.sh`) | done | `scripts/differential.sh` |
| A5 size/compile accounting | done | `performance/size/` |
| F4 literalChoice2 (opt-in `NPeggedFirst2`) | done, **off by default** (1.75x faster on one case, 14% slower on another) | `milestones/F4/` |
| P1 pure islands | verified, no measured gain, stays opt-in | `milestones/P1/` |
| P2 literal-root direct lowering | done, parity, no measured gain | `milestones/P2/` |
| B*, P3-P5, P7-P8, L*, G*, X* | not started | — |

P6 result (LDC, vs baseline): within 1.5x 53 -> 59 of 171, geomean 1.81 -> 1.62, JSON.EscapeHeavy 4.9x -> ~1.4x,
CSV.Flat/validation -73%. Remaining >5% slowdowns: Numbers.BinaryLong/validation +5.2%,
JSON.InvalidTruncated/validation +5.0% (borderline noise). P6a/P6b/P6c are kept as superseded runs.

Not run: DMD (this host's `dmd` segfaults, including `dmd --version` and on the unmodified baseline), ASan/LSan,
Valgrind, coverage tooling (`scripts/coverage.sh` needs GDC). `-vgc` on dfa.d adds only CTFE-time lines.
Largest outstanding gaps are listed in the latest summary.csv (PEGGrammar.Permissive, Arithmetic.Flat/Unary).

## Findings for the next session

- Remaining gap is mostly fixed per-node overhead, not scanning. Experiment (not committed, unsound): replacing
  `State.tick()` with `return true` moved Arithmetic/validation from ~3.1x to ~2.2x, so step accounting is only
  ~30% of the gap and the rest is status checks, rule-boundary (`recognizeRule`) and failure bookkeeping. A sound
  "slack fast path" (batch ticks when `steps + maxTicks < stepLimit`) can recover at most part of that 30%.
- Worth trying next: P1 (per-rule effects in mixed grammars), P2 (direct lowering for `root-combinator` rules,
  e.g. JSON.True/False/Null/Number/Spacing), A5 (compile/size accounting), then F1-F3 before any B work.
