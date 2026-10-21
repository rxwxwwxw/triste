# C2 / C3 / C4 — accept-clone dispatch, Proposition 6 cuts, predicate elimination — CLOSED NO-GO (no targets, zero ceiling)

All three rewrite only the accept clone, so each needs sites in the benchmark grammars where it would act. Measured with the
existing report APIs on the five benchmark grammars (`build` tools; counts below):

| grammar | choices | FIRST/FIRST conflicts | BITES improves FIRST (C2 target) | BITES proven-disjoint pairs | Prop. 6/11/13 candidate sites (C3) |
|---|---|---|---|---|---|
| Arithmetic | 4 | 0 | 0 | 9/9 | 7 |
| CSV | 3 | 0 | 0 | 5/5 | 6 |
| Numbers | 0 | 0 | 0 | - | 1 |
| PEGGrammar | 19 | 7 | 0 | 25/32 | 36 |
| JSON | 6 | 0 | 0 | 37/37 | 7 |

- **C2** (dispatch for FIRST-overlapping but BITES-disjoint alternatives): `bitesImprovesFirst` is 0 in every grammar. The 7 PEGGrammar
  FIRST/FIRST conflicts are not resolved by BITES, so there is nothing to dispatch; every FIRST-disjoint choice already compiles to
  `predictiveChoice`. Ceiling: 0 choices x 0 workloads.
- **C3** (cut after a bitten failing alternative): the candidate sites are choices that are already FIRST-disjoint (dispatched by
  one table lookup, never retried) and star loops. A cut can only save work when a *retry* would otherwise happen, i.e. in
  choices that are not dispatched; Proposition 6 requires BITES-disjointness, which the 7 undispatched PEGGrammar conflicts do
  not have. No retry is saved on any benchmark workload.
- **C4** (`!X Y -> Y` when FIRST(X) misses nonnullable Y, EOF handled by `eofOnly`): the only provable site in PEGGrammar is
  `!SequenceBoundary Prefix`; `TopBoundary` starts with a letter lookahead that overlaps `Prefix`, so its guard is necessary
  (the task's own `!'"' .` example). The provable site is already a single FIRST-mask test (`predictiveNot` fast path), so
  elimination saves one compare per element (< 1%), and it would make `accept` charge fewer units than `check`, weakening the
  `accept` == `check` contract for no measurable gain.

Disposition: not implemented; nothing in `src/` changed. New workloads with FIRST-overlapping keyword/identifier choices would be
needed first to justify any of the three.
