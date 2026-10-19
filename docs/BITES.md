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
