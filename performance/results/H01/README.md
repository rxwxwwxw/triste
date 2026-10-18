# H01 — explain current fast-path eligibility

The new cold `eligibilityReport!(memo, Selector, backend)` API returns explicit
status, typed rule rows and deterministic JSON (default) or text. Reporting is
opt-in and uses selective druntime GC, just like grammar generation. It does not
change a generated parser's policy, output, tracing or work limits.

```d
import npegged.grammar;
auto result = eligibilityReport!(Memoization.selective, void, ParserBackend.direct)(
    "Example: Root <- Leaf+ eoi Leaf <- [a-z]");
assert(result.status == Status.ok);
// result.report contains JSON; result.rules contains the typed decisions.
auto text = eligibilityReport!(Memoization.selective, void, ParserBackend.direct)(
    "Example: Root <- Leaf+ eoi Leaf <- [a-z]", EligibilityFormat.text);
```

Grammar errors, invalid report formats and invalid UTF-8 input return
Status.invalidInput plus Diagnostic; successful report metadata is meaningful
only when status is ok. UTF-8 validation keeps serialized reports valid JSON.
JSON escapes quotes, backslashes and every ASCII control byte. Rule and evidence
ordering follow source/analysis order and never depend on associative iteration.

## What the fields mean

The emitter captures its existing booleans after making its normal choices. A
report does not reimplement direct eligibility as a second optimization policy.
Scalar blocker lists explain the existing scalar predicate and are checked
against it in debug builds. Direct entry flags come directly from the decisions
that emit dispatch into `_direct_` functions; merely emitting an unused cursor
helper does not establish entry eligibility.

- `grammar`, `backend`, `memoPolicy`: the requested grammar and generation modes;
  memo `yes` means full memoization, distinct from selective.
- `conservative`, `unknownEvidence`: the existing whole-grammar conservative flag
  and structural unknown expressions/unresolved references that cause it.
  Unknown FIRST bytes on an understood Unicode terminal do not imply opaque calls.
- `actionRules`: rules triggering the emitter's existing textual action barrier.
  This is evidence for the current global decision, not a proof of reachable
  effects. A literal containing `action!(` can trigger the current barrier too;
  a source unit records that conservative behavior rather than changing it.
- Each row names the rule and its original frontend combinator expression,
  before DFA/direct rewriting, plus left recursion and actual memoization.
- `scalarEligible` describes scalar references from lowered callers;
  `directRecognition` and `directRecords` describe available entry dispatch.
  These are different decisions. `directFallback` explains recognition entry;
  records may still have a direct entry when recognition uses a combinator.
- `selectorConfigured`, `recordKind`, `recordSelected`, `recordLeaf` and
  `recordSubtree` expose the actual compiled selection. Unselected kind is
  uint.max. Availability of a record entry does not establish selector identity
  or bypass runtime guards.
- `fallbackModes` records trace/CTFE/full-tree fallback. The report does not claim
  that every call uses a direct entry, or predict budget-dependent DFA fallback.

Actual direct/selective rows from the fixtures without a compiled selector:

| Rule | Memoized | Scalar reference | Direct recognition | Direct records | Recognition fallback |
|---|---|---|---|---|---|
| Eligibility.Pure (unrelated action + opaque rule) | yes | no | no | no | grammar-action |
| Pure.Root | no | yes | no | yes | root-combinator |
| Pure.Leaf | no | yes | no | no | root-combinator |
| Rec.Root | no | yes | yes | yes | none |
| Rec.Expr | yes | no | no | no | left-recursion |

H02 will make *reported* effects rule-local. H03/H04 are separate policy changes;
this milestone retains the global action and conservative memo barriers.

## Verification

Test-first commit: `aefd42d`. The fixture initially fails because the API is
absent. `tests/eligibility_sources.json` pins 72 generated-source hashes captured
before implementation from R06 source, using the initial fixture's baseline
branch. Both compilers produced identical reference bytes.

`bash scripts/eligibility-check.sh` runs DMD and LDC with warnings as errors,
druntime only and no exceptions. Both pass all 72 combinations: six grammars ×
two backends × three memo policies × compiled selector on/off. The mixed grammar
contains an action, an opaque reference, left recursion and unrelated pure rules.
Other fixtures cover pure/recursive/parameterized/Unicode/empty grammars.

The fixture checks typed rows, repeated JSON/text determinism, consistency with
actual emitted direct entry calls, and retention across explicit GC collection.
Python parses all 72 JSON documents, checks the complete policy matrix and schema,
and hashes generated source against every pre-change golden. DMD/LDC JSON is
byte-identical. Native/ASan GC stress is selected by EligibilityGCStress.

Compilation has a 300-second timeout; every runner has a 45-second alarm, a
60-second outer timeout and a 4 GiB memory ceiling. The memory runner uses
MemoryMax=4G/MemorySwapMax=0 user scopes so ASan can reserve its shadow address
space. No Phobos imports or manual cleanup are introduced; fixture files use the
existing RAII File wrapper.

`bash scripts/coverage.sh` collects repository-wide DMD lines and GDC source
branches. Source-adjacent units cover formatting, empty/multiple rule rendering,
unknown evidence, action/opaque/recursive/parameter barriers, record metadata,
malformed input/encoding/format and the existing textual action barrier.
DMD/LDC differential, hot-path -vgc and staged-checkout hook checks also pass.
Final coverage summaries, compiler logs, source and transcript hashes are in
verification/. Changed modules have line/branch coverage of 99.67%/93.11%
(analysis) and 98.95%/92.99% (grammar). No parsing performance improvement is claimed.

## Memory-check configuration and limits

`bash scripts/eligibility-memory-check.sh` runs three ASan/LSan executions with
forced-GC stress and compares complete reports with the native fixture. It also
runs the same report workload through Memcheck without suppressions, with
`--DRT-gcopt=disable:1 parallel:0 cleanup:none` and no forced-GC stress.

On this installed LDC/LLVM/druntime combination, ASan fake-stack mode caused live
GC strings to be reclaimed during later generation. A debugger captured an
original JSON slice overwritten by subsequent text and another slice reclaimed.
ASAN_OPTIONS=detect_leaks=1:detect_stack_use_after_return=0 keeps roots on the
native stack; repeated forced-collection runs then agree exactly. Native DMD/LDC
also pass forced-collection tests. This is a configuration-specific observation;
report values retain ordinary GC ownership; the production parser policy is unchanged.

The [sanitizer documentation](https://github.com/google/sanitizers/wiki/AddressSanitizerUseAfterReturn#garbage-collection)
explains that fake stacks need GC integration, and the
[LDC maintainer discussion](https://forum.dlang.org/thread/fjdsmxirusasydlxrbxk@forum.dlang.org)
describes this configuration workaround. The existing make/validation ASan
commands now use it explicitly too. Heap, active-stack bounds and leak detection
remain enabled; stack-use-after-return detection is not claimed.

Explicit conservative marking under Memcheck reports undefined stack words inside
druntime's GC scanner. Therefore GC retention is covered by native/ASan runs,
while Memcheck covers all report construction, serialization and file operations
with collection disabled. No report operation or output check is skipped.

The final Memcheck log records zero errors, no definite or indirect leaks,
32 possibly lost bytes and 216 reachable bytes belonging to druntime, matching
the prior runtime checks. These are not described as zero bytes in every leak
category. Optimized LDC (-O3 with assertions retained) also passes all 72 cases
and returns byte-identical reports and generated source.
