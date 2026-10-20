# milestone:S3[direct] 20261020T151149Z-861675744-2d501e854

Final retained implementation: explicit NPeggedLeanEntry, direct backend, context-pointer and finish-return prototypes rejected. Full frozen-source run; 21 samples per implementation/case. Full coverage is not yet passing. Controlled prebuilt before/after comparison follows; this run alone does not establish regression disposition.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
