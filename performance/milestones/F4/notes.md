# F4: bounded FIRST-2 dispatch (opt-in, `-d-version=NPeggedFirst2`)

`literalChoice2!(texts...)` replaces `or!(literal...)` for ordered choices of 1-2 byte literals (>=2 alternatives, <=16
distinct first bytes) whose FIRST bytes overlap and which `dispatchChoice` cannot handle. A 257-entry-per-first-byte table
maps (byte1, byte2 or EOF) to the ordered-choice winner. Success equals the original: same node, same step count (the winner's
index+1 ticks, taken only when the budget allows). Failure, tree mode, CTFE, non-ok status and tight step budgets use the
original `choice`. Because literals are <=2 bytes, skipped earlier failures end at most at the winner's end, so omitting
their `recordFailure` calls cannot change final `failEnd`.
Validation: peg.d unittest (step limits 0..100, recognition and compact records), tests/differential.d `operators` fixture
(combinators vs direct, flag on and off), full suite with the flag. LDC only.
Mixed benefit (see choices.txt), so it stays off by default; a later milestone should decide the DFA-vs-dispatch interplay.
