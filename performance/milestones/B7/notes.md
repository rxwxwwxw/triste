# B7: regular SUCC precision study

Opt-in (`BitesAnalysis.regularSucc`, `prefixDiscriminationReport(..., regularSucc=true)`, `bitesReport(..., regularSucc=true)`).
Extension: SUCC of a sequence through zero-width steps (intersection) and fixed-length exact steps (`InputLanguage.fixedThen`),
SUCC(!e) = Σ* \ MAYSUCC(e) with MAYSUCC an upper approximation; budget overflow still maps SUCC -> ∅, MAYSUCC -> Σ*.
Soundness: exhaustive sampling over {a,b,c,1} up to length 4 against the reference matcher (SUCC ⊆ success, MAYSUCC ⊇ success,
NULL and BITES upper bounds) plus keyword/guard fixtures in `bites.d`.

Study: 105 real grammar definitions extracted from examples/, benchmark/ and tests/ (`regular-succ-study.csv`, driver `study.d`),
LDC -O2, one pass each mode:

| | plain | regular |
|---|---|---|
| choice pairs analysed | 25520 | 25520 |
| pairs proven BITES-disjoint | 14482 | 14484 (+2, both in markdown) |
| pairs `unknown` | 1076 | 1076 |
| FIRST conflicts improved by BITES | 340 | 342 |
| total analysis time (105 grammars, includes parsing) | 4.03 s | 6.47 s (+60%) |

Decision: the gain (2 of 25520 pairs, 0.008%) does not justify +60% analysis time, so the narrower original stays the default and
the extension remains an opt-in study flag. It does resolve guard patterns of the form `!('a' 'b') 'a' / 'ab'`
(`tests/prefix_discrimination.d`). Not studied: determinization blow-ups beyond the 512-state budget (none triggered on this corpus).
