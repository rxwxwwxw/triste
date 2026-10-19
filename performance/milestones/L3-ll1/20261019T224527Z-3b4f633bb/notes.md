# milestone:L3-ll1 20261019T224527Z-3b4f633bb

L3: PARSER_BACKEND=ll1 (direct + FIRST-guarded loop exits in cheap-certified rules). LDC only.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
