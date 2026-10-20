# milestone:S3[direct] 20261020T025438Z-915858834-2d501e854

Eight-byte guarded S3 candidate, rejected for unrelated workload regressions. Same paired protocol and overlapping compilation as its baseline. No default enablement.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
