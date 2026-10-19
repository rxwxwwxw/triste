# S1: register-resident step accounting in generated cursors (direct backend)

New baseline on the `direct` backend (`performance/baselines/20261019T224838Z-*`, PARSER_BACKEND=direct): 78/171 within 1.5x,
p90 2.50, geomean 1.47. Earlier baselines (A1..P2) used the default combinators backend and are not comparable.

Finding (throwaway experiments, not committed): on `direct`, replacing `State.tick()` with `return true` took Arithmetic.Flat from
12.1 us to 5.8 us (-52%); removing failure recording changed nothing. Step accounting dominated because `s.steps`/`s.status`
live in memory behind a `ref State` and every node ticks.

Change (`src/npegged/grammar.d`): every generated `_cursor_*` function holds `steps`, the step limit and a `live` flag in locals
(`_steps`, `_limit`, `_live`, nested inlined `_tick()`), which `State.tick`'s exact transitions operate on. They are synchronized
(`s.steps = _steps` before, reload of steps and status after) around every call that can tick or change status — rule calls,
scanner/combinator calls — and written back before the function returns. The empty-match guard uses the locals too.
Work-unit counts, resource-limit status and failure positions are unchanged.

Exactness evidence: `tests/differential.d` compares combinators with `direct` and `ll1` on all fixtures over a dense step-limit sweep
(every limit 0..79) plus depth and output limits; also run with `-d-version=NPeggedPureIslands`; the full LDC suite also passes with
PureIslands/Metrics/First2 enabled. DMD is not runnable on this host.

Result (S1 vs the direct baseline, 3x7 samples, 171 workloads, LDC):
- within 1.5x: 78 -> 96 (45.6% -> 56.1%); p50 1.55 -> 1.37; p90 2.50 -> 2.04; p95 2.79 -> 2.21; geomean 1.47 -> 1.32;
  worst 3.44 -> 2.72 (Numbers.ScientificEmpty/validation).
- 69 workloads >5% faster (Arithmetic -43..-56%), median change -1.5%.
- Regressions >5% (10, all PEGGrammar; reproduced by an A/B of the two builds): Trailing/spans +12%, Empty/spans +11%, Truncated/spans +9%,
  LongLiteral/spans +9%, LongTruncated +8%, others 6.5-8%. Five of them are workloads where NPegged is ~5x faster than the handwritten
  parser (ratio 0.21), the rest are 40-175 ns inputs (+4 ns). The tiny-input cost matches the closure/frame setup of the nested `_tick`.
  Not hidden by the mean; accepted because every one stays under the handwritten gate except already-slow tiny cases.

Alternative tried (S1b, `performance/milestones/S1b`): counters in a plain `StepCounter` struct instead of a nested function. It removes the PEG
regressions (6 remain, <= 8.7%) but is slower overall: 93/171 within 1.5x, p90 2.23, geomean 1.38. S1 kept for the better headline.
`pragma(LDC_never_inline)` on cursors did not help the PEG cases.

Next candidates on direct: fuse adjacent ticks, remove the per-node `live` initialisation, reduce rule-call synchronization (the likely
remaining PEGGrammar cost).
