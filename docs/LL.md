# PEG -> LL/CFG conversion contract (L1, report-only)

`conversionReport(definition, format)` (`src/npegged/ll.d`) classifies each rule's **closed region** (the rule plus every rule it
can reach). It generates nothing; it states what is *proven*.

| class | meaning |
|---|---|
| `certifiedLL1` | pairwise FIRST-disjoint alternatives; a nullable alternative is the last one and no alternative of it hides what follows (NEXTBITES); non-nullable repetitions/options whose BITES miss what follows; no predicates, actions, recursion hazards, or undescribable terminals |
| `boundedLookaheadCandidate` | FIRST overlaps but BITES proves the alternatives disjoint (needs k>1 or regular lookahead) |
| `CFGCandidateUnproven` | a CFG reading exists, but ordered choice or greedy repetition may hide language; no proof |
| `PEGOnly` | lookahead predicates, left recursion, definite ordered-choice shadowing, nullable repetition bodies |
| `unknown` | actions/effects, unknown or unresolved nodes, parameters, terminals not describable by bytes |

The worst finding anywhere in the closed region decides the class; `local` is the rule's own body. Every finding carries its
reason and graph node, so blockers and witnesses are explicit.

## Assumptions behind `certifiedLL1`
- Contract: the language of whole inputs (callers add `eoi`); byte-oriented terminals; no actions or side effects.
- Sufficient condition from Mascarenhas, Medeiros, Ierusalimschy (2014) for LL(1) grammars, strengthened for repetition and
  nullable alternatives by this repository's BITES/NEXTBITES premises (`docs/BITES.md`).
- No unaccounted lookahead behavior: every predicate forces `PEGOnly` (a future milestone may eliminate provably redundant ones).

## CFG -> PEG results do not give PEG -> CFG
Published results show that certain CFGs (LL(1) and related classes) have equivalent PEG readings, i.e. a *CFG-to-PEG*
direction. They do not make an arbitrary PEG equal to its naive CFG reading (`('a' / 'ab') 'c'`, `'a'* 'a' eoi` differ). Hence
the contract certifies a PEG region only through the sufficient conditions above, and empirical corpus agreement (L2) is extra
evidence, never proof.

## Limitation found while implementing
F3's `firstFollowConflict` uses rule-level FOLLOW, which misses the continuation after a *nested* choice (for example
`('a' / 'c'?) 'a'`). L1 therefore uses positional NEXTBITES for nullable alternatives; treat the F3 flag as advisory.
