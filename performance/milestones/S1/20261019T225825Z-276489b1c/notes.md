# milestone:S1[direct] 20261019T225825Z-276489b1c

S1: step accounting (steps/live status) held in locals inside generated cursor functions, synchronized around calls; exactness checked by dense differential sweeps. PARSER_BACKEND=direct, LDC only.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
