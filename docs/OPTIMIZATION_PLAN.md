# NPegged performance plan

Reviewed against the current worktree on 2026-10-14. This is the single backlog
for performance work; [PERFORMANCE_REVIEW.md](PERFORMANCE_REVIEW.md) records the
source findings. Completed work has been removed from the implementation plan.
No speedup estimates below are promises, and reaching the target requires measurement.

## Target and measurement contract

For each representative case and output mode, target
`NPegged mean ns/parse / Handwritten mean ns/parse <= 5` on the same machine,
compiler, input, iteration count, and output obligation. Report every ratio;
a geometric mean must not hide a case above 5. Treat validation, spans, and
concrete tree as separate targets. Keep legacy generic ParseTree compatibility,
but report its cost separately from a compact concrete-tree API.

The existing equal-work suite covers JSON and an ambiguous ordered-choice grammar.
It already checks acceptance, complete consumption, output records, checksums,
repeated samples, and allocator traffic. NPegged currently implements all three
obligations by building and projecting a native generic tree. The handwritten
implementation emits the required output directly. Eliminating this extra work
is part of the goal, rather than a reason to change the denominator.

Before runtime changes, save release baselines for all three modes:

```bash
scripts/benchmark.sh --mode=validation --memory --json --iterations=1000 --samples=7 > build/perf-validation-before.json
build/ldc2/benchmark_runner --mode=spans --memory --json --iterations=1000 --samples=7 > build/perf-spans-before.json
build/ldc2/benchmark_runner --mode=tree --memory --json --iterations=1000 --samples=7 > build/perf-tree-before.json
```

Wrap direct runner invocations in `timeout --kill-after=5s 120s` in automation.
Increase iterations for tiny or invalid cases until clock resolution is negligible;
reduce them for slow cases while keeping paired engines at equal counts. Use at
least seven measured samples, record mean/min/max and raw reports, and repeat
near-threshold results in three independent runs on an otherwise idle machine.
A pass requires every target case to remain within 5× in those runs. Archive
compiler flags/versions, CPU, revision and dirty source hashes with each report;
the existing comparison script provides this metadata when a Rust comparison is
also wanted. Chumsky and Pegged are context, not the acceptance denominator.

Remaining measurement work is targeted: profile CPU and allocation sites on small
JSON, long strings, whitespace-heavy input, deep nesting, and ambiguity; calculate
per-row ratio and required improvement `current ratio / 5`. Extend equal-output
adapters to arithmetic, CSV, numbers, and PEG grammar parsing before claiming
that the target covers all handwritten benchmark programs. The legacy mixed
suite is useful for regressions but cannot establish equal-work ratios.

## 1. Replace per-request malloc with stable slab allocation

**Files:** `src/npegged/storage.d`, allocation callers in `src/npegged/peg.d`.

Allocate aligned POD objects by advancing a cursor within slabs. Use dedicated
blocks for oversized requests; preserve stable addresses and destructor-owned
release. Preserve `T.init`, including nonzero defaults. Start with bounded slab
sizes and measure small-input overhead before tuning growth.

Keep actual allocator calls, logical payload bytes, and reserved bytes distinct.
Charge memory limits against reserved bytes, including headers/alignment; avoid
reserving a slab larger than the remaining budget when the request itself fits.
Define sticky failure behavior and overflow checks. Test alignment, exact limits,
allocator failure, oversized requests, and two simultaneously live results.
Do not recycle result storage through ParseContext without an explicit borrowing
contract. A bump arena alone does not remove excessive output or retained scratch.

**Exit:** substantially fewer system allocation calls on long inputs, stable
ownership and accounting, and no unexplained per-case time or memory regressions.

## 2. Generate recognition paths and cheap speculative failures

**Files:** `src/npegged/peg.d`, `src/npegged/grammar.d`.

Introduce compile-time check, span, and tree modes. A check result needs status
and offsets, not ParseTree children or match arrays. Propagate check mode through
discard and lookahead, and through sequences, choices, repetition, and rules.
Do not merely clear output after parsing. Begin with action-free grammars;
actions that inspect/change trees need a declared contract or a conservative
fallback. Include execution mode in memo identities or use isolated caches.

Represent ordinary mismatch with offsets and static expectation identifiers.
Materialize public diagnostic trees at the API boundary on failure, preserving
furthest failure, expectation ordering, and lookahead isolation. Normal repetition
termination and rejected alternatives on valid input must not allocate diagnostic
snapshots. Keep resource exhaustion distinct from syntax mismatch.

**Exit:** the validation adapter calls a real recognizer, discarded whitespace
creates no output, and valid recognition allocates no match/child/failure arrays.
Report stack and memo costs separately; do not label recognition zero-memory.

## 3. Fuse safe scalar token scanners

**Files:** grammar emission and terminal/repetition combinators.

Specialize discarded whitespace and fused repetitions of ASCII ranges/classes
into a byte loop with one final span. Then add ordinary JSON string runs with
escape/control-byte fallback, identifiers, and numeric components. Preserve
UTF-8 behavior: arbitrary Unicode ranges and `any` are not byte classes.

Return slices into owned input for proven contiguous, unmodified captures.
Retain concatenation for captures with discarded gaps or action-modified text;
`fuse!(a, discard!b, c)` must still capture `ac`, not `abc`.

Preserve empty matches, successful end offsets, failure positions, CTFE behavior,
and documented resource-limit accounting. If fused operations change step units,
define and test the new contract explicitly rather than silently disabling limits.

**Exit:** token length no longer determines allocation count for eligible spans;
long strings and whitespace show measured improvement in all applicable modes.

## 4. Remove unnecessary memo work and widen safe prediction

First benchmark existing `Memoization.no` on action-free JSON and other grammars
without left recursion. Retain explicit packrat control for backtracking-heavy
grammars. Add memo hits/misses, seed-growth iterations, invalidations, entries,
and bytes as optional counters outside the normal fast path.

Then use a structured expression graph for fixed-point nullability/FIRST analysis
and left-recursive strongly connected components through nullable prefixes.
Ordinary recursive nesting is not left recursion. Preserve seed growth where
needed; selective caching must retain dependencies needed by seed invalidation.
Do not change global defaults based only on JSON.

Extend the existing predictive-choice implementation to safe choice unions and
nullable prefixes. Handle spacing explicitly: skipping it once is only valid
when it preserves commitment, captures, actions and failure semantics. Unknown,
nullable, overlapping or Unicode-sensitive alternatives retain ordered fallback.

**Exit:** compare memo-on/off/selective on JSON, arithmetic, left recursion and
shared-prefix ambiguity; show no exponential regression or changed PEG semantics.
Prediction improves cases whose generated choices currently fall back.

## 5. Emit compact outputs directly

Add a result-owned compact representation of token spans and concrete value
nodes (kind, begin/end, parent or child indices). Generate only requested records;
avoid duplicating flattened descendant match arrays at every ancestor and avoid
projecting a generic tree into the benchmark's concrete tree. Use geometric
builders and transactional output checkpoints for speculative parses.

Preserve the legacy ParseTree API as a distinct supported path. Input borrowing
may be an explicit opt-in API with a lifetime contract; include input copying in
owned-mode timings. Check mode should omit copies when its synchronous lifetime
allows it. Do not hide conversion, disposal or ownership costs outside timing.

**Exit:** spans/tree adapters produce the same records directly, with storage
proportional to retained output and bounded scratch. Re-evaluate the 5× matrix;
profile remaining gaps before adding further machinery.

## 6. Only address measured residual bottlenecks

If scalar scanning dominates, add bounded SIMD delimiter scanning with portable
scalar fallback, safe tails, and CPU/compiler selection. Measure short tokens too.

General DFA generation is deferred. Ordinary regex NFA/DFA conversion changes
PEG semantics: `('a' / 'ab') 'c'` rejects `abc`, and `'a'* 'a'` rejects `a`.
Restrict compilation to a proven-safe subset or preserve PEG commitment explicitly;
cap generated states and CTFE cost. Avoid unconditional longest-prefix acceptance.

Streaming callbacks are also deferred: speculative choices and seed growth require
rollback or delayed commitment, and arbitrary external effects cannot be undone.
Neither SIMD nor streaming is a prerequisite for the initial 5× attempt.

## Delivery gates

Land and measure one change at a time. After every stage, publish paired per-case
ratios, MB/s, allocation calls, payload/reserved bytes, and valid/invalid behavior
for every mode. Keep an optimization only when its benefit or necessary capability
justifies its complexity; investigate regressions beyond sample noise. Stop adding
performance machinery once the covered target matrix consistently passes.

Runtime changes must preserve druntime-only linking, `@nogc nothrow`, CTFE,
move-only ownership and explicit errors. Require adjacent contract-mirroring unit
tests, >90% line/branch coverage in each `src/` module, timeout-bounded integration
tests, dfmt, DMD/LDC/GDC warning-free builds, ASan/LSan, Valgrind, and the active
pre-commit checks. This documentation revision does not claim those runtime checks
were executed or that the 5× goal has already been achieved.
