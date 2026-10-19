# Performance dashboard

Generated from `performance/trends.csv`; do not edit by hand.

Latest run: `20261019T210601Z-07315cd94` (milestone:P6d, ldc2, commit 07315cd94)

- Workloads within 1.5x: 59/171 (34.5%)
- Slowdown p50/p90/p95: 1.81 / 2.90 / 3.14
- Geometric mean: 1.62x
- Worst: 4.08x (handwritten-workloads/PEGGrammar.Permissive/validation)

Delta vs previous run `20261019T210324Z-07315cd94`: within-target +1, p90 +0.03, geomean -0.02

## History

| run | kind | compiler | within target | p90 | geomean | worst |
|---|---|---|---|---|---|---|
| 20261019T204823Z-9bba1f268 | baseline | ldc2 | 53/171 | 3.16 | 1.81 | 4.88 |
| 20261019T205844Z-07315cd94 | milestone:P6a | ldc2 | 60/171 | 2.89 | 1.61 | 4.07 |
| 20261019T210109Z-07315cd94 | milestone:P6b | ldc2 | 58/171 | 2.88 | 1.60 | 4.08 |
| 20261019T210324Z-07315cd94 | milestone:P6c | ldc2 | 58/171 | 2.87 | 1.64 | 4.04 |
| 20261019T210601Z-07315cd94 | milestone:P6d | ldc2 | 59/171 | 2.90 | 1.62 | 4.08 |

## Progress

Last updated 2026-10-19.

| Milestone | State | Evidence |
|---|---|---|
| A1 harness + LDC baseline | done | `baselines/20261019T204823Z-9bba1f268` |
| P6 (state-code DFA scanner, <=48 states) | done, enabled by default | `milestones/P6{a,b,c,d}`; P6d is the final form |
| A2–A5, F*, B*, other P*, L*, G*, X* | not started | — |

P6 result (LDC, vs baseline): within 1.5x 53 -> 59 of 171, geomean 1.81 -> 1.62, JSON.EscapeHeavy 4.9x -> ~1.4x,
CSV.Flat/validation -73%. Remaining >5% slowdowns: Numbers.BinaryLong/validation +5.2%,
JSON.InvalidTruncated/validation +5.0% (borderline noise). P6a/P6b/P6c are kept as superseded runs.

Not run: DMD (this host's `dmd` segfaults, including `dmd --version` and on the unmodified baseline), ASan/LSan,
Valgrind, coverage tooling (`scripts/coverage.sh` needs GDC). `-vgc` on dfa.d adds only CTFE-time lines.
Largest outstanding gaps are listed in the latest summary.csv (PEGGrammar.Permissive, Arithmetic.Flat/Unary).
