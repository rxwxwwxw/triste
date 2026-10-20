# milestone:S2[direct] 20261020T000732Z-6e7a5966f

S2: rule-level tick taken from the register counter (recognizeRuleTicked); cursors with fewer than 3 tick sites keep the shared-memory counter. PARSER_BACKEND=direct, LDC only.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
