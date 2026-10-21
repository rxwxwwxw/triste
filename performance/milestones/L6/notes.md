# L6 — LR runtime backend — CLOSED NO-GO (table recognizer built as the first sub-milestone)

Split as the roadmap requires: (a) tables + recognizer, (b) scanner, (c) stack/value construction, (d) hybrid call bridge. Only (a)
was built (`lrAccepts` over `buildLr` tables; verified against the PEG parsers by `tests/lr_check.d`, see L5) because its
measurement decides whether the rest is worth doing.

Measurement (`lrbench.d.txt`, Apple M1, LDC 1.43 -O3, 2,401-byte expression `n+n*(n+n*n)*n...`, 34 LR(1) states, per parse):
| engine | time |
|---|---|
| LR(1) table recognizer (flat arrays, fixed stack, byte-class map; the best form of the idea) | 67.3-67.6 us |
| `accept!` on the direct backend (`Expr <- Term ('+' Term)*`, ...) | 5.70-5.79 us |
| handwritten recursive descent (same language) | 5.42-5.46 us |
The table machine is 11.8x slower than the direct PEG code and 12.4x slower than the handwritten parser, which the direct
backend already matches within 1.05x. The CFG reading of `*`/`?` adds helper-nonterminal reductions (an LL-style `Star -> X Star | _`
chain per repetition) that the loop forms do not pay; LR would need left-recursive loop forms and an optimized shift/reduce
fusion to compete, which is a research project of its own with no workload where the direct backend is behind.

Disposition: (b)-(d) not built. L5's conflict analysis and the tested tables remain as the experimental, report-only artifacts.
