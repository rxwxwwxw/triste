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
