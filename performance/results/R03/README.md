# R03 — narrower invalidation prototype: rejected and not installed

**Decision:** apply the plan's stop/rollback rule. The prototype improves deep
nesting but introduces quadratic recognition work on sibling nested expressions.
The production parser retains R02's original broad invalidator. No new runtime
policy, producer annotation or algorithm from this experiment is installed.
`candidate.patch` preserves the exact tested implementation for review.

## Prototype and proof boundary

The isolated worktree is based on R02 commit `09834c0`. An explicit
NPeggedNarrowInvalidation build plus context opt-in enables the experiment.
A small grammar.d handshake emits an internal UDA only for a whole grammar with
selective memoization, no actions/opaque references/parameters/predicates, and one
non-nullable left-recursive rule. This deliberately avoids a new rule-local
analysis system. Runtime guards require recognition mode, no semantic trace
callback, maximum step/depth/context-memory/actual-arena limits, and the standard
allocator. Unsupported entries and modes retain broad invalidation. size_t.max
budgets still use the existing overflow-safe tick/allocation checks.

Each memo entry records a conservative minimum consulted seed position and its
active evaluation parent. Active seed reads and completed hits propagate that
position and proof taint through active memo callers. At head growth, proven
completed entries with dependency positions beyond the head may survive. Unknown
entries always retire under the original predicate. Active entries are preserved;
retirement still unlinks both the entry list and hash bucket. Unit tests assert
these links, dependency propagation and fallback guards.

The extra producer handshake is the only scope addition beyond peg.d/tests:
runtime code cannot infer absence of actions or opaque calls from a body pointer.
No static purity promise is guessed from rule names or caller assertions.

## Complete experiment

All 25 workloads completed for both combinator/direct backends, with reference,
compiled-but-off control, and enabled candidate builds. Each timing case has
three independent runs × seven samples × 32 parses. Counter builds use separate
binaries and one parse/case: **3150 timed samples and 150 counter samples**.
Compiler flags/version, CPU, source/driver hashes, consumed/failure offsets,
60-second deadlines and 4 GiB limits are retained. All timing builds exclude
metrics. The control isolates field-layout/build overhead from retention itself.

See `timing-summary.md` and the full raw CSVs. Key median candidate/reference ratios:

| Backend | Flat 8192 terms | Nesting depth 8 | 512 sibling expressions |
|---|---:|---:|---:|
| combinators | 1.031 | 0.023 | 11.315 |
| direct | 1.084 | 0.025 | 12.092 |

The sibling regression repeats in **every** independent run: combinators
11.48/11.42/11.10×, direct 12.09/12.07/11.93×. Shared-machine noise cannot explain
the measured work-growth change; no speed promotion is claimed.

For combinator recognition at 128→512 siblings, reference invalidation visits grow
514→2050 (about 4×), but candidate visits grow 16768→263680 (about 16×). At 512,
the reference retires 512 entries and keeps the active list short. The candidate
retires none, records 131328 repeated keep decisions, performs five bucket
allocations/rehashes (724 rehashed entries), and retains 73774 arena bytes versus
45056 for the reference (57344 for the control). Keeping an arena-owned object
valid does not save its allocation—the reference already retains retired objects
until parse disposal. It expands the repeatedly scanned list and bucket working
set instead. `narrow_kept` counts repeated skip decisions, not unique entries.

At nesting depth 8 the reference has 1533 memo calls / 4599 invalidation visits;
the candidate has 35 / 81. That intended improvement is real, but insufficient to
accept the regression on a flat sequence of the same nested-expression grammar.
Rescuing it would require a dependency retirement index/worklist and new fallback
proofs. That is a separate experiment, not a hidden memo-table rewrite in R03.

## Correctness and verification

Both compilers pass source-adjacent prototype units and the targeted oracle over
direct, indirect, mutual, nullable, cached-transitive, opaque/action, nested,
tracing and finite-budget cases. Exhaustive four-byte tiny inputs compare status,
success, consumed end and exact failEnd. The F02 differential matrix also passes
under DMD/LDC with policy off/on, including maximum-budget opt-in cases, full
ParseTree/record fields, actions, trace sequences and CTFE. Metrics assert the
intended case actually uses narrow invalidation and unsupported grammars do not.

Prototype ASan/LSan and Valgrind pass; LSan ran outside the sandbox's ptrace
restriction. Valgrind uses the repository GC test settings, with zero errors and
zero definite/indirect leaks, without suppressions. `verification/` contains the
correctness and Valgrind logs. Source default-build coverage/full verification is
recorded under `../R02/verification`; no prototype source was promoted.

## Reproduce the rejected experiment

From the final checkout, create a scratch checkout at R02 (choose an unused path):

```
git worktree add --detach /tmp/triste-r03-replay 09834c0
git -C /tmp/triste-r03-replay apply /absolute/path/to/triste/performance/results/R03/candidate.patch
cp tests/narrow_invalidation.d /tmp/triste-r03-replay/tests/
cp benchmark/diagnostics/narrow_invalidation.d /tmp/triste-r03-replay/benchmark/diagnostics/
bash scripts/narrow-invalidation-check.sh /tmp/triste-r03-replay prototype
python3 scripts/narrow-invalidation.py /tmp/triste-r03-replay build/R03-replay
```

The driver compares that scratch candidate with the final checkout's unchanged
reference algorithm. `candidate-sources.json` pins the patch and reconstructed
source hashes. Do not apply the rejected patch to the production checkout. The
reference-only oracle can be run with `bash scripts/narrow-invalidation-check.sh .`.
