# milestone:PhaseExit2[direct] 20261021T060113Z-124016000-5be5e5027

Phase-exit full gate after the LeftExpr check-mode fix and O4: --q2, four modes, 500 iterations x 7 samples x 3 runs, direct backend, LDC, Apple M1.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
