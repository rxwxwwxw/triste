# A2 per-rule metrics

Build with `-version=NPeggedRuleMetrics` (separate instrumented build; absent otherwise, so timed builds are unchanged).
Attach a `RuleReport` (borrowed `RuleStats[]` rows) to `ParseContext.ruleReport`; `report.json()` emits per-rule
calls/successes/failures/memoHits. Test: `tests/rule_metrics.d`. Sample: `rule-metrics-arithmetic.json`
(direct backend, one 26-byte input; counts only rules reached through the `rule`/`recognizeRule` boundary).

Not collected yet: bytes examined, backtracks/rollbacks, output materializations, per-rule time. Memo-hit attribution is wired
in `rule()` but no fixture in this milestone observed a hit; aggregate hit counts remain in `NPeggedMetrics`.
