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
| B1 InputLanguage, B2 SUCC/NULL, B3 BITES, B4 disjointness diagnostics | done, report-only (no codegen change) | `docs/BITES.md`, `src/npegged/{language,bites}.d`, `tests/prefix_discrimination.d` |
| B5 NEXTBITES + Prop. 10-13 premises, B6 commit-site candidates, B7 regular SUCC (opt-in, +2 pairs/+60% time), B8 unified diagnostics | done, report-only (no codegen change) | `docs/BITES.md`, `tests/{next_bites,diagnostics}.d`, `milestones/B7/` |
| L1 conversion contract, L2 certified EBNF export (254k-string corpus check) | done, report-only | `docs/LL.md`, `tests/{ll_regions,ll_export}.d` |
| L3 `ll1` backend (opt-in, exact, no gain) | done | `milestones/L3-ll1/notes-l3.md`, differential fixtures |
| **Finding: `direct` backend beats default combinators** (79/171 vs 60/171 within 1.5x, geomean 1.48 vs 1.62) | recorded | `milestones/L3-direct` |
| **New baseline on `direct`** | 78/171 within 1.5x, geomean 1.47 | `baselines/20261019T224838Z-*` |
| **S1 register-resident step accounting in cursors** (exact; dense differential sweeps) | 96/171 within 1.5x (56%), p90 2.04, geomean 1.32; 10 PEGGrammar regressions <= 12% disclosed | `milestones/S1/notes-s1.md`, S1b alternative |
| G1 seeded candidate generator, G2 full-acceptance oracle | done (cold modules, no codegen change) | `docs/GENERATION.md`, `tests/{generator,acceptance_oracle}.d` |
| G3 coverage-guided generation (76/80 vs 57/80 targets at 12 samples), G4 external weighted policies | done (cold modules) | `docs/GENERATION.md`, `tests/{coverage_generation,policy_generation}.d` |
| G5 weight learning from corpora | done (marginal model, holdout comparison) | `tests/learning.d` |
| G6 mutation/differential fuzzing/shrinking, regression seeds | done; combinators vs direct agree over 1500+ inputs | `tests/fuzz_differential.d`, `tests/regression/` |
| G7 reproducible corpora (json/arithmetic/csv; real + synthetic + learned + adversarial; manifest) | done; **not yet wired into the timing runner** | `performance/corpora/`, `tests/corpus_generation.d`, `tests/test_corpora.py` |
| S2b rule-call tick from register counter (direct) | 99/171 within 1.5x (58%), p90 2.04, geomean 1.32; no regression vs S1 | `milestones/S2b`; S2 threshold heuristic rejected (`milestones/S2`) |
| P3-P5, P7-P8, L4-L6, X* | not started | — |

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

## Phase 2

- Q1 implemented: `benchmark/entry_ladder.d`, `performance/scripts/entry_ladder.py`,
  `tests/test_entry_ladder.py`; 21 samples/layer on empty and one-byte fixtures.
  See `milestones/Q1/notes.md` for measured costs and validation limitations.
- Next in the roadmap's recommended order: S3, then S8.
