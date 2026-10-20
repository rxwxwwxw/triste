# S5 — Depth as a cursor parameter — COMPLETE (exact; direct backend)

Change: direct cursors take `const size_t _depth` (their own frame depth, after the increment) and call each other inline with
the limit check in registers: `if (_depth >= _depthLimit) { status = resourceLimit } else _cursor_Y(s, ..., _depth + 1)`.
`s.depth` is synchronized (`s.depth = _depth`) only where a cursor leaves register code (State rule/record templates,
generic combinator fallbacks, scanner replay; `dfaToken.cursor` takes `depth`). Because cursors may leave `s.depth` stale,
every boundary that increments it now restores a saved value instead of decrementing (`ruleBody`, `recognizeRule`,
`recognizeRuleTicked`, `memoizedRule`, `directLeftAscent`). Direct cursors only run when `trace` is null at entry, so the inline
call skips the dead trace hook. Work units, failure results and statuses are unchanged (the same tick and the same check).

Tests: peg.d (`recognizeRule`/`recognizeRuleTicked` restore a stale depth), dfa.d (cursor sweep now also over depth 0..4 with a
stale shared depth), grammar.d (generated cursors carry `_depth`), A4 differential (depth limits swept on both backends,
all memo policies), 24-module unit tests, scripts/build.sh and the ten fixture checks on LDC. DMD, sanitizers, Valgrind,
coverage tooling: not run on this host.

Benchmarks (Apple M1, LDC 1.43, direct, validation/spans/tree for CSV, PEGGrammar, Arithmetic, Numbers; 3 interleaved
repetitions x 9 samples x 20000; baseline = D2 runner): PEGGrammar validation Deep -21.8%, Truncated -17.5%, Small -14.0%,
Medium -13.4%, ManyRules -8.2%; PEGGrammar spans -10..-14%; median over 132 workload/mode pairs -0.5%.
Reproducible regressions (4 alternating reruns, disclosed): PEGGrammar.Medium/tree +5.6% (2200 -> 2325 ns),
PEGGrammar.Small/tree +4.0%, Arithmetic.Flat/spans +3.3%, other tree/spans cases within +-3%.
