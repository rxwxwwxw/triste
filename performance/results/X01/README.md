# X01 — Bounded Literal-Prefix Discrimination After FIRST-Byte Overlap

## 1. Overview & Semantic Contract

Milestone X01 implements bounded literal-prefix discrimination analysis in `npegged.analysis` and `npegged.grammar`.
When alternatives in an ordered PEG choice share overlapping FIRST byte sets, conventional predictive choice fails to dispatch directly.
X01 provides diagnostic inspection of ordered alternatives to determine whether bounded literal lookahead resolves the overlap, preserves ordered choice semantics, or detects unreachable/shadowed branches.

The analysis is strictly descriptive and follow-up UX to H01/H02: it does not alter default parser code emission or runtime semantics.

### 1.1. Discrimination Taxonomy (`DiscriminationKind`)

| Kind | Description | Example Fixture | Ordered Choice Implication |
|---|---|---|---|
| `disjointFirst` | FIRST byte sets are completely disjoint | `'a' / 'b'` | Direct single-byte predictive dispatch possible. |
| `disjointTails` | FIRST bytes overlap; common literal prefix followed by disjoint tail bytes | `'ab' / 'ac'` | Bounded lookahead of depth $k$ discriminates alternatives; neither shadows the other. |
| `shadowed` | Earlier alternative is an unguarded proper prefix of (or identical to) a later alternative | `'a' / 'ab'`, `'ab' / 'ab'` | The later alternative is unreachable for any input matching the prefix; flagged for grammar authors. |
| `guarded` | Earlier alternative has a literal prefix, but is constrained by EOF (`eoi`/`endOfInput`) or a lookahead predicate (`&`/`!`) | `'a' eoi / 'ab'`, `&'ax' 'a' / 'ab'`, `!'b' 'a' / 'ab'` | Backtracking after guard failure permits subsequent alternatives to match; later alternative is not shadowed. |
| `unbounded` | Overlap cannot be resolved by bounded literal prefix inspection (e.g. non-literal, recursive, or opaque rules) | `[a-z]+ / 'ab'` | Requires general backtrack or DFA scanner lowering. |

## 2. API & Struct Definitions

- **`DiscriminationKind` (enum):** `disjointFirst`, `disjointTails`, `shadowed`, `guarded`, `unbounded`.
- **`BranchDiscrimination` (struct):** Contains ordered indices `(firstIndex, secondIndex)` where $i < j$, `kind`, `commonPrefixLength`, `commonPrefix`, `discriminatingDepth`, and diagnostic `detail`.
- **`ChoiceDiscrimination` (struct):** Contains `expressionIndex`, `ruleName`, `hasOverlap`, and `BranchDiscrimination[] pairs`.
- **`PrefixDiscriminationResult` (struct):** High-level report with `status`, `diagnostic`, `grammarName`, `choices`, and formatted `report`.
- **`GrammarAnalysis.analyzePrefixDiscrimination(size_t exprIndex)` / `analyzeAllPrefixDiscriminations()`:** Core analysis queries in `npegged.analysis`.
- **`renderDiscrimination(...)`:** Deterministic serialization into human-readable text or valid JSON.
- **`prefixDiscriminationReport(...)`:** Frontend entry point in `npegged.grammar`.

## 3. Verification & Compliance Matrix

- **Fixtures Tested:**
  - `'ab' / 'ac'`: `disjointTails` at depth 2 (common prefix `"a"`).
  - `'a' / 'ab'`: `shadowed` (earlier alternative 0 is unguarded prefix of alternative 1).
  - `'a' eoi / 'ab'`: `guarded` by `eoi`.
  - `&'ax' 'a' / 'ab'`: `guarded` by positive lookahead.
  - `!'b' 'a' / 'ab'`: `guarded` by negative lookahead.
  - `'a' / 'b'`: `disjointFirst` (no overlap).
  - `'ab' / 'ac' / 'ad'`: Multi-branch pairwise `disjointTails`.
- **Automated Check Script:** `scripts/prefix-discrimination-check.sh` validates DMD and LDC2 compilation, execution under GC stress and memory limits, and verifies byte-for-byte identical output between DMD and LDC2.
- **Multi-Compiler & Sanitizer Results:**
  - DMD and LDC2 compile cleanly with zero warnings (`-w`).
  - AddressSanitizer (ASan) and LeakSanitizer (LSan): clean exit code 0.
  - Valgrind Memcheck: 0 errors from 0 contexts, 0 definitely lost, 0 indirectly lost bytes.
- **Coverage:**
  - Branch and line coverage across all executable `src/` modules strictly exceed 90%.
  - Zero Phobos imports verified via pre-commit and `validate.sh`.
