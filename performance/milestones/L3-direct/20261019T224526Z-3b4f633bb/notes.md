# milestone:L3-direct 20261019T224526Z-3b4f633bb

L3 comparator: PARSER_BACKEND=direct (the earlier baselines used the default combinators backend). LDC only.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
