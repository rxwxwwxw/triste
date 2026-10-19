# baseline[direct] 20261019T224838Z-276489b1c

Baseline on the direct backend (PARSER_BACKEND=direct), HEAD after L3. Earlier baselines/milestones used the combinators backend and are not comparable. LDC only; DMD host-broken.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
