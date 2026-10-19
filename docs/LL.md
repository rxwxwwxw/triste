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

# Certified EBNF export (L2)

`ebnfExport(definition, format)` converts **only** rules whose closed region is `certifiedLL1`. Everything else gets its own
entry — `not-convertible` (`PEGOnly`, `CFGCandidateUnproven`, `boundedLookaheadCandidate`) or `unknown` — with the reasons from
L1 and no EBNF. Text form: `Rule ::= expr ;` plus `(* not converted: ... *)` comments; JSON form: per rule `ruleIndex`
(original rule id), `status`, `class`, `ebnf`, and `proof` (class and closed region).

Notation: `"text"` (escapes `\"`, `\\`, `\xNN`), `[\x61-\x7a]` byte classes, `eps`, `EOF` (end of input), `( a | b )`,
postfix `?` `*` `+`, rule names as nonterminals. Captures/wrappers do not change the language and are dropped.

Empirical evidence (`tests/ll_export.d`, 120 s alarm): an independent reader parses the exported text and matches it with real
CFG semantics (all alternatives, all lengths); on every string up to length 6-7 over small alphabets (254,308 strings, both
parser backends, five certified grammars) the exported CFG accepts exactly the inputs the PEG consumes completely. The same test
shows the trap `'a'* 'a' eoi`: its naive CFG reading accepts `aa`, the PEG rejects it, and the export refuses the rule.
Corpus agreement is additional evidence only; the certificate is the L1 proof contract.

# LL(1) backend (L3)

`ParserBackend.ll1` (opt-in; benchmark with `PARSER_BACKEND=ll1`) is `direct` plus FIRST-guarded loop exits in rules accepted by
the cheap positional LL(1) certifier. It replays the skipped body's work units and recorded failure exactly, so outputs, step
limits and failure positions equal the combinators (differential-tested). Measured gain over `direct`: none; see
`performance/milestones/L3-ll1/notes-l3.md`.
