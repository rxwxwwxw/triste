# milestone:S3[direct] 20261020T025412Z-2d501e854-broad-candidate

Broad S3 experiment, rejected for regressions. CPU pinned, alternating binaries; compiler activity may overlap. Not the shipping default.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
