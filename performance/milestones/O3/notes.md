# O3 — `RecordBuffer.putLeaf` for compiled leaf kinds — COMPLETE (exact; default on)

Change: `RecordBuffer.putLeaf(kind, begin, end)` (src/npegged/records.d) appends a finished childless record with a
single capacity branch, replacing `openKind` + `syncOutput` + `finishFresh` on the compiled-leaf path of
`State.recognizeRecordedRule` (src/npegged/peg.d). It skips the selector/`kind == uint.max` test (the leaf bit
implies a real kind; asserted), the up-front `status` computation, the `parent < _length` validation (holds by
construction: rollbacks never cut below an open ancestor; asserted) and the `parent` save/update. The status is checked
after the append by the existing `syncOutput`, which rolls the record back to the checkpoint when it is not ok,
the same outcome the failing `put` of the old pair produced. Growth uses the same `grow()` as `put` (shared helper, so
arena counters `allocationCalls/requestedBytes/used` are unchanged). The optional capacity reservation was NOT
implemented: arena counters feed `Observation` and a reservation could move `resourceLimit`/`outOfMemory`.

Tests: records.d colocated test (equals openKind+finishFresh over 200 records across growth steps with a parent;
suppressed output; rollback after a leaf; refused growth reports the arena status). Differential gate (A4, dense
step/depth/output sweeps, records/tree modes, both backends) and 24-module unit tests pass on LDC. DMD not run
(segfaults on this host); coverage tool, sanitizers, Valgrind not run for this milestone.

Benchmarks (Apple M1, LDC 1.43, direct backend; 3 interleaved repetitions x 9 samples x 20000; baseline = O2 runner):
raw JSON here (`o1_o2_runner-*` vs `o1_o3_runner-*`). CSV records: Flat/spans -10.7%, Flat/tree -12.5%,
MultiLine -12.3/-13.8%, MultilineQuoted -11.5/-12.6%, SingleLine -10.0/-12.3%; Arithmetic.Truncated/spans -8.7%;
median over 66 workloads -3.0%. One outlier, CSV.LongQuoted/spans +10.0%, did not reproduce in 5 alternating reruns
(3496-3570 ns vs 3492-3510 ns; a single 3886 ns sample). No reproducible regression.
Cumulative S4+O2+O3 on CSV.Flat/spans: 12,086 -> about 10,540 ns.
