# C1 — `accept` mode — (a) COMPLETE, (b) NO-GO

(a) `accept!(parser)(context, input)` -> `AcceptResult{accepted, status}` (src/npegged/peg.d, `docs/ACCEPT.md`): the same
verdict/status/work units as `check`, no `failEnd`, no arena counters. The direct backend emits an `accept` clone per rule
(`_acursor_*`, `State.acceptOnly` routes to it) without failure recording, probe bookkeeping or mismatch-offset scans;
`dfaToken.cursorAccept` skips the scanner's diagnostic records.

New output mode `accept` in the benchmark infrastructure (`--accept` with `--workloads --mode=validation`;
`scripts/performance_gate.py --modes validation spans tree accept`): the NPegged side calls `accept!`, the handwritten twins
are the existing boolean parsers, workload ids end in `/accept`, and the mode is reported separately from `validation`.

Tests: peg.d (`accept` == `check` + whole input, prefix match not accepted, resource limit), options/workload unit tests, and
the A4 differential: for every fixture, both backends, memoization yes/selective, tracing on/off, dense step limits 0..80,
depth/memory/output limits: accept(reference) == accept(direct) == derived from check(direct), including trace sequences.
LDC only (DMD segfaults here); sanitizers/Valgrind/coverage tooling not run.

Measured (Apple M1, LDC 1.43, direct backend, 3 interleaved repetitions x 9 samples x 20000, same binary, validation vs
accept, raw JSON in this directory): median over 44 workloads -7.1%. PEGGrammar.Deep -19.3% (ratio vs handwritten 0.81 ->
0.66), Small -10.7% (1.12 -> 1.00), Trailing -10.6%, Truncated -10.4%; tiny rejections -10..-15% (Arithmetic.Empty
17.4 -> 14.8 ns, ratio 1.79 -> 1.52; Numbers.HexaInvalid 2.03 -> 1.73; CSV.Empty 1.95 -> 1.72); long scanner-dominated
inputs unchanged (+-0.5%). No regression.

(b) Optimistic `check` with exact replay: closed NO-GO. `check`'s result includes arena counters and `failEnd`, which the accept
clone does not reproduce; a rejection pays both passes (34 of the 40 over-target tiny workloads are rejections); the speed is
available directly through `accept!`.
