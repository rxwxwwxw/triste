# O2 — Checkpoint elision in record loops — COMPLETE (exact; default on, direct backend records mode)

Fact: `Frontend.failureLeavesNoOutput` (src/npegged/grammar.d). A loop/option body qualifies when a failed
iteration provably leaves no record: non-emitting expressions; a reference whose callee is emitted through
`recognizeRecordedRule` (it rolls back its own record on failure, including limits); a sequence whose single
record-emitting child is its LAST child (nothing after it can fail or tick, so limit exhaustion cannot strand
a record either); choices all of whose arms qualify; loops. Everything else keeps `outputCheckpoint()` and
`rollbackOutput()`. `(Field Sep)*`, `(Sep Item Mark?)*`, and emitting-middle shapes stay unproven.

Ceiling (unsound: drop all loop checkpoints; `ceiling-*.json`, vs the S4 runner): CSV.Flat/spans -9.4%,
CSV.MultiLine -8.8%, PEGGrammar.ManyRules -8.7%, Arithmetic spans -4..-6%. Above the 3% threshold, so implemented.
(CSV.LongField +49% in that unsound variant is an artifact of its wrong output; not used.)

Result (sound; 3 interleaved repetitions x 9 samples x 20000, medians; S4 runner vs O2 runner, spans+tree):
PEGGrammar tree -9.4% .. -11.9%; Arithmetic spans -5.1% .. -6.4%; CSV.Flat spans/tree -5.2%; CSV.MultiLine/spans -5.3%.
Worst: CSV.Empty/spans +2.9%, Arithmetic.InvalidNumber/tree +2.9%, CSV.InvalidSpacing/spans +2.7%
(no reproducible >5% regression; disclosed). Median over 66 workloads: -1.6%.

Tests: colocated generated-source test in grammar.d (checkpoint counts for 9 grammars: proven and unproven shapes,
choices, unselected rules); tests/differential.d new `loops` fixture with only `Item` selected, dense step/depth/output
limit sweeps in recognition, borrowed/owned records and tree modes, both memoization policies; all differential
and 24-module unit tests pass on LDC. A mutation (assume every body qualifies) is caught by the unit test.
DMD: not run (segfaults here). Coverage tool, ASan/LSan, Valgrind: not run for this milestone.
