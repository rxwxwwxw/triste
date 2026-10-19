# L3: selectable LL(1) backend (`ParserBackend.ll1`, `PARSER_BACKEND=ll1` for the benchmark)

`ll1` = the `direct` backend plus one transformation inside rules accepted by `firstCertifiedRules` (src/npegged/ll.d, classic
positional FIRST/FOLLOW LL(1) test, a subset of the L1 `certifiedLL1` class): an `e?`/`e*`/`e+` whose body is a sequence
starting with a literal, byte class or predictive choice tests the next byte against FIRST(body) before running the body. A
miss replays exactly what the body would have done on that byte — the same number of work units (`tick`s, so step limits
behave identically) and one recorded failure at the cursor — without running it. Uncertified rules, other body shapes, actions,
predicates and left recursion use the plain `direct` code (the fallback).
The full L1 classification (language algebra) took ~8 minutes under CTFE for the benchmark grammars, so generation uses the
cheap certifier (compile 52 s, same as the other backends).

Parity: `tests/differential.d` compares combinators with `ll1` on 7 grammars (certified, uncertified, mixed, predicates) over
every word up to length 4 and step limits 0..39, depth limits and output limits: all equal. Unit tests check where guards appear.

Measured (LDC, 3x7 samples, 171 workloads; `milestones/L3-direct` vs `L3-ll1`): median change +0.1%; no workload faster than
5%; six tiny `spans` workloads 5.6-6.5% slower (inputs of tens of ns, within noise). Within 1.5x: direct 79 (as measured here,
see L3-direct) vs ll1 79. Verdict: exact, but no measurable gain; stays opt-in and is not recommended.

Finding: the earlier baselines (A1..P2) used the default *combinators* backend. The `direct` backend is much better: within 1.5x
79/171 (46%) vs 60/171 (35%) and geomean 1.48 vs 1.62 (`milestones/L3-direct` vs `P2`). The performance work should be measured
and, if suitable, defaulted on `direct`.
