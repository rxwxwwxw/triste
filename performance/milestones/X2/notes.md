# X2 — Lexer/parser fusion: (a) satisfied by existing analyses, (b)/(c) CLOSED NO-GO

(a) Token-boundary facts are already certified by the B-series BITES/MAYSUCC analyses (used by C2 and by P3/L4 dispatch) and by the L1/L5
classifiers; O4(a) counted the regular regions that a fused recognizer would target: 260 regions in 105 grammars, 119 composed ones
(`performance/milestones/O4/corpus-study.csv`). No new certifier was written.
(b)/(c) A generated fused recognizer and records support were not built: Q3 shows the remaining gap is not token scanning, and the cost
of O4's tagged-DFA research is not supported by a measured ceiling. Reopen if a ceiling experiment on CSV-style records shows >=3%.
