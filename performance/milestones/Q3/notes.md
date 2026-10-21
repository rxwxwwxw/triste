# Q3 — Cycle attribution — COMPLETE (function-level; per-instruction counters not run)

Method: macOS `sample` (1 ms stacks, 3-4 s windows) on single-engine harnesses built from the benchmark grammars
(`miniq3.d`, direct backend, LDC 1.43 -O3, Apple M1) so the NPegged parser is the only code running, plus the full runner
for context (`sample-*.txt`, `mini-*.txt` here). `xctrace` CPU counters were not used (not run). Cursors are heavily inlined, so
attribution is by function: parser cursors, record store (`RecordBuffer.openKind`/`putLeaf`), arena growth
(`Arena.allocate!CompactNode` + `memmove`), clock reads. Timing runs stayed separate from these profiles.

| workload (mode) | cursor/rule code | record growth (allocate + copy) | record put | note |
|---|---|---|---|---|
| CSV.Flat (spans) | 80% | 17% (11% allocate, 6% memmove) | inlined | growth is first-touch of fresh pages plus copies |
| Arithmetic.Flat (tree) | 60% | 30% (20% allocate, 10% memmove) | 11% (`openKind`) | every rule is a record |
| PEGGrammar-like (validation) | 100% | - | - | two functions: root and the inlined `Primary` cursor |
| PEGGrammar-like (accept) | 100% | - | - | same shape; accept clone has no failure code |

Ceiling experiments (unsound, same tree, median of repeated runs) put numbers on the other categories:
- failure recording (rejection path and lookahead-heavy grammars): PEGGrammar validation -8..-23%, Numbers/CSV/Arithmetic ~0%
  on valid inputs, -1..-5% on tiny rejections (S8) -> realized by the `accept` clone (C1);
- rule/loop ticks (after D2): validation -10..-14% on Arithmetic/PEGGrammar, but see W2: mostly inlining side effects;
- depth: -4..-10% before S5, recovered by S5;
- scanner prologue and record put: S4 and O3.

Rejection path vs acceptance path (tiny inputs): `check` entry (CheckResult + arena counters + merge) is the floor for the
validation mode; `accept` avoids it (-10..-15% on tiny rejections). Disposition of the dependent milestones:
- S7 (cursor results in registers): not supported. The profiles show two or three functions and no call-boundary hot spot; the
  S5 depth change and the register experiments (see W2) did not move validation beyond noise except through inlining.
- X1 (vectorized scanning): not supported. Scanner prologue was removed by S4 and scanner time is not the dominant category in
  any profiled workload (CSV long fields run at handwritten speed: ratios 0.95-1.0).
- Record growth is the largest remaining non-parser category in records modes (17-30%). A parse-time reservation
  (`RecordBuffer.reserve(input/2 + 128)`) measured -17% on CSV spans (7.79 -> 6.43 s per million parses) and ~0% on Arithmetic tree.
  It was NOT applied: the handwritten twins share `RecordBuffer`, so reserving only inside `parseRecords` would flatter the
  ratios without a corresponding twin change. A shared growth-policy change (start at 128, quadruple) measured -1% (CSV) and
  -6% (Arithmetic tree, noisy) and was not kept.
