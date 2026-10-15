# NPegged performance review

Review date: 2026-10-14. This is a source review and implementation proposal;
the priorities below are hypotheses to measure, not measured speedup claims.

Validation: `DC=ldc2 scripts/benchmark.sh --iterations=20` built and completed
all ten cases. As a smoke baseline, JSON.Small took 0.87 ms for 20 parses
(60 bytes each), and JSON.Medium took 4.60 ms (317 bytes each): roughly
1.4 MB/s for both. These are single-run, full-tree measurements with the
benchmark limitations discussed below; no chumsky comparison was executed.
Only documentation was changed; runtime validation suites were not rerun.

## Main finding

The next work should reduce allocation and unused output construction before
attempting general DFA compilation or SIMD. The current runtime constructs
matches, children, and diagnostic trees throughout parsing, including inside
expressions whose outputs are subsequently discarded. Its arena performs one
`malloc` per allocation. These costs remain after terminal matching becomes fast.

Chumsky offers a useful architectural reference: its release notes describe
avoiding output construction when a combinator ignores that output, and its
public interface supports check-only parsing, zero-copy outputs, and opt-in
memoization. See [release notes](https://github.com/zesterer/chumsky/releases)
and [project documentation](https://github.com/zesterer/chumsky).
Published throughput on another machine and grammar is not a local target measurement.

## What the existing roadmap gets right, and what needs correction

The ASCII range fast path, literal comparison fast paths, non-memoized rule
branch, character-class masks, and predictive-choice combinator exist.
However:

- `storage.d: Arena.allocate` calls its allocator for every request and links
  every allocation into a list. There is no slab or bump allocation, despite
  the roadmap's reference to arena pooling.
- `peg.d: repeat` still invokes a complete parser and collects outputs for
  every character. Character-class masks do not yet imply the tight repeated
  scanner illustrated in the roadmap.
- `grammar.d: grammar` defaults to `Memoization.yes`; the non-memoized fast
  path is available but is not the default for the example grammars.
- Predictive dispatch is narrower than the JSON example suggests.
  `computeFirstSet` does not handle `wrapAround`, general choice unions, or
  nullable sequence prefixes. Spaced arrows wrap primary expressions in
  `wrapAround!(Spacing, ..., Spacing)`, blocking analysis of common rules.
- The roadmap's speedup ranges are not established by repository measurements.
  They should remain hypotheses until each change is benchmarked separately.

## Proposed order of implementation

### 1. Establish a trustworthy comparison

The current benchmark compares NPegged's owned input and full generic parse
tree against handwritten parsers returning a boolean. That measures different
amounts of work. The NPegged JSON grammar also accepts a different language
from the handwritten JSON parser: its number rule omits negatives/exponents,
and its string fallback is more permissive. Require equivalent acceptance and
complete input consumption before comparing speed.

The benchmark builds with release flags, but correctness checks are assertions.
Replace these with explicit status checks outside timing. Feed results into an
observable checksum or equivalent barrier: the handwritten JSON entry point is
`pure`, so discarded boolean results are especially vulnerable to optimization.
Check generated code to establish whether elimination actually occurs.

Measure separate modes: validation, token/span output, and full tree output.
Add chumsky implementations using the same corpus and output obligations;
record compiler versions, flags, CPU, repeated-run dispersion, and MB/s.
Include small inputs, large strings, escape-heavy strings, whitespace-heavy
documents, deep nesting, ambiguous grammars, and invalid inputs.

`GC.stats()` does not count NPegged's `malloc` traffic: zero GC bytes does not
mean zero allocations. Add allocator-call counts and requested/reserved bytes.
The current arena high-water metric is cumulative allocation, not live output
size. Also correct handwritten allocation normalization: the runner can execute
5000 handwritten iterations but divides allocated bytes by the requested count.

### 2. Implement a real bump arena

Allocate aligned objects within reasonably sized slabs, with dedicated blocks
for oversized requests. Keep pointers stable and release all blocks through
the existing move-only owner destructor. Preserve initialization guarantees:
memo buckets and other callers rely on zero/default initialization.

Define whether the memory limit accounts for reserved slab bytes or logical
requests; report both. Test alignment, overflow, limit boundaries, allocator
failure, and independence of simultaneously live results. Context reuse alone
currently saves no storage: each parse creates a fresh result-owned arena.
An optional reusable workspace needs an explicit lifetime contract before it
can recycle storage borrowed by results.

### 3. Push output suppression into child parsers

Introduce compile-time execution modes such as tree, matches/spans, and check.
`discard` and lookahead should invoke eligible children in check mode;
`defined` should create a child node only when the enclosing mode needs it.
Keep the existing full-tree API as a supported mode.

Currently `transform(':')` first runs its child normally, then clears its
matches and children. Whitespace is `discard!(zeroOrMore!blank)`, where blank
itself tries several literals and choices. Successful whitespace and normal
loop termination therefore allocate output and failure data that are unused.
This occurs frequently because `wrapAround` scans spacing before and after
each wrapped primary.

Actions can inspect and alter trees, so output suppression requires an explicit
action contract or a conservative fallback. Memo keys/results must distinguish
execution modes; a check result cannot satisfy a later tree-producing request.

### 4. Add specialized scalar scanners

Start with discarded whitespace and fused repetitions of ASCII ranges/classes.
Generate a tight byte loop and one final match, rather than a ParseTree and
match allocation per byte. Extend to ordinary string spans with escape fallback,
identifiers, and numbers after the simpler cases are measured.

Preserve step/resource limits, failure offsets, empty matches, and CTFE behavior.
Do not reinterpret Unicode ranges as raw byte classes.

`transform('~')` currently concatenates every collected match into a fresh byte
buffer. For proven contiguous, unmodified matches, return a slice into the
result-owned input instead. A blanket `input[begin .. end]` substitution is
incorrect: the existing fuse test discards the middle character of `abc` and
expects `ac`. Actions and spacing can also make captures non-contiguous.

### 5. Make memoization selective

Benchmark the existing `Memoization.no` option first on grammars without left
recursion. Then analyze the rule graph and nullable prefixes to identify left
recursive strongly connected components, rather than equating all recursion
with left recursion. Ordinary nested JSON recursion does not require seed growth.

Retain seed-growth support where needed and explicit packrat options for
backtracking-heavy grammars. Removing memoization everywhere can turn repeated
work exponential. Measure memo hits, misses, table bytes, and invalidations to
choose rules deliberately.

### 6. Separate expected mismatch from diagnostic materialization

`State.failure` allocates a match slice; sequence failures allocate nested
failed-child snapshots. Routine alternatives, lookahead, whitespace, and
repetition termination can trigger these paths on valid input.

Represent speculative failure with offsets and static expectation identifiers,
then materialize the public diagnostic structure when needed. Offer richer
diagnostics as a measured mode. Preserve furthest-failure selection and
lookahead isolation; failure suppression must not erase actionable diagnostics.

### 7. Improve predictive analysis and reduce repeated output copying

Replace string-pattern FIRST analysis with a structured expression
representation and fixed-point nullability/FIRST computation. Handle choices,
nullable prefixes, builtins, and spacing conservatively. Spacing cannot simply
be ignored before dispatch: inspect the byte after valid spacing, and preserve
custom Spacing actions and failure behavior.

For overlapping FIRST sets, dispatch to an ordered subset of viable branches
instead of abandoning prediction altogether. Preserve PEG priority and
diagnostics; put a bound on compile-time table/code growth. The current ubyte
branch table also needs an explicit branch-count limit or a wider index.

After temporary output construction is reduced, profile `Builder.put` and
`defined`: enclosing rules repeatedly copy flattened match lists and full
ParseTree values. Consider a compact node/span representation and an opt-in
API that avoids storing every descendant match at every ancestor. Retaining
all legacy views has an unavoidable storage and copying cost.

## Why general DFA and streaming should come later

Being nonrecursive is insufficient to justify ordinary Thompson NFA to DFA
conversion. PEG ordered choice and repetition have different semantics from
regular-expression backtracking or longest-prefix acceptance:

- `('a' / 'ab') 'c'` rejects `abc`; a regex union recognizes it.
- `'a'* 'a'` rejects `a`; a regex repetition followed by `a` recognizes it.

Start with a proven-safe scanner subset or a compiler that preserves PEG
commitment. Differentially test successful offsets, captures, failures, and
limits, not just acceptance. Large dense DFA tables can also hurt cache use and
CTFE compilation time.

SIMD becomes attractive once profiling shows time in allocation-free scalar
scanning. Provide safe bounded loads, scalar tails, and portable compiler/CPU
fallbacks; short tokens may not benefit.

Streaming callbacks require rollback or delayed commitment: ordered choice and
left-recursive seed growth can abandon successful subparses. Arbitrary external
callbacks cannot be undone. A check mode is a simpler initial route to reducing
output work. Event parsing also still uses recursion state, and memoized parsing
can allocate; “zero bytes” and handwritten-equivalent speed need measurement.

## Acceptance criteria

Land one optimization at a time with before/after measurements for all output
modes, allocator counts, and representative valid/invalid inputs. Preserve
`@nogc nothrow`, druntime-only linking, resource limits, CTFE compatibility, and
move-only result ownership. Runtime changes need adjacent unit tests, >90%
line/branch coverage, timeout-bounded integration tests, dfmt, all three
compilers, and ASan/LSan/Valgrind checks required by AGENTS.md.

The first implementation sequence should be benchmark corrections, bump arena,
discard/check specialization with scalar token scanning, and selective
memoization. Whether this reaches chumsky-level throughput must be answered
with equivalent local benchmarks; the current full-tree versus boolean results
cannot establish that gap.
