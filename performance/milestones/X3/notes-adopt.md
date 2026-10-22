# X3 — profile adoption (2026-10-22)

`autotune.py direct=PhaseExit3 combinators=D1-combinators-final` (same gate, same host, commit 3435a052d) chooses `direct` for both
families (`profile-backend.json`; direct 261/346 within 1.5x vs 150/346, `combinators/direct` geomean 1.35). The maintainer approved
adopting it, which is a reversal of D1 (2026-10-20): the default `ParserBackend` of `grammar!`, `generate`, `eligibilityReport`,
`asModule` and `grammar(ParseTree)` is now `direct`.

Known cost (D1 notes): `combinators` is faster by >3% on 15/346 workloads (LeftExpr.Deep/validation 0.62; the rest tiny/failure within 9%).
Grammars with actions or runtime selectors keep the walked forms. Callers needing the old output pass `ParserBackend.combinators`;
`scripts/generate_parser.d` does, so `src/npegged/parser.d` is unchanged (`scripts/examples.sh` with `DC=ldc2` passes).

Verified (LDC): 26 modules pass `-unittest`; differential, maximal-munch, tagged-regions, left-recursion, hotpaths, examples exit 0.
Tests that meant "combinators" now say so explicitly. Not run: DMD (segfaults on this host), scripts needing bash>=4 `mapfile`
(eligibility, entry, prefix-discrimination, pure-islands, lr), coverage, sanitizers, Valgrind, new timing runs.
