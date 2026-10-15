# Performance implementation record

The full objective remains the per-case 5× target in
[OPTIMIZATION_PLAN.md](OPTIMIZATION_PLAN.md). This log records implementation
evidence without treating intermediate milestones as completion.

## Slab allocation, 2026-10-14

`Arena` now allocates small requests within 4 KiB slabs, reserves dedicated
oversized blocks without displacing the current slab, and retains destructor
ownership of every block. Limits charge actual reserved bytes and a new slab
is capped at the remaining budget. Existing reserved storage can still serve
requests when the reservation limit is exactly reached. Lowering the limit
below already reserved bytes causes a sticky resource-limit failure.

Adjacent tests cover sharing a slab, stable pointers, over-alignment, nonzero
default initialization, dedicated blocks, budget exhaustion, allocation failure,
overflow and independent arenas. The benchmark output builder test checks payload
traffic while allowing slab sharing rather than requiring one malloc per growth.

Passed DMD/LDC/GDC unit and integration runs, hot-path diagnostics, Phobos check,
LDC ASan/LSan, benchmark runner integration tests, and allocator-only Valgrind
Memcheck (zero errors and no lost bytes). Valgrind required the existing cached
loader debuginfo via `DEBUGINFOD_CACHE_PATH=build/debug-cache-cachy` and
`DEBUGINFOD_URLS=https://debuginfod.cachyos.org`.

Exploratory validation allocation counts fell from 482 to 14 for small JSON,
2,546 to 85 for medium JSON, and 73,878 to 1,106 for long strings. The report is
`build/perf-validation-slab.json`; the previous report is
`build/perf-validation-review.json`. Timing overlapped compiler/coverage jobs
and showed mixed results, including regressions; it is not acceptance evidence.
Repeat paired timings without competing jobs and investigate remaining regressions.

Baseline spans/tree reports were captured before rebuilding the benchmark:
`build/perf-spans-before.json` and `build/perf-tree-before.json` (20 iterations,
seven samples, exploratory). The slab-era GDC sanitizer binary subsequently
passed outside the sandbox; LeakSanitizer could not inspect threads inside it.

## Recognition and initial scalar scanners

`State!(CT, Check)` separates recognition and tree memo identities and storage.
`check!(Parser.opCall)` borrows input synchronously and returns scalar acceptance,
status and offsets in a move-only owner. Compile-time specialization suppresses
match/child/failure arrays; memo entries remain. The frontend and regenerated
bootstrap expose both modes, including the alternate CTFE storage backend.

Generated grammars containing actions fall back to whole tree execution for
recognition, preserving callback-visible captures and recursive seed behavior.
Direct action combinators also have a conservative tree fallback. Adjacent and
integration tests compare action invocation counts, left recursion, offsets,
acceptance, status and resource limits between tree and recognition modes.

Range/class and repetition combinators expose scanner metadata. Eligible
recognition repetitions, and fused/discarded repetitions in tree mode, use tight
byte loops. Fused captures use one input slice; ordinary tree repetition retains
its original per-character captures. Unicode range decoding and captures with
gaps retain the generic implementation. Differential tests preserve loop and
terminal step accounting, including unfused captures on resource failure.

The validation benchmark now uses recognition and reports that execution mode.
The exploratory seven-sample, 20-iteration report is
`build/perf-validation-scanners.json`: whitespace-heavy JSON and the three
ambiguity cases were within 5×; other cases ranged roughly 8×–120×. These are
not final acceptance measurements: compilation/coverage jobs overlapped them.
The earlier recognition-only report is `build/perf-validation-check.json`.

A local probe (`build/memo-probe.d`, raw samples in `build/perf-memo-small.txt`
and `build/perf-memo-long.txt`) compares the same JSON grammar with memoization
on/off against handwritten validation, using input barriers and verified
checksums. No-memo recognition removes all allocator calls on both inputs, but
still costs roughly 13× handwritten time on small JSON and 95× on long strings
in that exploratory run. Ordinary string-character combinators remain expensive.

Passed DMD/LDC/GDC unit/integration tests, LDC ASan/LSan, hot-path diagnostics,
Phobos checks, benchmark integration/comparison-script tests, and full-library
Valgrind Memcheck (zero errors; no definitely/indirectly/possibly lost bytes).
DMD line reports currently show storage 100%, engine 96%, frontend 98%, bootstrap
99%.

## Grammar graph analysis and selective memoization

`npegged.analysis` adds structured grammar expression graphs and fixed-point solver
for nullability, conservative FIRST byte-set facts (`CharSetMask`), and Tarjan SCC
analysis identifying left-recursive rule components.

`Frontend` in `npegged.grammar` now supports `Memoization.selective`: rules without
parameters or left-recursion bypass memoization tables when non-conservative.
Choice optimization automatically generates `predictiveChoice` jump-tables from
computed FIRST sets. The bootstrap parser `src/npegged/parser.d` was regenerated and
verified against `build/regenerated-parser.formatted.d`.

Passed DMD/LDC/GDC unit and integration suites, all `src/` modules exceeded 90%
line and branch coverage (e.g. `analysis.d` 98.96%, `grammar.d` 92.01%, `storage.d` 97.50%),
LDC ASan/LSan, and Valgrind Memcheck (0 errors from 0 contexts).

Still unfinished: smaller recognition values, broader string/token scanning,
diagnostic materialization and discard propagation for general expressions,
direct compact output, equivalent benchmark coverage for the other handwritten
programs, and the repeated 5× acceptance matrix. SIMD/DFA/streaming remain
conditional on residual profiles.
