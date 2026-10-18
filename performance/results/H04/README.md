# H04 — rejected local memoization experiment

The candidate was **rejected and rolled back** after repeated large-case
regressions. No H04 runtime or generator policy remains in production.
`candidate.patch` preserves the tested implementation behind NPeggedLocalMemo;
the descriptions below refer to that archived candidate. H03 is unchanged.

## Proof and compatibility

H02 knowledge/effect facts alone are insufficient. A pure scanner invoked at
repeated overlapping positions can do more work without its cached result. The
new `GrammarAnalysis.boundedWork` proof admits only input-independent primitive
work and closed combinations of such work. It rejects unbounded repetition,
scanner wrappers, unresolved references, all call cycles and effects. Primitive
FIRST/nullability facts do not establish bounded work: identifier and spacing
scans stay cached. Recursive rules and transitive recursive bodies keep memo
entries; seed growth, dependencies and invalidation are unchanged. Repeating a
bounded rule cannot introduce an input-length factor into the work per call.

Generated `npeggedLocalMemoRules` identifies conditional bypass candidates;
`npeggedLocalMemoEntries` separately identifies proven effect-free API closures.
The bypass requires both proofs, runtime recognition/records, no tracing,
unlimited context and actual arena budgets, standard allocators and healthy
status. Opaque/actionful/unproven composed callers cannot grant permission, since
they can observe or change steps, depth, input and limits. Existing eligibility
report `memoized` remains true: memoization is still compiled and used outside
the guarded context. The metadata describes the conditional relaxation.

Full trees deliberately keep the reference policy. An early oracle failure on
`Probe <- (&Atom Atom '!' / Atom '?') eoi` with empty input demonstrated that
cached failure replay can retain a named `failedChild` where fresh execution
retains an anonymous primitive failure. Changing only the amount of work would
therefore change observable trees. Isolated action tree fallback also keeps the
reference policy. The final fixture retains this regression case.

## Verification and reproduction

Test-first commit: `80cf8e4`. `scripts/local-memo-check.sh` compares full memo with
selective memo inside each binary (the original conservative policy caches every
fixture rule), then compares ordinary and opt-in transcripts. The mixed grammar
contains bounded pure rules, an opaque sibling, an unbounded scanner, overlapping
backtracking/predicates, consuming cycles and direct/indirect left recursion.
A separate action-bearing variant verifies callback state/order and fallback.
Recognition, borrowed/owned records, exact full trees, failures and finite
step/depth/parse/output budgets are covered. Full-tree and guarded-off contexts
also require exact arena charges and memo counters. Positive checks require
fewer memo calls and requested bytes. Both direct and combinator backends run on DMD/LDC, separately and with H03
and H04 together.

Memory checks: `scripts/local-memo-memory-check.sh`, bounded to 4 GiB and explicit
timeouts. ASan/LSan uses the druntime-compatible native-stack setting documented
in H01. Memcheck disables conservative GC scanning and supports the fixture's
large stack frame with `--max-stackframe=8388608`; no suppressions. Native/ASan
and Memcheck transcripts must match. Final logs and source coverage evidence are
in `verification/`. Coverage was collected with
`LOCAL_MEMO_COVERAGE=1 PURE_ISLANDS_COVERAGE=1 bash scripts/coverage.sh`.
Changed-module line/branch percentages are analysis 99.71/94.04, generator
98.58/90.25 and runtime 95.52/91.37; every executable source module exceeds 90%.

Measurements: `scripts/local-memo-benchmark.py performance/results/H04/matrix`,
then `python3 performance/results/H04/report.py`. All eight binaries are compiled
before timing; source/raw/binary hashes and compiler commands are preserved.
Timing omits counters, warms up, batches calls and includes result destruction.
Three runs × seven samples cover 102 cases per backend: mixed Root, unbounded overlapping
scan, direct/indirect recursion, action grammar, finite budgets, full trees and
repository JSON/CSV/PEG. Counter builds run separately. The stop rule remains:
roll back on worse scaling; do not infer default promotion or the global ≤5× gate.

## Outcome: reject and roll back

All 8,568 uninstrumented timing samples and 408 counter samples pass their
output checks. At 1,024 tokens, native recognition takes 0.130× reference time
(combinators) or 0.176× (direct); borrowed/owned records take 0.360–0.371×.
Memo calls drop from 4,101 to 1 and recognition requested bytes from 376,640 to
592. These are real benefits in the intended mixed pure/opaque case.

However, full-tree controls retain identical memo counts and requested bytes but
slow to 1.977× (direct) and 2.010× (combinators) at 1,024 valid tokens. Individual
run ratios are 1.982/2.012/2.008 and 2.061/1.982/1.994 respectively. The worst
case is valid finite-budget recognition at 1,024 tokens: 2.272× in combinators
(three runs 2.248/2.272/2.254), with direct at 2.120×. This repeated large-case
regression and worse growth in guarded-off controls fail H04's stop rule.
From 1 to 1,024 tokens, the candidate/reference growth ratio is 1.913–2.102
for full trees and 1.866–2.046 for finite recognition. These are measured
finite-range growth comparisons, not a claim of a different asymptotic order.
Equal counters and allocation footprints do not establish equal CPU cost; the
underlying compiler/runtime cause was not established. No default or opt-in
production change is retained.

`ratios.csv` and `timing-summary.md` report every case and endpoint scaling.
`timing-ratios.svg` plots the intended and recursive/overlap controls. The native
unbounded overlap/recursion endpoints alone are not grounds to accept a candidate
that regresses other required modes. No global acceptance-target claim is made.

To reproduce the candidate, use an isolated checkout at test-first `80cf8e4`,
apply `candidate.patch`, and copy the final tests/drivers/scripts from this result
commit. Then run the oracle, memory, coverage and benchmark commands above.
The raw metadata source hashes, rather than the dirty source-head label, identify
the exact measured files. The oracle script requires the archived patch; it is
not wired into production validation after rollback. Candidate coverage/memory
evidence is retained as such. Final production sources match the verified H03
source hashes; `verification/rollback.json` records that check.
