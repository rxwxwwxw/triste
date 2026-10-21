# milestone:C1[direct] 20261021T002149Z-280633000-4f68f5d5a

Full gate after S4, O2, O3, Q2, D2, S5, C1 (direct backend, LDC 1.43, Apple M1): 171 original workloads + corpora + family cases in validation/spans/tree, plus the new accept mode on the workload suite.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
