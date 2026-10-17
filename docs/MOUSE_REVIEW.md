# Mouse 2.3: opportunities for triste

Review date: 2026-10-17. This is a source review of the vendored distribution,
not a benchmark or an implementation change. The sole implementation roadmap is
[PERFORMANCE_PLAN.md](PERFORMANCE_PLAN.md); suggested ordering here is review context,
not a second task queue. Mouse is by Roman R. Redziejowski;
its source is licensed under Apache 2.0. All Mouse-specific observations and
recommendations below credit that implementation. Links resolve to the local
sources inspected.

## What is most useful

| Priority | Mouse reference | Existing triste foundation | Useful next step |
| --- | --- | --- | --- |
| 1 | [ParserTest.java](../third-party/Mouse-2.3/source/runtime/ParserTest.java), [TestParser.java](../third-party/Mouse-2.3/source/TestParser.java) | `ParseContext.Metrics` and tracing in `peg.d`; benchmark and recursion scaling runners | Add opt-in per-rule rescans, memo reuse, and backtracking distance reports. |
| 2 | [Diagnose.java](../third-party/Mouse-2.3/source/peg/Diagnose.java), [PEG.java](../third-party/Mouse-2.3/source/peg/PEG.java) | Nullable/FIRST facts and recursion analysis in `analysis.d` | Explain dead alternatives, redundant optionals, nullable loops, and unproductive cycles before generation. |
| 3 | [Conflicts.java](../third-party/Mouse-2.3/source/explorer/Conflicts.java), [Tail.java](../third-party/Mouse-2.3/source/explorer/Tail.java), [Terminals.java](../third-party/Mouse-2.3/source/explorer/Terminals.java) | Byte FIRST sets, continuation analysis, predictive choices and scanner proofs | Expose conflict witnesses and add richer terminal-prefix proofs where byte sets are too coarse. |
| 4 | [RecClass.java](../third-party/Mouse-2.3/source/peg/RecClass.java), [Generate.java](../third-party/Mouse-2.3/source/Generate.java) | Left-edge SCC detection and runtime memo seed growth | Prototype generated recursive ascent for a narrowly proved subset of left recursion. |
| 5 | [ParserMemo.java](../third-party/Mouse-2.3/source/runtime/ParserMemo.java) | Full/selective memo policies and memo metrics | Experiment with small bounded caches for ordinary backtracking rules, independently of mandatory recursion state. |

## Measure repeated work, not just parser throughput

Mouse's test runtime distinguishes calls, rescans without reuse, reuse,
successful calls, failures without backtracking, failures with backtracking,
total backtrack distance, maximum backtrack distance, and its location.
It tracks previously visited positions even when the corresponding cached
result has been evicted. That distinguishes a rule that is naturally called
often from one repeatedly reparsing the same input.

Triste already counts memo calls/hits, seed growths, invalidation visits,
invalidated entries and snapshot bytes. Those counters should be retained;
Mouse suggests adding attribution by rule and input position. A report could
rank rules by rescanned bytes and failed-branch distance, then link the worst
position to a small input excerpt. This would make memo policy decisions much
better grounded than treating every non-left-recursive rule alike.

Use generated integer rule IDs and optional, parse-owned counter arrays;
avoid strings, hash allocation and callbacks in the default hot path. Exact
visited-position sets can be expensive: place them behind a profiling option,
charge their storage to the context budget, and distinguish exact from sampled
statistics. Measure profiling overhead separately. Backtrack distance is a
work indicator, not elapsed time or a complete count of bytes examined.

## Make grammar analysis explain itself

Mouse computes several expression attributes, including nullability, ability
to advance, and failure-related facts. Its diagnostics use them to flag nullable
repetition, alternatives hidden behind a never-failing alternative, redundant
optionals, and problematic recursion. Triste's `FirstFacts` already provides
nullable, known and EOF-related information, but not an equivalent public
explanation of all these conditions.

Add conservative failure/productivity facts with explicit unknown states.
For example, an empty first alternative makes later ordered alternatives
unreachable; a nullable repetition deserves a diagnostic even if runtime
progress guards prevent a hang. Preserve current accepted grammar behavior
initially by making these warnings, except where an existing contract already
requires rejection. Unknown external rules, parameters and actions must not
be classified as never-failing from incomplete information.

Mouse separately represents calls at the starting position and calls whose
surrounding sequence can consume no input in its `first` and `clean` relations
([Relations.java](../third-party/Mouse-2.3/source/peg/Relations.java)). That is
useful for explaining why a recursive component is productive or cannot make
progress. Triste already uses Tarjan SCCs: retain that scalable graph machinery
rather than automatically adopting Mouse's dense expression matrices and
transitive closures. Add labeled edges and cycle witnesses to the existing
analysis. Benchmark generation time and analysis memory on large grammars.

## Go beyond a first-byte collision

Mouse's explorer checks alternatives against alternatives plus their tails,
and repetition/optional bodies against their following tails. It retains
terminal pairs responsible for possible conflicts. Its string-literal test
proves disjointness when neither literal is a prefix of the other: `"ab"` and
`"ac"` can be distinguished although their first byte is identical.

Triste already has continuation and deterministic-region analysis; the new
opportunity is a user-visible explanation and richer proofs, not simply
adding FIRST/FOLLOW analysis again. Report the rule, expression, following
context, colliding terminals, and whether the collision is proved or merely
not ruled out. An LL(1) conflict is not a PEG ambiguity or grammar error.

For eligible literal-only choices, a priority-preserving trie or bounded
lookahead could dispatch on additional bytes. Preserve ordered choice for
prefix cases such as `"a" / "ab"`; do not replace it with longest matching.
Predicates, nullable paths, EOF, Unicode decoding, budgets and exact failure
offsets require separate proof or fallback. Mouse uses Java character-oriented
operations; triste's byte literals and UTF-8 ranges require their own rules.
Do not translate terminal-disjointness routines without testing complemented
classes, range boundaries and EOF explicitly.

## Recursive ascent is a research path, not a drop-in fix

Mouse groups left-recursive expressions into classes with entries, exits and
seeds. `Generate.generateCommonEntry`, `generateSeed`, `generateSequenceAscent`
and `generateClimb` generate procedures that parse seeds and climb through
predecessors within a class. Sequence ascent parses the suffix after the
already recognized leading expression. This offers a concrete alternative
to repeatedly evaluating an entire recursive rule from its starting position.

Triste's `State.memoizedRule` still snapshots output during seed growth and
calls `invalidateMemo`; the existing counters and recursion scaling tools
are suitable for measuring those costs. A specialized ascent backend might
reduce repeated parsing, invalidation and output copying. That is a hypothesis,
not a demonstrated complexity or speed improvement. Generated ascent can
also consume stack, so long operator chains and recursion depth budgets matter.

Mouse explicitly rejects some recursive forms and action combinations in its
diagnostics, including nullable-leading recursive sequences and certain actions.
Triste must retain its existing general fallback. Start with action-free direct
left recursion, then compare indirect and mutual recursion, ordered alternatives,
associativity, selected output, failure positions and resource limits. Matching
acceptance alone does not establish equivalent trees or action invocation order.

## Small caches are an experiment with a clear boundary

Mouse's memo runtime defaults its cache size to zero. When enabled, each cache
is a bounded circular array of phrases; lookup scans that array for the current
position. This can avoid a large general memo table when useful reuse is local.

Try capacities such as 0, 1, 2, 4 and 8 for rules selected by profiling, measuring
misses, rescans, allocation traffic and throughput. Eviction forfeits packrat's
general linear-time protection and can be disastrous on shared-prefix workloads.
Never evict active left-recursion seeds or mix optional result caching with the
state required for recursive correctness. Cache results must include the output
and diagnostic state required by triste's API; side effects need their existing
conservative treatment. Mouse's bound on phrase entries is not a bound on total
memory retained through phrase references.

## Other reusable design ideas

Mouse's [Phrase.java](../third-party/Mouse-2.3/source/runtime/Phrase.java) carries
a farthest-failure position and expected expressions, and its memo reuse propagates
that information. Predicate acceptance clears speculative failure history in
[ParserBase.java](../third-party/Mouse-2.3/source/runtime/ParserBase.java).
These are useful comparison cases for testing memoized versus uncached diagnostics
and predicate-local failures. Changing triste's diagnostic policy should be an
explicit API decision, not an incidental optimization.

Mouse's generator separates inline expression emission from generated subprocedures.
Triste already has a direct backend; use Mouse as a design reference for deciding
which small expressions to inline, while measuring generated source size, compiler
time, instruction-cache effects and runtime. Its Java object graph and vectors
are not suitable runtime storage models for druntime-only `@nogc nothrow` D.

The explorer's useful product is an explanation of grammar behavior. A text or
machine-readable analysis report fits triste better as a first step than porting
the Swing interface. Mouse can also be an independent oracle for a deliberately
restricted common grammar subset; align full-input acceptance and character
semantics first, and run every external parser test under a timeout.

## Suggested execution order and validation

1. Add per-rule profiling and a text conflict/optimization report. Correlate static
   collisions with measured rescans before changing memoization defaults.
2. Add conservative grammar warnings and literal-prefix proofs. Preserve generic
   parsing at every boundary where the proof is incomplete.
3. Run separate bounded-cache and recursive-ascent prototypes against current
   full/selective and combinator/direct configurations.

Use the existing benchmark corpus, shared-prefix workload and recursion scaling
runner. Add long common literal prefixes, nullable tails, productive and unproductive
cycles, long left-associative chains and invalid suffixes. Compare validation,
selected records and full trees separately; record exact acceptance, end/failure
offsets, output records, action traces, memory and step/depth limit behavior before
timing. Use the required DMD and LDC compilers, colocated contract-mirroring unit tests, timed
integration tests, coverage gates, GC diagnostics and sanitizer/Valgrind checks for
any eventual implementation. No numerical speedup is claimed by this review.

## Attribution and reuse record

Mouse 2.3, by Roman R. Redziejowski, is the source of the bounded phrase-cache,
per-expression profiling, grammar diagnostics, tail-conflict exploration and
recursive-ascent designs discussed here. Original copyright notices remain in
the vendored source; the complete license remains in
[LICENSE.txt](../third-party/Mouse-2.3/LICENSE.txt).

This review adds no Mouse implementation code, translated algorithms, grammar
fixtures or generated parsers to maintained code. If a later change copies or
adapts any of those, identify the exact upstream files in the changed file and
project NOTICE, retain applicable upstream notices, prominently mark modifications,
and distribute the Apache 2.0 license with that material. Preserve any upstream
NOTICE supplied with the reused distribution. Keep the scope of Apache-derived
material explicit alongside the project's existing Boost-licensed Pegged work;
the current NOTICE's blanket statement about new code must be qualified if such
material is added. Independently implemented ideas should still cite Mouse as
their design reference without claiming the whole project derives from Mouse.
