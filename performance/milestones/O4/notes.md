# O4 — Tagged-DFA lowering of record-emitting regular regions — (a) COMPLETE (report-only count)

`tagRegionReport(definition)` (`src/npegged/grammar.d`, unit-tested) re-runs the generator's region finder on every rule and counts the
regular (scanner-eligible) regions and, among them, the composed ones: regions that call rules, which a record selector turns into
`dfaToken(..., HasInnerRecords=true)` regions that the scanner cannot take in records mode (they fall back to the cursor path).
`performance/scripts/o4_study.d` + `corpus-study.csv` apply it to the 105-grammar corpus (examples/, benchmark/, tests/):

| corpus | grammars | rules | scanner regions | composed regions | rules with a composed region | grammars with one |
|---|---|---|---|---|---|---|
| 105 grammars | 105 | 1,688 | 260 | 119 (46%) | 89 | 25 (24%) |
The largest: xml2 (50 composed regions in 54), markdown (21), csv (8 of 8), oberon2 (6), pascal (5). So the situation is not rare, and
CSV (the benchmark with the largest records-mode gap) is entirely composed.

(b) and (c) are recorded in `notes-b.md` of this directory when attempted; the roadmap requires them to be separate, tested steps.
