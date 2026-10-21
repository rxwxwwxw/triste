# milestone:D1-combinators 20261021T060542Z-107474000-1ce38a6c6

D1 data: same gate as PhaseExit2 with PARSER_BACKEND=combinators.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
