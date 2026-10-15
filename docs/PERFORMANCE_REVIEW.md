# NPegged performance review

Reviewed against the current worktree on 2026-10-14, including staged benchmark
changes. The actionable backlog is consolidated in
[OPTIMIZATION_PLAN.md](OPTIMIZATION_PLAN.md); this file records why it is ordered
that way. Earlier speculative speedup ranges and the old incomparable smoke
baseline have been removed.

## Current source findings

| Area | Evidence | Remaining consequence |
| --- | --- | --- |
| Storage | `storage.d: Arena.allocate` allocates and links one block per request, then initializes each element | Allocation counters exist; a slab/bump allocator does not |
| Output suppression | `peg.d: transform(':')` runs its child before clearing matches/children | Discard and whitespace still pay output construction costs |
| Repetition | `peg.d: repeat` invokes the full child parser and collects match/child arrays per iteration | Character masks alone do not produce fused scanner loops |
| Failure | `State.failure` allocates an expectation slice; `finish` retains a failed-child snapshot | Speculative failures allocate even during successful parsing |
| Capture | `transform('~')` copies matches to a new byte buffer | Safe contiguous captures can use owned-input spans; captures with gaps cannot |
| Memoization | `grammar` defaults to `Memoization.yes`; `State.rule` has a no-memo branch | Existing no-memo mode can be measured before selective policy work |
| Prediction | `Frontend.computeFirstSet` analyzes generated expression strings conservatively | General choice unions, nullable prefixes and spacing wrappers still limit prediction |
| Tree copying | Builders collect ParseTree values; `defined` and enclosing combinators retain matches/children | Compact direct output can avoid generic-tree construction and projection |

## Completed work removed from the backlog

The source already contains ASCII range decoding bypasses, single-character and
slice literal fast paths, the non-memoized rule branch, character-class masks,
and predictive choice for supported disjoint FIRST sets. These are foundations,
not pending optimization tasks. The prediction and scanner extensions in the
plan are explicitly additional work.

The current benchmark implementation already addresses the previous review's
baseline blockers. `benchmark/json_grammar.d` shares JSON syntax between tree
engines; acceptance gates check complete consumption and equivalent output
records. Validation, spans and concrete-tree obligations exist, along with
checksums, input barriers, repeated samples, warmup, actual iteration accounting,
allocator traffic and separate GC reporting. Chumsky is pinned and the comparison
script captures versions, flags, CPU and source identity. See
[benchmark/README.md](../benchmark/README.md) for commands and measurement scope.
These mechanisms exist in source; that does not imply every compiler, dependency
or validation suite was exercised during this documentation review.

The important remaining distinction is execution: NPegged validation/spans/tree
currently use native-tree projection, while handwritten output is direct.
Equivalent observable outputs make this a useful comparison, but do not mean
NPegged has implemented recognition or compact output paths. The legacy mixed
benchmark rows still lack common output obligations across engines.

## Fresh validation baseline

Executed the validation benchmark with 200 iterations and five samples on
LDC 1.43.0 / LLVM 22.1.8, AMD Ryzen 7 PRO 5850U. Release flags were
`-O3 -release -boundscheck=off -w -de -checkaction=halt`. All 13 cases completed
with checked checksums. Selected paired means:

| Case | NPegged µs/parse | Handwritten µs/parse | Time ratio | Improvement needed for 5× | NPegged allocator calls/parse |
| --- | --- | --- | --- | --- | --- |
| JSON.Small | 22.51 | 0.199 | 112.9× | 22.6× | 482 |
| JSON.Medium | 120.13 | 0.910 | 132.0× | 26.4× | 2546 |
| JSON.LargeString | 3816.80 | 5.224 | 730.6× | 146.1× | 73878 |
| JSON.EscapeHeavy | 262.74 | 1.065 | 246.8× | 49.4× | 6157 |
| JSON.WhitespaceHeavy | 234.28 | 2.407 | 97.3× | 19.5× | 6264 |
| JSON.DeepNesting | 107.98 | 1.411 | 76.5× | 15.3× | 1568 |
| Ambiguous.Retry | 20.31 | 0.217 | 93.8× | 18.8× | 539 |

This is one exploratory run with five samples, not the plan's acceptance gate.
All validation cases were above 5× (approximately 16×–731×). The long-string
case reserved 10,631,413 bytes per parse for 8,203 input bytes. These allocator
observations strengthen the case for eliminating intermediate work; they do
not establish CPU attribution without profiling. Spans/tree, the full Rust
comparison, and runtime validation suites were not run for this docs revision.
Raw local output is in `build/perf-validation-review.json` (an ignored build artifact).


## Priority decision

Reduce allocation and unused output first: slabs, true recognition/discard paths,
cheap failure tracking, then fused scalar scanning. Measure the already available
no-memo option early; apply selective memoization and broader prediction with
semantic safeguards. Direct compact output is necessary to give spans/tree a
credible route to the same target as validation.

There is no measured basis for multiplying estimated speedups or guaranteeing
5× across all grammars. The consolidated plan defines the denominator, remaining
benchmark coverage, per-stage evidence, and a per-case stopping criterion. General
DFA compilation and event streaming remain conditional because their semantic
and ownership costs exceed those of the initial optimizations.
