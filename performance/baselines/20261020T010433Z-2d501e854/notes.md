# baseline[direct] 20261020T010433Z-2d501e854

Fresh Ryzen/Linux direct-backend baseline for S3. Earlier M1/macOS runs are not comparable. Build timeout extended to 900s via temporary wrapper; flags and runtime timeouts unchanged.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
