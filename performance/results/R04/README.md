# R04 — copying scales independently of recognition

The same direct/indirect recognition-chain grammars from R01 are compiled for
compact records, with root-only and all-named-rule projections. Both parser
backends and full/selective memoization are measured. Raw CSVs contain successful
and trailing-`+` failures at 16–2048 terms (256 diagnostic parses in total).
There is no timing claim: instrumentation and output work are the subject.

The standalone `combinators.svg` and `direct.svg` plots distinguish final logical
output bytes, cumulative requested payload, peak retained bytes, snapshot copies,
restore copies and buffer-growth copies. `summary.csv` preserves every raw field
with its cohort labels. Metadata pins sources, compiler, CPU, command and CSV hash.

## Findings

For combinator/selective output at 2048 terms:

| Grammar | Final output | Snapshot copies | Restore copies | Buffer growth copies |
|---|---:|---:|---:|---:|
| direct | 131104 B | 134217728 B | 134348768 B | 261120 B |
| indirect | 196608 B | 402522112 B | 402718656 B | 261120 B |

Snapshot and restore work are quadratic in the all-rule chain projection. The
indirect chain's snapshots at 256/512/1024/2048 terms are
6275072/25133056/100597760/402522112 bytes: roughly 4× per doubling, while
logical output doubles. Buffer growth is geometric and its copy volume remains
linear. This isolates an output-copying mechanism even though R01's recognition
work counters remained at most linear for these flat chains.

Root-only output retains one 32-byte node, with no memo snapshot/restore copies
for these rules. It is a projection control, not evidence that arbitrary recursive
output is cheap. Failure rows expose no final nodes but still incur copying and
retained memory; final output size is not a proxy for attempted work.

## Measurement definitions and bounds

`logical_bytes` is successful exposed node count × CompactNode.sizeof (32 here).
Snapshot counters in RecordBuffer count actual successful node copies; empty and
failed snapshot calls still count calls, but add zero copied bytes. Existing parser
snapshot counters agree for these allocation-successful cohorts. Restore counters
count appended nodes, including work subsequently rolled back. Buffer-growth bytes
count moving prior live records to newly allocated capacity.

Requested payload and peak retention include **both** parse and output arenas,
reported separately in the CSV and summed in plots. Both arenas are monotonic
within a parse: retained memory at parse completion is their peak, including
retired entries, discarded snapshots, alignment and slab overhead. Requested
payload excludes arena block/slab overhead and is not the number of live bytes.
Libc allocator-internal bookkeeping and process RSS are not measured.
Cumulative copies may exceed both logical output and live buffer capacity.

The initial 2048-term all-rule run hit the default 256 MiB parser arena budget.
The archived complete cohorts explicitly permit 2 GiB parse and 1 GiB output
arenas, under a 4 GiB process address-space ceiling and 60-second deadline.
No default production limit or parser policy changed. Default builds contain no
new metric fields or updates; RecordBuffer's existing snapshot API is preserved.

Reproduce with `python3 scripts/record-copying.py build/R04-replay` (requires
LDC and matplotlib). DMD/LDC metric unit tests and full repository verification
cover the instrumentation; verification evidence is retained in `verification/`.
