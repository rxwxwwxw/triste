# W2 / W3 — Limit-free clones, depth checks at cycle heads — CLOSED NO-GO

W2 premise: a W1 bound lets an entry select a clone without tick checks. Findings:
1. Applicability. The bound exists only for rules the positional certifier accepts. On the benchmark grammars that is the leaf
   rules (Number, Identifier, Numbers.*, JSON Number/True/False/Null); the roots of Arithmetic, CSV, PEGGrammar and JSON are not
   certified (`performance/milestones/W1/benchmark-grammars-bounds.txt`), so no workload entry would take the clone.
2. Ceiling. Replacing the remaining rule/repetition ticks by liveness tests (unsound, `build` experiment on the S5 tree)
   gives validation -10..-15% on Arithmetic and PEGGrammar (ManyRules -10.8%, Flat -14.5%) and CSV spans -5..-8%, but removing
   the register counters also changes inlining; a partial experiment that kept ticks but dropped the `s.steps` syncs around
   cursor calls and one that restructured `_tick()` into a hot/cold split both measured 0% on Arithmetic validation, so the
   gain is not the tick instructions themselves.
3. Soundness cost. A wrong bound would silently disable resource limits for that entry; the evidence for the scanner overscan
   assumption would need a per-table DFA analysis in generated code plus a third cursor family (+code size, +compile time on
   a toolchain whose 200-rule stress case already exhausts 16 GiB).
Disposition: not built. The measured wins came from D2 (coarser units, -10..-14%), S5 (register depth, up to -22%) and C1
(failure-free accept clone, median -7%).

W3 (depth checks only at recursive-cycle heads): superseded by S5. The depth comparison is now one register compare against a
hoisted limit and the `++depth/--depth` stores are gone; the depth ceiling experiment (-4..-10% before S5) is what S5
recovered (PEGGrammar validation -8..-22%).
