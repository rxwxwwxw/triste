# L5 — LR(1) conflict analysis on the certified CFG subset — COMPLETE (report-only)

`src/npegged/lr.d`: `lrGrammarOf` (CFG reading of a `certifiedLL1` region over a byte-class partition), `buildLr` (canonical LR(1)
item sets, ACTION/GOTO, conflicts, state budget), `renderLr` (text/JSON), exposed as `lrReport` / `lrBuild` in `grammar.d`. Nothing
generated changes. Behavior, tests and the evidence run are described in `docs/LL.md`.

Tests (LDC): colocated unit tests in `lr.d` (conflict-free grammars, shift/reduce, reduce/reduce, nullable productions, the
precedence expression grammar, the LR(1)-not-LALR(1) grammar, a budget-exceeded run that must not look like a proof, an
independent recursive-descent reference over all strings up to length 7 over `n+*()`, report rendering) and in `grammar.d`
(`lrReport` over certified and uncertified rules, `lrBuild` errors); integration `tests/lr_check.d` (`scripts/lr-check.sh`, 120 s
alarm). Sanitizers/Valgrind/coverage tooling/DMD: not run on this host.
Limits: no LALR(1) compression (not needed at these sizes), no precedence declarations, terminals are byte classes only.
