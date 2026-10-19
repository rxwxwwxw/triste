# BITES analysis (report-only)

Reference: Redziejowski, "BITES Instead of FIRST for Parsing Expression Grammar", Fundamenta Informaticae 109(3), 2011.
Nothing here changes generated code; FIRST machinery is untouched.

## B1: input languages (`src/npegged/language.d`)

`InputLanguage` = set of whole input strings (EOF included), stored as a complete byte DFA. Union and intersection are exact
product constructions, complement flips acceptance, emptiness is decided by reachability (with a shortest witness).
Constructors: `empty`, `universal`, `endOfInput` (only ""), `prefix("abc")` (= L Σ*), `bytePrefix(class)`.

Proof contract: `provenEmpty`/`provenNonempty` are exact; `unknown` appears only after a budget (`Budget.maxStates`, default 512
product states) is exceeded and is never read as empty. Over-approximations (BITES, NULL) map `unknown` to `universal`;
under-approximations (SUCC) map it to `empty`. Zero-width terminals (`eps`, `eoi`) never become `prefix(...)`.
Trusted facts: byte-oriented terminals, pure (action-free) expressions. Excluded: actions, left recursion, parameters/dynamic
nodes — treated as unknown.

## B2: SUCC and NULL (`src/npegged/bites.d`, `BitesAnalysis.succ` / `.nul`)

SUCC is a *lower* approximation, NULL an *upper* one, both as `InputLanguage`s per expression index.

| node | SUCC | NULL |
|---|---|---|
| literal "t" (escape-free) | t Σ* | ∅ |
| single-byte class | class Σ* | ∅ |
| other proven-consuming terminal | ∅ | ∅ |
| `eps` / empty literal | Σ* | Σ* |
| `eoi` | {""} | {""} |
| `fail` | ∅ | ∅ |
| choice | ∪ SUCC | ∪ NULL |
| sequence | Σ* if empty, child if single, else ∅ (B7 refines) | ∩ NULL (∅ if facts prove nonnullable) |
| `e?`, `e*` | Σ* | Σ* |
| `&e` | SUCC(e) | Σ* |
| `!e` | ∅ | Σ* \ SUCC(e) |
| wrappers, `e+` | child | child |
| unknown, action, unresolved/parameter | ∅ | Σ* |
| recursive back edge | ∅ | Σ* |

Budget overflow: SUCC -> ∅, NULL -> Σ*. Rules whose bodies contain actions or unknown nodes are `unknown` nodes in the graph.
Tests: per-node cases, recursion/budget degradation, and an exhaustive sampling check (all strings over {a,b,c}, length ≤ 4)
against a reference PEG matcher: SUCC never contains a failing input, NULL never misses an empty success. Sampling is
supplementary; soundness rests on the table above.

## B3: BITES (`BitesAnalysis.bites`, `renderBites`, `bitesReport(definition)`)

`BITES(e)` is an upper approximation of the inputs on which `e` may consume input outside a predicate:

- consuming terminal (literal, single-byte class): L(t) Σ*; other known consuming terminal: FIRST-byte class Σ*;
  zero-width (`eps`, `eoi`, empty literal): ∅. Unknown: Σ*.
- sequence: BITES(e1) ∪ ⋃ (NULL(e1..e(i-1)) ∩ BITES(ei)); evaluation stops once the prefix NULL is provably empty.
- choice: union. `e?`, `e*`, `e+` and transparent wrappers: BITES(e). Predicates: ∅ (their effect is the NULL restriction).
- reference: the rule's BITES; a recursive back edge degrades to Σ* (and the rule is reported `exact:false`).

Examples (tests): BITES("abc" [a-z]*) = "abc" Σ*; BITES((!"abc") [a-z]*) = (Σ* \ "abc" Σ*) ∩ [a-z] Σ* — FIRST overlaps but the
two BITES are provably disjoint. `eoi [a-z]` can never bite (NULL(eoi) = {""}).

`renderBites` / `bitesReport` serialize SUCC, NULL and BITES per rule (`status` empty|restricted|universal, state count, shortest
`witness`, and `exact`, false when a budget or recursion forced a conservative answer). No FIRST sets or generated code change.
Tests include an exhaustive sampling check (strings over {a,b,c} up to length 4) that BITES contains every input on which a
reference matcher consumed input outside a predicate.

## B4: disjointness and hiding diagnostics (report-only)

`prefixDiscriminationReport` pairs gain `bites` (`proven-disjoint` | `possible-overlap` | `unknown`), `bitesWitness`,
`bitesImprovesFirst` and `noHidingProven`; choices gain `bitesAllDisjoint` and `noHidingProven` (JSON keys appended, older
keys unchanged; text lines gain a `{bites: ...}` note). The older FIRST-based `kind`, `firstFirstConflict` and `definite`
fields are preserved.

- `proven-disjoint`: BITES(ei) ∩ BITES(ej) is provably empty (a proof even when unknown nodes enlarged the sets).
- `possible-overlap`: the upper approximations intersect and both alternatives were analysed exactly. This is **not** proof of
  hiding; `bitesWitness` is a shortest input inside the intersection of the approximations.
- `unknown`: the intersection is nonempty (or too large) and an alternative needed a budget cut, a recursive back edge, or an
  unknown/unresolved node.
- `noHidingProven` (Proposition 5): only for proven-disjoint pairs whose alternatives are both provably nonnullable per F1 facts.
  Nullable alternatives are out of scope here (Propositions 10-13 need NEXTBITES, B5). It is a lint result, never permission to
  reorder alternatives or cut.
- `bitesImprovesFirst`: a FIRST/FIRST conflict that BITES proves disjoint, e.g. `!'abc' [a-z]+ / 'abc' [a-z]*`.

## B5: NEXTBITES and Propositions 10-13 premises (`NextBites`, `checkPremises`, `nextBitesReport`)

Source read directly from the paper (Definition 5, Propositions 7-13, Appendix A.5-A.6).
`NEXTBITES(e, r) = ⋃ BITES(e')` over `NEXT = Last* × Next`, for `r ∈ {succ, fail}`, as a language seen from the position where `e`
terminated. Implemented over the expression graph by monotone fixed point from ∅, with the paper's Last/Next conditions
evaluated on the "may" properties nullable (F1), may-advance (`!neverAdvances`) and may-fail (`!neverFails`). Since every
condition is monotone in those properties, over-approximating them only adds pairs: results are supersets.

Differences from the paper, all conservative: a later element that can advance is reached through elements that may be empty
(intersecting their NULL languages), and for ordered choice the continuation after `ei` failed includes every later alternative
reachable through alternatives that may fail. Rule bodies return to every call site; the start rule is followed by nothing.
`&e` is handled as `!!e`; `e+` as `e e*`.

Fallbacks: a conservative graph (unknown nodes, unresolved references, actions/parameters = hidden call sites), a fixed point
that does not converge in 32 rounds, or a budget overflow all produce universal results and no proven premise.

`checkPremises` evaluates, per choice and star expression, the premises of the propositions (true = proven under the
approximations; false = not proven):

| flag | premises |
|---|---|
| `prop10` (no hiding, nullable choice) | disjoint BITES; (4) ei non-nullable for i<n; (5) if en may be nullable, BITES(ei) ∩ NEXTBITES(E,succ)=∅ |
| `prop11` (cut safety after a bite) | disjoint BITES; (6) if E may be nullable, BITES(ei) ∩ NEXTBITES(E,succ)=∅ (i<n); (7) if E may fail, BITES(ei) ∩ NEXTBITES(E,fail)=∅ |
| `prop12`/`prop13` (star) | e non-nullable and BITES(e) ∩ NEXTBITES(E,succ)=∅ |

All require `wellFormed` (trusted graph, converged, no left recursion). They are lint results and cut *candidates*, not
transformations (B6). Validation: paper examples `('a'/'c'?)'a'` (unsafe), `...'b'` (safe), `(!'a' .)*'a'` (safe),
`'a'*('ab'/'c')` (hidden), `'a'*('b'/'c')` (safe), nested calls, failure continuation, left recursion, unknown nodes
(`tests/next_bites.d`, unit tests in `bites.d`).

## B6: candidate commit sites (report-only; `commitSiteReport`, `renderCommitSites`)

For every choice and star expression the report names the theorem that would justify stopping retries, the proven premises,
and — when no theorem applies — the blockers. **No cut is emitted and no generated code or runtime changes** (`emitted:false`).

| theorem | applies to | premises |
|---|---|---|
| Proposition 6 | choice | well-formed, action-free owning rule, every alternative provably nonnullable, BITES pairwise disjoint |
| Proposition 11 | choice with nullable alternatives | well-formed, action-free, disjoint, conditions (6) and (7) |
| Proposition 13 | `e*` | well-formed, action-free, e nonnullable, condition (8) |

Premise names, blockers and examples: `C1 'ab' / 'ac'` (Prop. 6), `C2 ('a' / 'c'?) 'b'` (Prop. 11), `C3 ('a' / 'c'?) 'a'` (blocked by (6)),
`C4 'a'* ('b' / 'c')` (Prop. 13), `C5 'a'* ('ab' / 'c')` (blocked by (8)), `C6 'a' / 'ab'` (not disjoint), actions and left
recursion (not well-formed / not action-free).

Before any guarded optimization may use a site it must additionally prove, and test with the differential gate (A4), that
stopping retries preserves: `failEnd` and failure diagnostics (alternatives not tried would have recorded failures), compact
record/tree rollback behavior, step counts and the depth/memory limits. None of this is checked by the report. Note the theorems
speak about the paper's PEG semantics; NPegged additions (memoized left recursion, trace/actions, parameters, resource
limits) are handled by treating them as non-well-formed or unknown, never as proven.

## B7: regular SUCC (opt-in study)

See `performance/milestones/B7/notes.md`. `BitesAnalysis(graph, budget, regularSucc=true)` adds fixed-length and zero-width
sequence steps and `SUCC(!e) = Σ* \ MAYSUCC(e)`; measured gain on 105 real grammars was +2 certified pairs of 25520 for +60%
analysis time, so it stays off by default.

## B8: unified diagnostics (`diagnosticReport(definition, format)`)

One entry per choice and star expression combining F3 (FIRST, FIRST/FOLLOW), B4 (BITES), B5/B6 (NEXTBITES premises, theorem):

- `first`: `disjoint` | `overlap` (choice); `firstFollowConflict` with `followKnown`.
- `bites`: `proven-disjoint` | `possible-overlap` | `unknown`; `theorem`: governing proposition or "".
- `lint.hiding`: `definite` (proven unguarded literal-prefix shadowing) | `none-proven` (Proposition 5, 10 or 12, named in `reason`)
  | `possible` | `unknown` (not well-formed, unknown nodes, effects). Lint says nothing about whether a transformation is safe.
- `optimization`: `backend` recommendation (`predictiveChoice (emitted today)`, `cut candidate after first bite (not emitted)`,
  `literalChoice2 (opt-in NPeggedFirst2)`, `ordered choice`, `repetition loop`), `cutCandidate`, `cutEmitted` (always false) and
  `blockers`, which always include why no cut exists ("cuts are never emitted by the generator").

Source location is the owning rule, the expression's source text and graph index (the graph has no byte offsets).
The report is analysis-only and independent of the parser backend and memoization policy, unlike `eligibilityReport`.
It is a separate API rather than extra `eligibilityReport` fields so existing consumers are untouched.
Tests: `tests/diagnostics.d` (JSON stability, text form, lookahead, nullable, star, unknown, effects, left recursion).
