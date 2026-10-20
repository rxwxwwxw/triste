# milestone:Q2[direct] 20261020T220009Z-547430000-38e6e00b1

Q2: G7 corpora (real, synthetic, learned, adversarial; large entries from build/corpora-large) and the lex_utf8/failure/pathological family cases timed with the 171 original workloads. Direct backend, LDC 1.43, Apple M1. First run including these workloads, so it is not comparable with earlier runs; compare the original 171 by workload id.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
