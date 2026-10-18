# H05 — empty Sp candidate abandoned: fast path already present

No production source change is retained. F05's selected empty whitespace/comment
experiment was stopped under its explicit condition to abandon the experiment
if the existing lowering already removes the suspected work. No 15–20% new gain
or global acceptance-gate improvement is claimed.

The initial source-level suspicion was that discard's `.scan` arm bypassed an
existing child `emitEmpty` guard. The generated source and optimized control flow
disprove that suspicion for Sp. The closed sequence's guard is emitted at child
position `p3` in recognition and records. In the optimized cursor, status/trace
checks precede a combined FIRST mask for space, tab, CR, LF and `#`. For a byte
outside that mask, or EOF, enough remaining budget permits a six-work-unit batch
and an immediate successful empty result. The `repeat.scan` call is reached only
on consuming/fallback paths; counting its static call site does not show work on
the empty path. Adding a second discard-level guard would duplicate existing work.

The microfixture copies the benchmark PEG Sp expression exactly. Its standalone
recognition timing uses borrowed opaque input, 1,000 warmups and 100,000 parses
per sample; three runs × seven samples per case. The six cases are `x`, EOF, one
space, `#`, a comment with newline and mixed whitespace/comments. Timings are
uninstrumented baselines, not a before/after speedup comparison. The CSV case
index maps to `caseInputs` in metadata. Compiler flags, source/raw/binary hashes,
CPU, compile time and optimized cursor evidence are preserved. Each binary run
has a 60-second timeout and 4 GiB address-space limit.

Reproduce with `scripts/empty-scanner-check.sh`,
`scripts/empty-scanner-memory-check.sh` and
`scripts/empty-scanner-probe.sh performance/results/H05`. Keep timing isolated
from other compilation or verification jobs.

`tests/empty_scanner.d` compares combinator and direct recognition, borrowed/owned
records and every full-tree field, exact trace event arrays, all 256 leading
bytes with five short suffixes, EOF, comments, embedded NUL/UTF-8 and finite
step/depth/parse/output budgets. Generated-source assertions confirm the existing
recognition and records guard. Source modules are unchanged from H03; their
coverage remains tied to those exact source hashes. The integration fixture is
outside the source coverage threshold. Memory checks use ASan/LSan's established
native-stack setting and Memcheck without suppressions, conservative GC disabled
as documented in H01. All integration runs have explicit watchdogs/timeouts and
4 GiB memory limits.

Final measurements and verification are recorded alongside this report.

## Fresh evidence

The full benchmark PEG confirms the same path, not just the microfixture:
`peg/Sp.assembly.txt` loads the mask at `22b8f`, branches to the batched path at
`22bef`, adds six work units at `22c15` and jumps to the success return at `22c3f`.
The consuming/fallback code begins at `22c44`. Addresses identify this recorded
binary only. The optimized function retains three static call sites; they do
not imply calls execute on the empty path. `peg/` includes three fresh whole-PEG
probe runs, semantic trace counts, hashes and flags. Stage-clock rows are
diagnostic probes, not acceptance-gate times. Reproduce that cohort with
`scripts/empty-scanner-peg-probe.sh` after other timings finish.

| Standalone Sp input | Median ns/parse | Three run medians |
|---|---:|---|
| ordinary x | 19.89 | 19.76 / 19.84 / 20.19 |
| EOF | 19.25 | 19.19 / 19.17 / 19.83 |
| one space | 21.72 | 21.72 / 21.00 / 23.38 |
| # | 30.83 | 31.38 / 30.33 / 30.78 |
| comment + newline | 35.23 | 35.06 / 35.08 / 36.29 |
| mixed whitespace/comments | 47.46 | 47.29 / 47.90 / 47.46 |

The final integration transcript contains 39,681 lines and is byte-identical on
DMD, LDC, ASan/LSan and Memcheck. Memcheck reports zero errors, zero definite or
indirect leaks, and the established druntime residual of 32 possible / 216
reachable bytes. `verification/summary.json` pins the unchanged production source
hashes and fixture. Micro metadata's instruction field counts disassembly address
lines, including continuation-byte lines; it is not an executed instruction count.

Decision: abandon this candidate as already optimized. The exhaustive regression
fixture and reproducible evidence remain; no source or parser policy changed.
Another fixed-cost hotspot requires a separate ticket. H06 scanner fallback
reporting is the next independent roadmap task.
