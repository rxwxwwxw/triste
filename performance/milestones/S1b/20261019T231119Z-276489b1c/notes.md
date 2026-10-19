# milestone:S1b[direct] 20261019T231119Z-276489b1c

S1b: as S1 but step counters in a local StepCounter struct (no nested-function closure). PARSER_BACKEND=direct, LDC only.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
