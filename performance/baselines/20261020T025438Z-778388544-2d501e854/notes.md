# baseline[direct] 20261020T025438Z-778388544-2d501e854

Paired baseline for the guarded S3 experiment; CPU pinned with alternating binaries and seven samples in each of three runs. Coverage compilation overlapped.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
