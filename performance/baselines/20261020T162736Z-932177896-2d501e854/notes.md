# baseline[direct] 20261020T162736Z-932177896-2d501e854

Controlled final-default comparison: same CPU, hardware, compiler, flags, inputs and modes; before is the pre-S3 exact direct binary. 21 samples per implementation/case with alternating prebuilt blocks.

- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), both from identical output-mode workloads; N/A when no handwritten twin exists.
- Samples pool all repetitions (n_samples = runs x samples).
- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).
- Peak RSS and DMD timings: not measured by this harness (DC=ldc2 only).
