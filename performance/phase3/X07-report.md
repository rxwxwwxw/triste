# X07 — Exact recursive-ascent contract audit

Disposition: **NO PROMOTION — SPECIALIZED/MANUAL ONLY.** The prototype is not exactly equivalent to generated left recursion for the tested full-tree contract. No parser source or lowering policy changed. This conditional branch is closed; no automatic general left-recursion transformation is introduced.

## Gate applicability

The arithmetic gate's mode named `tree` is implemented in `benchmark/workload_output.d` by selected `CompactNode` concrete-rule intervals: Root/Term/Factor/Primary/Number/Identifier and their exact parent indices. `benchmark/workload_grammars.d` uses iterative Term/Factor operator loops. A Term span contains Factor siblings; it is not a nested left-associative Expr `ParseTree` with per-prefix matches and diagnostic children.

The manual `directAscent` prototype produces the latter representation. It is not a drop-in replacement for the maintained gate's precedence grammar, output hierarchy or budget policy. A04's Arithmetic deficit does not establish coverage for this particular manual full-tree algorithm. B04's zero-left-recursion finding is consistent with this, but the output-obligation mismatch is the more specific reason not to transfer synthetic ascent ratios to the gate.

The existing X03 test was nevertheless part of normal validation and contained misleading checks. X07 repairs that test/reporting path rather than leaving an incomplete comparator and an invalid performance gate in CI.

## Comparator and ownership repairs

`tests/test_recursive_ascent.d` now uses the same `parse` API for both comparators. Both own the input and result arenas; resource limits are identical. The generated LeftChain Expr is the baseline. The manual candidate has the matching outer `defined` boundary, avoiding an accidental wrapper-shape mismatch. Nested cases use a BranchChain Atom with parenthesized reference expressions, so the manual transformation applies only at the outer chain, not recursively throughout the grammar.

Complete comparison includes:

- Parse-result status and success, consumed end and failEnd.
- Every tree's name, input, successful flag, begin/end/failEnd and matches.
- Recursive child and failed-child sequences.

An adjacent `@nogc nothrow` unit test specifically verifies detection of the formerly omitted input, failEnd and failed-child differences. The integration helpers and main are also `@nogc nothrow`.

The previous comparator omitted input, failEnd and failedChild. Its depth assertion was `!successful || shallowCtx.depthLimit <= 16` after assigning depthLimit=16; the second operand made it tautological. Its scaling section used five iterations, copied input only for the reference API, and asserted a speed threshold despite incomplete output parity. Those are not valid equal-output performance evidence.

## Concrete failure of full equivalence

For unlimited input `1+1`, both APIs return status=ok, end=3 and top-level failEnd=3, but the first inner expression's failEnd is **0 in the reference and 1 in the manual candidate**. The old comparator accepted that pair because it did not inspect this field. Empty and failed-suffix inputs also expose complete diagnostic-tree differences. These are not timing noise.

For `1+2+3` with memory limits 4095, 4096 or 4097 bytes, the generated reference reports **resourceLimit** while the manual candidate reports **ok**. Both can report end=5 and failEnd=5, so those offsets or an intermediate node's successful flag cannot substitute for parse-result status. The repaired checker asserts that every printed result's success flag agrees with status==ok, including quota failures.

A 64-term chain under depthLimit=16 succeeds in both implementations. The repaired test asserts those actual statuses instead of assuming term count equals call depth. It also tests depth zero and other shallow limits. Left-recursive seed growth is iterative; output-tree depth and parser-call quota are different quantities.

## Seven-repeat correctness matrix

DMD and LDC produce byte-identical transcripts. Each executes seven repetitions covering singleton/multi-term flat chains, mixed digit lengths, prefix/truncated suffixes, empty/nonmatching input, parentheses, nested/sibling expression shapes, and step/depth/memory limits.

| Family | Comparisons per compiler | Complete-tree parity failures | Parse-status differences |
|---|---:|---:|---:|
| Flat chains / prefix failures | 63 | 49 | 0 |
| Branch/nested shapes | 42 | 28 | 0 |
| Step limits | 56 | 56 | 0 |
| Depth limits | 56 | 56 | 0 |
| Memory limits | 49 | 28 | 21 |
| 64 terms at depth 16 | 7 | 7 | 0 |
| Total | 273 | 224 | 21 |

Expr is a prefix-parsing entry without eoi: e.g. `1+` may return a successful `1` prefix with a farther diagnostic frontier. These cases are not silently relabeled as whole-input acceptance. A few singleton/base cases match completely, but the matrix proves no useful multi-term full-tree class interchangeable with the generated parser.

The JSON explicitly states `generalEquivalent=false` and `SPECIALIZED_MANUAL_ONLY`. A successful oracle-run marker means that the limitation/counterexample assertions passed, not that the prototype is generally equivalent. The CI wrapper now says “limitation audit passed; general equivalence rejected.”

## Performance disposition

**No new latency experiment was run after the exact oracle failed.** Seven repetitions here are semantic repetitions, not seven timing trials. The universal correctness-first stop rule rules out reporting an optimization win for unequal full outputs. X07's performance/promotion criteria are not met, so the plan's alternative disposition—retain a specialized/manual prototype—applies.

The old `>=1.5` packrat/ascent speedup assertion was removed from this correctness wrapper. It was not the official ≤1.5× handwritten gate, and relied on five-iteration timings with unmatched ownership and incomplete field comparison. The official gate and its target are unchanged.

The initial legacy LDC smoke passed under that weak checker. Its source/checker snapshots and smoke log are retained in `X07/original-*`. The legacy scaling output used a fixed build path that later correctness runs overwrote; no scaling values from that smoke are retained or used in this decision. The new 273-case transcripts are preserved unmodified. This report makes no native speed, memory-complexity or full-gate improvement claim.

## Memory and compiler verification

The corrected oracle passed DMD and optimized LDC with warnings/deprecations treated as errors, module unit tests enabled and existing EligibilityGCStress configuration. Source, compiler versions, exact compiler commands, binary/transcript hashes and family summaries are in `X07-decision.json`.

Targeted ASan/LSan and Valgrind runs produce the same 273-case transcript. Valgrind reports zero errors and zero definitely, indirectly or possibly lost bytes; 120 bytes remain reachable in druntime. These are memory-safety passes for the experiment, not semantic-equivalence passes. ASan uses a physical 4 GiB user systemd scope with swap disabled; other children use the 4 GiB address-space limit. The integration main has a 45-second alarm and runners a 60-second execution timeout.

## Reproduction and next step

```sh
python3 scripts/x07_audit.py
bash scripts/x07_memory.sh
```

The first command runs the repaired checker on both compilers and records the exact outputs under `performance/phase3/X07/`. `scripts/recursive-ascent-check.sh` is still the normal validation entrypoint. Performance is deliberately separate from correctness; there are no speed assertions in this oracle. All touched D is formatted, no Phobos import or manual resource cleanup was added, and no `src/` change occurred. No whole-repository coverage or staged-hook pass is claimed for this test-only milestone.

The manual helper remains available for callers choosing its explicit construction semantics, not as an equivalent replacement for arbitrary PEG rules. Any future general lowering proposal must first repair and pass the complete-field and finite-resource counterexamples, establish a useful exact grammar/output class and obtain more than five independent native timing repetitions plus matched controls. E01 is the remaining integrated audit; the global ≤1.5× target remains unproven and unmet on the saved baseline.
