# Work attribution (F04)

Reproduce with `bash scripts/recursion-metrics.sh performance/results/F04`.
All four counter CSVs have 112 groups. Each overhead cohort has 112 groups ×
three runs × seven samples (2352 timed rows). Source hashes were verified.
Timing and counter reports are separate: overhead-1 is explicitly instrumented
and must never be used as an optimization timing baseline.

Counters retain existing semantics. `output_snapshots` counts snapshot requests
(including empty/failed requests); `snapshot_bytes` retains the previous requested
copy size. Restore calls are counted at RecordBuffer.restore, including empty or
failed operations. Restore nodes/bytes count successful puts, including work
subsequently rolled back after a corrupt snapshot or resource failure. Growth
copies count bytes actually copied after a successful replacement allocation.
Bucket visits count examined lookup entries; unlink visits count every examined
link including the target. Rehashes include initial bucket creation; rehashed
entries count entries actually linked into the replacement table.

## Observed scaling

Valid direct/selective measurements (combinator counters agree):

| Grammar / mode | Terms | Invalidation visits | Snapshot bytes | Restore bytes |
|---|---:|---:|---:|---:|
| Direct / recognition | 256 | 256 | 0 | 0 |
| Direct / recognition | 512 | 512 | 0 | 0 |
| Direct / recognition | 1024 | 1024 | 0 | 0 |
| Indirect / recognition | 256 | 512 | 0 | 0 |
| Indirect / recognition | 512 | 1024 | 0 | 0 |
| Indirect / recognition | 1024 | 2048 | 0 | 0 |
| Direct / records | 256 | 256 | 2097152 | 2113504 |
| Direct / records | 512 | 512 | 8388608 | 8421344 |
| Direct / records | 1024 | 1024 | 33554432 | 33619936 |
| Indirect / records | 256 | 512 | 6275072 | 6299584 |
| Indirect / records | 512 | 1024 | 25133056 | 25182144 |
| Indirect / records | 1024 | 2048 | 100597760 | 100696000 |

This corpus is **output-dominated**, with quadratic snapshot/restore copying.
Recognition invalidation and hash traversal are linear, with one initial bucket
allocation and no later rehash in these synthetic chains. F03 recognition timing
is also approximately linear at larger sizes. These results do not support the
historical claim of superlinear recognition invalidation in the current source.
They do not prove that all recursive grammars have linear invalidation.

## Instrumentation overhead (diagnostic only)

Across the 112 groups, instrumented/uninstrumented median-time ratios range from
0.960 to 1.354, with median 1.019. At 1024 valid terms: direct recognition 1.031,
indirect recognition 1.098, direct records 0.985, indirect records 1.012. Values
below one illustrate shared-machine noise; no performance promotion is justified.
Both cohorts use the same source, samples, limits and optimized LDC flags.

## Verification

DMD and LDC each pass all 14 source-module unit suites with NPeggedMetrics.
Deterministic adjacent tests assert restore success/empty/corrupt/failure deltas,
growth copy bytes, lookup/rehash/unlink deltas and snapshot counts. Both compilers
pass the differential fixture. A separate compilation statically verifies that
ParseMetrics, RecordMetrics and their context/buffer pointer fields are absent
without NPeggedMetrics. Version guards also remove all counter increments.
Diagnostic ASan/LSan passes (outside the sandbox because its ptrace restriction
prevents LeakSanitizer startup). Full repository verification is recorded in the
final Phase F verification report.
