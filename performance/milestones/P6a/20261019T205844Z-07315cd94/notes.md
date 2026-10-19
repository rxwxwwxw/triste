# milestone:P6a 20261019T205844Z-07315cd94

P6a: straight-line state-code DFA scanner (<=48 states) replacing table loop; LDC only, DMD not run (dmd segfaults on this host, also on baseline). Compare against baselines/20261019T204823Z-9bba1f268.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
