# D1 — data set for the maintainer: `direct` versus `combinators` as the `grammar!` default

Status: the maintainer decided on 2026-10-20 to keep `combinators`. This is the refreshed evidence on the final tree (commit `3435a052d`),
so the decision can be revisited with current numbers. The default has NOT been flipped.

Same gate for both backends (`--q2`, validation/spans/tree/accept, 500 iterations x 7 samples x 3 runs, LDC 1.43, Apple M1; commit `3435a052d`):

| backend | run | within 1.5x | p50 | p90 | geomean | worst |
|---|---|---|---|---|---|---|
| direct | `milestones/PhaseExit3` | 261/346 (75.4%) | 1.26 | 1.87 | 1.21 | 6.4x (LeftExpr check) |
| combinators | `milestones/D1-combinators-final` | 150/346 (43.4%) | 1.64 | 2.83 | 1.64 | 12.8x |

Per workload, `combinators / direct` time has geomean **1.35**. `combinators` is faster by more than 3% on **15 of 346** workloads: LeftExpr.Deep/validation
(0.62: nested parentheses go through the generic wrapper on `direct`), LeftExpr.Empty (0.88), JSON small-invalid corpus and FirstByte failure (0.91-0.93),
CSV.MultilineQuoted/SingleLine/EmptyQuoted spans (0.92-0.96), PEGGrammar.LongLiteral/LongTruncated (0.94-0.96), JSON WhitespaceThenError/tree (0.95),
LeftExpr.Trailing (0.95); apart from LeftExpr.Deep they are tiny inputs or failure cases within 9%. `performance/scripts/autotune.py direct=... combinators=...`
chooses `direct` for both families (`X3/profile-backend.json`).

Other items the roadmap asks for:
* L3 and S2b numbers: `milestones/L3-direct`, `milestones/S2b`.
* A4 parity over all fixtures and G6 seeds: `tests/differential.d` passes on LDC for both backends at the current commit (`scripts/differential.sh`).
* A5 generated-size and compile-time deltas: `performance/size/` (P6's state-code scanner did not increase compile time or object size).
* DMD: `dmd` segfaults (exit 139) when compiling the whole tree on this host, so it is "not run"; per-file `dmd -c -o-` of `dfa.d` succeeds.
* Caveats of switching: grammars with actions or runtime-selector records keep the walked forms; failure `end` in records mode differs for tagged regions (see O4).
