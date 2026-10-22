# milestone:X2b[direct] 20261022T163510Z-735827000-59d9f0a36

X2(b)/(c) plus direct default; LDC 1.43, same gate as PhaseExit3

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
