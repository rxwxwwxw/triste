# R06 — shared snapshots in recursive compact output

Decision: retain only behind the explicit build flag and context opt-in.
No default parser policy changes. Test-first commit: `ae3fa22`; implementation
and this evidence are committed together (see git log).

## Supported policy and reference fallback

Build with NPeggedSharedOutput and request ParseContext.sharedOutput. A generated
eligibility enum permits only closed, action-free, parameter-free grammars with
memoization, left recursion, a compiled compact selector, and selected recursive
output. Opaque/action-bearing/composed entry points keep the reference path.
Normal legacy PEG/CSV/JSON controls also retain their original path.

The initial policy requires maximum step/depth/parse/output arena budgets and no
semantic trace callback. The result arenas are constructed internally with the
standard allocator. Finite budgets and tracing keep the existing flat output
mechanism. Both input ownership modes retain their original contracts.

Sharing begins at 4 KiB of logical snapshot data, the existing arena slab size.
Small snapshots retain bulk copying: allocating immutable leaves and links must
pay for itself through subsequent reuse. The full matrix measures the cutover
and small cases as well as intended large workloads.

## Soundness and resource accounting

The live record buffer remains flat. Successful shared replay records an immutable
span plus its actual external parent. Spans are ordered and disjoint. Snapshot
composition reuses only complete spans still known unchanged; unproven records
are frozen in dense leaves, split whenever their external-parent attachment
changes. Internal parent links remain local to their leaf. This does not infer a
stable prefix across seed growth, ordered choices, or replacement.

`finish` invalidates a span containing the mutated node. Generated capture
wrappers finish only their own fresh node, outside all replay spans; a debug
assertion checks that structural invariant without adding release-path replay
bookkeeping. Partial rollback drops
the whole intersected span. Exposing mutable `nodes` drops all provenance.
Old frozen handles remain immutable for their parse-arena lifetime. Existing
broad memo invalidation and active-seed handling are unchanged.

RecordSnapshot keeps its original three-word layout, so merely compiling the
experiment does not enlarge memo entries or move finite-memory failure points.
An internal shared snapshot uses an odd pointer in an empty slice; it is decoded
only by an enabled internal parser buffer, never dereferenced as a CompactNode.
The factory uses aligned arena-owned fragments. Generic public restore/freeze
APIs continue treating all empty slices as empty, including unaligned empty
views; regression tests exercise that boundary. No new resource owner or cleanup
protocol is introduced.

Replay still materializes all records. Its arena-backed traversal workspace is
reused geometrically within the parse, avoiding a new depth-sized allocation on
each seed replay. R05's public one-shot API keeps its allocation/budget behavior.
Allocation failures remain sticky, and partial replay/span-registration failure
restores the previous logical output length. All runtime operations are @nogc
nothrow. All new work counters compile out of timing builds.

## Verification

The oracle compares ordinary and experimental binaries, and compares policy off/on
within each experimental binary. Its complete deterministic transcript includes
status, success, end, exact failEnd, every record field, action/trace sequences,
and inactive-path arena accounting. It covers both ownership modes; direct,
indirect, mutual, nullable, nested and predicate recursion; longest choice;
replacement/backtracking; EOF/NUL/non-ASCII; exhaustive tiny strings; finite
step/depth/memory/output limits; and action/opaque/tracing fallback. Diagnostic
positives prove actual shared snapshots and subtree reuse.

Run `bash scripts/shared-output-check.sh` for the full DMD/LDC × backend × memo ×
projection matrix (all rules, root only, and selected descendants with omitted
ancestors). METRICS=0 also exercises uninstrumented builds. Every runner
has a 45-second internal alarm, a 60-second timeout, and a 4 GiB ceiling.

Source-adjacent units test span invalidation, parent rebasing, checkpoint clipping,
workspace reuse, ABI size, generic empty snapshots, and sticky/partial allocation
failure. `SHARED_OUTPUT_COVERAGE=1 bash scripts/coverage.sh` includes the oracle in
DMD line/GDC source-branch collection. All executable src modules exceed 90% in
both; logs and source/coverage manifests are in verification/. ASan/LSan, Valgrind
and flagged DMD/LDC -vgc checks pass. R05 compatibility oracles also pass.

## Measurement

`python3 scripts/shared-output-scaling.py performance/results/R06/matrix` builds
separate ordinary-reference, compiled-off control and enabled-candidate cohorts.
Both backends/memo policies and root/all projections are paired. Instrumented
binaries measure work separately from three timing runs × seven samples × four
parses. Data includes complete output checksums, offsets, allocations, both arena
payload/peak counters, snapshot copies, restores and provenance work. Repository
PEG/CSV/JSON controls retain their own full/combinator grammar modes, consistently
across all three policies. Compilations can overlap; timed runs follow the compile
barrier. Runs have 60-second timeouts and 4 GiB address-space ceilings.

The complete matrix contains **34,272 timing samples**, **1,632 counter samples**
and **48 cohorts**. All 68 cases per cohort completed. Cross-policy output
signatures match, and compiled-off/root-only/legacy-control arena footprints
match the ordinary build exactly. [Provenance](provenance.json) identifies the
source commit plus dirty-tree hashes; ordinary reference means the same pinned
source without NPeggedSharedOutput, not a historical executable.

See [all timing tables and worst cases](timing-summary.md), [every paired
ratio](ratios.csv), [machine-readable analysis](analysis.json), and
[copy/replay/retention plots](copying-and-memory.svg). Every timing cohort has
three independent runs of seven samples. Candidate and compiled-off control use
the exact same executable, toggled by a startup environment variable.

At 2,048 terms with valid input and all named output, candidate/reference medians are
**0.388–0.436** across both backends and memo policies. Every corresponding
individual run improves: ratios range **0.383–0.448**. At 512 valid sibling expressions,
ratios are **0.255–0.293**; the gain is not confined to one flat expression.

For combinator/selective at 2,048 terms:

| Measure | Direct reference | Direct candidate | Indirect reference | Indirect candidate |
|---|---:|---:|---:|---:|
| Snapshot bytes copied | 134,217,728 | 262,112 | 402,522,112 | 371,296 |
| Flat replay bytes | 134,348,768 | 134,348,768 | 402,718,656 | 402,718,656 |
| Retained arena bytes | 134,832,887 | 1,580,920 | 403,426,909 | 2,263,416 |
| Final nodes | 4,097 | 4,097 | 6,144 | 6,144 |

Snapshot work is a fixed small-copy prefix plus linear freezing after the
cutover. Over 512→2048 terms its measured exponent is 0.34–0.37, reflecting that
constant prefix; retained arena exponents are 0.81–0.83 versus 1.98–1.99 in the
reference. **Flat replay remains quadratic** (exponent 2.00), and timing exponents
remain approximately quadratic too. This removes one quadratic mechanism and
reduces retained memory; it does not make all record generation linear.

## Regressions and stop decision

Do not promote this policy to a default. Valid all-output JSON controls range
1.050–1.246× reference, CSV 1.069–1.102× and PEG 1.065–1.152×; compiled-off
controls incur much of this cost too. The experiment increases builder state and
adds snapshot/provenance checks even when no large shared snapshot is reached.
Valid small sibling cases range 0.997–1.113×. All raw results remain visible.

The worst median is **1.601×** on a 16-term invalid indirect chain with direct/full
memoization; its compiled-off control is **1.942×**. Per-run candidate ratios are
1.692/0.726/1.604. Other tiny cases show similar run-to-run variation, so these
numbers do not support a precise attribution of small-case overhead. They remain
an unresolved barrier to broader adoption, rather than being discarded as noise.
No new work-growth mechanism or scaling regression appears in the tested flat,
nested or sibling cohorts. The repeated large-output gains and deterministic
copy/retention reductions justify keeping the experiment available for that
explicit use, without enabling it in ordinary builds.

Descriptive compile-wall candidate/reference ratios have median 1.032 and maximum
1.038 across the eight uninstrumented configurations. Each unique binary was
compiled once with two concurrent jobs; this is not a repeated compiler-cost
benchmark. Timed runs began only after the compile barrier.

R03 remains rejected, so R07's prerequisite that both experiments passed is not
met. No combined invalidation/snapshot policy or 2×2 combination claim is made.
The next independent roadmap milestone is H01.
