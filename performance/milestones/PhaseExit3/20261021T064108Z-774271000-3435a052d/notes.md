# milestone:PhaseExit3[direct] 20261021T064108Z-774271000-3435a052d

Final gate after check-mode loop form, O4 and trie walk; --q2, four modes, 500x7x3, direct backend, LDC, M1.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
