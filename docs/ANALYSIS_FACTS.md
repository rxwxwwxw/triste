# Grammar facts (F1)

Per-expression facts in `FirstFacts` (`src/npegged/analysis.d`). Byte-oriented; actions and resource limits are ignored.

| Fact | `yes`/`true` means | Otherwise |
|---|---|---|
| `first` | superset of bytes that can start a consuming success | — |
| `nullable` | `no`: provably cannot succeed empty; `yes`: can succeed empty; `unknown` | never read `unknown` as `no` |
| `known` | `first`/`nullable` are complete (no unknown node, unresolved reference, or unknown prefix) | facts are partial, do not optimize |
| `eofOnly` | every empty success needs end of input | |
| `neverFails` | **proven** the expression succeeds on every input | `false` = possibly fails |
| `neverAdvances` | **proven** every success consumes nothing | `false` = possibly advances |

`neverFails`/`neverAdvances` are one-sided proofs computed as least fixed points from `false`, so recursion
(including left recursion) and unknown nodes only lose precision. Examples: `'a'*`, `'a'?` never fail; `eoi` and
predicates never advance; `!e`/`&e` are not claimed to never fail; an empty choice never advances and always fails.

Validation matrix: `analysis.d` unit tests cover eps/eoi, literal, left recursion, star/optional of unknown,
choice rescued by eps arm, predicate, empty sequence/choice. Unsupported: Unicode code-point terminals and
parameterized/dynamic rules are `known=false` upstream and receive no proofs.
