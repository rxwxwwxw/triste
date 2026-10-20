# S8 — Rejection-path ceiling experiment — NO-GO

Date: 2026-10-20. Host: Apple M1, LDC 1.43.0, `PARSER_BACKEND=direct`, validation mode,
20000 iterations x 9 samples per case (single run; indicative, not a gate run).

Experiment (unsound, never committed): `State.recordFailure` returns immediately, which removes every
failure-position store, the `hasFailure` update and the `finish` merge input. This is an upper bound
on anything S8 (furthest failure in a register) could save, because S8 would still have to produce
the same `failEnd`. Raw data: `base-*.json` (unmodified) vs `ceil-*.json` (ceiling build).
Outputs differ by design; only timings are used.

| Workload (invalid/tiny) | base ns | ceiling ns | delta |
|---|---|---|---|
| Numbers.ScientificTruncated | 27.2 | 26.0 | -4.6% |
| Numbers.ScientificTrailing | 23.8 | 23.0 | -3.6% |
| Numbers.ScientificEmpty | 26.4 | 25.9 | -1.6% |
| Numbers.HexaInvalid | 15.9 | 15.5 | -2.9% |
| Numbers.BinaryInvalid | 16.4 | 16.1 | -1.9% |
| CSV.Empty / EmptyQuoted / Truncated / InvalidSpacing / Trailing | 13.4-20.2 | | -0.1 .. -2.6% |
| PEGGrammar.Truncated / Trailing / Empty | 82 / 74 / 23 | 75 / 68 / 22 | -7.9 / -7.4 / -4.5% |
| Arithmetic.Truncated / Trailing / InvalidNumber / Empty | 66 / 41 / 26 / 19 | | -1.7 / -5.9 / -4.2 / -0.6% |

Median delta over all 4 families: -2.4%. For the Numbers/CSV tiny cluster it is -0.1% to -4.6%,
median about -2%, below the roadmap's 3% threshold even with failure recording deleted entirely.

Decision: **S8 closed NO-GO.** No source change was kept (`git diff` clean; the experiment was applied to
`src/npegged/peg.d` temporarily and restored). Failure recording is not what dominates the tiny rejection
path; the fixed entry cost measured by Q1 is. Not run: DMD (segfaults on this host), sanitizers (no code change).
