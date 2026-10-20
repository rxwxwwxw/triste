# milestone:S3[direct] 20261020T151538Z-427156981-2d501e854

Controlled final retained S3 candidate, explicit NPeggedLeanEntry, direct backend. Same host/compiler/input/mode as paired exact baseline; feature version is the intentional build difference. Context-pointer and explicit finish-return experiments were rejected. S3 remains open pending strict coverage and final hook. Measurement source hashes precede subsequent test-only coverage additions; parser implementation is unchanged.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
