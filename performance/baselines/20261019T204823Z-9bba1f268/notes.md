# baseline 20261019T204823Z-9bba1f268

A1 initial baseline: scripts/performance_gate.py defaults (2000 iterations, 7 samples, 3 runs), LDC only; DMD not run.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
