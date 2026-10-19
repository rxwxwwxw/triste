# milestone:P6c 20261019T210324Z-07315cd94

P6c: self-loop bitmask loops in the state-code scanner. LDC only; DMD not run (host dmd segfaults, also on baseline).

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
