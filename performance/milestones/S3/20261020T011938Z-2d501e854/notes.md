# milestone:S3[direct] 20261020T011938Z-2d501e854

Exploratory unpinned run concurrent with coverage work. Retained as measured; controlled prebuilt A/B is required before conclusions. Parser code unchanged after compilation. Test-only recorder coverage is being merged back into the existing suite.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
