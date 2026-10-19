# milestone:F4 20261019T213323Z-1fef780eb

F4 trial: -d-version=NPeggedFirst2 (off by default). Existing workloads contain few overlapping-literal choices; see choices micro-benchmark in performance/milestones/F4/choices.txt. LDC only.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
