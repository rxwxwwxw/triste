# milestone:S2b[direct] 20261020T001203Z-6e7a5966f

S2b: S1 plus rule-level tick from the register counter (recognizeRuleTicked); every cursor keeps register counters (threshold 1). PARSER_BACKEND=direct, LDC only.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
