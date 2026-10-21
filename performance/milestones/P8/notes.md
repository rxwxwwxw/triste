# P8 — Iterative lowering of directly left-recursive rules — COMPLETE for recognition (`accept`); `check` keeps seed growth

Recognized form (`Frontend.iterativeForm`, unit-tested): `E <- E S1 / .. / E Sk / B1 / .. / Bm` with every suffix alternative
before the base alternatives, each suffix consuming (some part of its rest is provably nonnullable), and no base alternative
leading back to `E` at its own position (direct or through `leftEdges`). Seed growth tries the suffix alternatives in order on the
current seed and stops when none succeeds or the candidate does not extend the seed; the base alternatives only run on the first
iteration (afterwards they reproduce the seed or something shorter). That is exactly `E <- (B1 / .. / Bm) (S1 / .. / Sk)*`. The
generator builds this body from the analysis graph, runs it through the usual token/DFA pipeline, and emits it as `_acursor_E`,
routed from `accept!` through the entry (`E` skips the memoized seed-growth rule when `State.acceptOnly` and no trace) and through
inline calls from other accept cursors (`acceptRules`). Combinators, `check`, the record modes and trace runs are unchanged.
Tree and record associativity were not attempted (they need the nested left-leaning shape of seed growth).

Contract change in `accept` (docs/ACCEPT.md): the loop form charges fewer work units, less depth and no memo than seed growth, so
where `check` finishes inside its limits `accept` returns the same verdict and status, and where `check` hits a limit `accept` may
still finish (never the reverse). `tests/differential.d` now asserts exactly that relation for every fixture, limit and
backend, plus equal trace sequences when tracing.

New family `LeftExpr` (nested_expr): left-recursive `Expr`/`Term` grammar, handwritten recursive-descent twin
(`benchmark/handwritten/leftexpr.d`), workloads Small/Empty/Trailing/Unbalanced/Flat (1.5 KB)/Deep (8 nested parentheses)/FlatInvalid
in validation and accept modes.

Measured (Apple M1, LDC 1.43, direct, 3 interleaved repetitions x 9 samples x 100 iterations, raw JSON here; before = same tree
without the lowering), ratio vs handwritten:
| workload | accept before | accept after | check before | check after |
|---|---|---|---|---|
| Small | 454 ns (16.4x) | 54 ns (1.96x) | 453 ns | 483 ns (+6.6%) |
| Flat | 26.2 us (10.3x) | 4.3 us (1.69x) | 25.6 us | 26.2 us (+2.2%) |
| Deep (8 levels) | 20.7 ms (223,000x) | 178 ns (1.92x) | 19.7 ms | 21.5 ms (+8.7%) |
| Unbalanced | 1,079 ns (39.8x) | 51 ns (1.89x) | 1,068 ns | 1,133 ns (+6.1%) |
| Trailing / Empty / FlatInvalid | 16x / 8.8x / 10.1x | 1.93x / 1.77x / 1.71x | | |
The check column is unchanged code on the same hot path; its +2..+9% is the extra `acceptOnly` test at the lowered rules' entry
plus layout noise (disclosed, not guarded). Pre-existing finding recorded here: memoized left recursion is catastrophic for
nested parentheses (`check` of 16 nesting levels exhausts the default depth limit; 8 levels take 20 ms against 90 ns handwritten),
because every seed growth invalidates dependent memo entries; this is the P7 (memoization) territory, not changed.

Tests: unit tests for `iterativeForm` (accepted, suffix-after-base, several suffixes, indirect, nullable suffix) and for the
generated source (`_acursor_Expr` present only for the lowered shapes); the A4 differential with the relaxed accept relation;
scripts/build.sh and the fixture checks (eligibility golden hashes refreshed: 4 generated sources changed) on LDC. DMD, sanitizers,
Valgrind and coverage tooling: not run on this host.
