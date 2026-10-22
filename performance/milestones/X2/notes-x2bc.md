# X2(b)/(c) — maximal-munch literal choices in compiled DFA regions (reopened by the maintainer, 2026-10-22)

**Scope.** An ordered choice of literals that is prefix-closed (every proper prefix of an alternative is itself an alternative) and
lists each literal before its proper prefixes is maximal munch. `GrammarAnalysis.maximalMunch` certifies it (`analysis.d`); the
region lowering (`grammar.d`) turns it into a trie whose stop points are `RegularKind.guard` nodes: a token may stop only if the
next byte is not one of its extensions (the end of input passes).

- **(b) Recognizer.** `compileDFA` routes expressions containing guards to `compileGuardedDFA`: each NFA thread carries the bytes it
  may not consume next, merged by intersection. Without the certificate the old path is unchanged (choice stays walked).
- **(c) Records.** `compileTaggedDFA` accepts guards (per-thread forbidden mask, first path wins) and still declines unless its
  transitions and accepting states equal the plain automaton's byte for byte, so a disagreement degrades to the walked cursor.

**Evidence (LDC, this host).**
- Unit tests: 26 modules pass (`-unittest`), including `maximalMunch` accept/reject cases, guarded DFA scans and a tagged guard table.
- `tests/maximal_munch.d` via `scripts/maximal-munch-check.sh`: 827,970 strings; `check`/`accept` of the compiled grammars equal the
  walked ones on `end`, `failEnd`, verdict, in both backends; span and tree records (`parseRecords`) equal the walked records, with a
  static assert that the tagged table is valid. Includes the `abz` trap where greedy munch must not accept what ordered choice rejects.
- `tests/tagged_regions.d` (O4) still agrees on 977,413 strings; `scripts/differential.sh` exit 0.

**Not run / limits.** DMD segfaults compiling the library on this host (known), so DMD is *not run*. Coverage, ASan/LSan, Valgrind and
the `performance/` timing runs were not run for this change: no speedup is claimed. Guards and the Ops family benefit is unmeasured;
the walked trie from L4 remains the runtime path for grammars the certificate rejects.
