# P7 — Explain/select memoization — COMPLETE (report only; no default changes)

`performance/scripts/memo_report.d` (build with `-d-version=NPeggedRuleMetrics`, see the file header) runs a grammar on a
representative input under `Memoization.yes` with the A2 per-rule counters and prints, per rule: calls, memo hits (repeated
`(rule, position)` evaluations), hit rate, whether the rule is left-recursive, whether `selective` memoizes it, and a
recommendation; then compares the three policies (`no`, `selective`, `yes`) on verdict, arena bytes and work units (the smallest
step limit that does not run out). Output for Arithmetic, LeftExpr, CSV and JSON: `memo-report.md`.

Findings (each is a measured row, not a prediction):
- Arithmetic: no rule ever repeats a `(rule, position)` call (0 hits in 3,800 calls); `selective` memoizes nothing and charges the
  same 5,901 units as `no`, while `yes` allocates 262 KB of memo for no gain -> keep `selective` (the default policy).
- LeftExpr: `Expr` and `Term` hit their memo 78% / 68% of the time and `no` cannot parse the input at all (verdict 0): left recursion
  requires memoization, which `selective` provides (234 units, 4 KB).
- CSV: single DFA rule, nothing to memoize.
- JSON: only `Spacing` repeats (11% hits on this input); `selective` leaves it unmemoized; the memo would save a handful of
  scanner calls at the price of a hash lookup per call.
The settings for trials are the existing `Memoization` values (`no`, `selective`, `yes`) of `grammar!`; the explain tool never
changes behavior. Rules needed for correctness (left-recursive) are never recommended for removal.

Tests: the tool is a diagnostic program (not part of the CI binaries); the underlying counters are covered by
`tests/rule_metrics.d`. LDC only.
