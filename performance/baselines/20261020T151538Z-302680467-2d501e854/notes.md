# baseline[direct] 20261020T151538Z-302680467-2d501e854

Controlled S3 comparison, exact direct baseline: fixed CPU, 21 samples per implementation/case, alternating prebuilt A/B blocks with retained final opt-in binary. Same exported corpus and output obligations; compiler feature version differs intentionally in the candidate.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
