# W1 — Static work bounds — COMPLETE (report-only)

`src/npegged/work.d` computes, for every rule whose closed region the positional LL(1) certifier accepts
(`firstCertifiedRules`: no predicates/actions/left recursion/unknown nodes, FIRST-disjoint choices, loops that miss their
continuation), a bound `units <= perPosition*(n+1)` for the work-unit model of `docs/WORK_UNITS.md`. Derivation (in the
module header): the parse never re-reads input, so units are charged by rule-call and repetition-attempt nodes starting at
a position; evaluations starting at one position form chains through the same-position graph; a node is evaluated at most
`paths(e) = 1 + sum(paths(preds))` times per position; `perPosition = 1 + sum(cost(e)*paths(e))` over the closed region.
A cycle in the same-position graph (left recursion, also through nullable prefixes) or any missing premise gives
`unknown: <blocker>`; unknown is never read as a bound. Exposed as `workBound` in every `eligibilityReport` rule row
(text and JSON). Generated code does not change.

Tests: colocated (grammar.d: hand-derived bounds 2/9/15*(n+1) for Num/Expr/Root, and left recursion, predicates, FIRST
conflicts, nullable loop bodies and a rule that calls an uncertified rule all unknown); `tests/work_bounds.d` +
`scripts/work-bounds-check.sh` enumerate every input up to length 7 over small alphabets for three certified grammars
and assert that the units actually charged (smallest step limit that does not run out) never exceed the bound, on the
combinator and the direct backend (worst measured/bound: 0.145 arithmetic, 0.200 expression, 0.333 item loop).
Enumeration is extra evidence, the derivation is the proof. LDC only (DMD segfaults on this host).

Benchmark grammars (`benchmark-grammars-bounds.txt`, `performance/scripts/work_bounds_report.d`): the cheap certifier accepts
only leaf rules: Number 5, Identifier 2, Numbers.Scientific 10 / Hexa 3 / Binary 2, JSON True/False/Null 1, JSON Number 9,
PEG guards 3-5 (all `*(n+1)`). The roots of Arithmetic, CSV, PEGGrammar and JSON are `not-certified-ll1` (nullable `Space`
loops and lookahead predicates). Measured units for reference: Arithmetic Flat 5,645 for n=1025, Deep 589 for n=129.

Scanner caveat (documented in the module): a scanner charges `examined - pos + 1`, which exceeds the per-attempt units of
the loops it replaces by its overscan; the bound assumes at most one byte per token. Not enforced by W1; this is one reason
W2 is not built on it.
