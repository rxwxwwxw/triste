# P2: direct lowering of plain-literal roots

Shape chosen: rules whose root is a nonempty `literal!("...")` (JSON `True`/`False`/`Null`; chosen from the A3 report,
where `root-combinator` fallbacks were scanners/literals/charClass roots). `emitDirect` already lowered literals, so only the
`useDirect` gate changed (`grammar.d`). JSON grammar: `root-combinator` fallbacks 9 -> 6 (the rest are DFA scanners).
Parity: full LDC suite, differential gate (combinators vs direct), eligibility integration test all pass; tests that pinned the
old fallback (`Leaf <- 'a'`, A3 strategy fixture) were updated.
Measured vs P6d (3x7 samples, 171 workloads): no workload moved by more than 5% in either direction; geomean 1.62 -> 1.62.
Cost/gain: no measurable gain; kept because it is behavior-identical and reduces fallbacks. Next candidates in the same list:
`charClass` / `Spacing`-style `discard(zeroOrMore(charClass))` roots, but those are already DFA scanners.
