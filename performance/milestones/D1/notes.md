# D1 — data set for the maintainer: `direct` versus `combinators` as the `grammar!` default

Status: the maintainer decided on 2026-10-20 to keep `combinators`. This is the refreshed evidence on the final tree (commit `1ce38a6c6`),
so the decision can be revisited with current numbers. The default has NOT been flipped.

Same gate for both backends (`--q2`, validation/spans/tree/accept, 500 iterations x 7 samples x 3 runs, LDC 1.43, Apple M1):

| backend | run | within 1.5x | p50 | p90 | geomean | worst |
|---|---|---|---|---|---|---|
| direct | `milestones/PhaseExit2` | 264/346 (76.3%) | 1.25 | 1.88 | 1.26 | 24.5x (LeftExpr check) |
| combinators | `milestones/D1-combinators` | 147/346 (42.5%) | 1.64 | 3.09 | 1.74 | 27.4x |

Per workload, `combinators / direct` time has geomean **1.38** (1.37 handwritten-workloads, 1.40 json-ambiguity). `combinators` is faster by more than
3% on **31 of 346** workloads, never by more than 12% (largest: LeftExpr.FlatInvalid/validation 0.885, JSON small-invalid corpus spans 0.885,
CSV.MultilineQuoted/spans 0.904); they are tiny inputs or failure cases. `scripts` listing: `performance/scripts/autotune.py direct=... combinators=...`
chooses `direct` for both families (`X3/profile-backend.json`).

Other items the roadmap asks for:
* L3 and S2b numbers: `milestones/L3-direct`, `milestones/S2b`.
* A4 parity over all fixtures and G6 seeds: `tests/differential.d` passes on LDC for both backends at the current commit (`scripts/differential.sh`).
* A5 generated-size and compile-time deltas: `performance/size/` (P6's state-code scanner did not increase compile time or object size).
* DMD: `dmd` segfaults (exit 139) when compiling the whole tree on this host, so it is "not run"; per-file `dmd -c -o-` of `dfa.d` succeeds.
* Caveats of switching: grammars with actions or runtime-selector records keep the walked forms; failure `end` in records mode differs for tagged regions (see O4).
