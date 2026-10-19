# P12 — Audit Fragment Lifetime, Parent Rebasing, Rollback, and Resource Limits

## 1. Executive Summary & Disposition

- **Milestone:** P12 — Audit fragment lifetime, parent rebasing, rollback, and resource limits
- **Disposition:** **ACCEPT (ALL 10 INVARIANTS AUDITED AND VERIFIED CLEAN)**.
- **Audit Target:** Persistent fragment lifetime, parent rebasing in trees, span rollback, arena boundary isolation, sticky resource limits, and error invariants across `SharedRecordStore` and `RecordBuffer` under `version (NPeggedSharedOutput)`.
- **Test Suite:** [`tests/fragment_audit.d`](file:///home/alex-work/repos/triste/tests/fragment_audit.d)
- **Validation Results:**
  1. **Repeated Frozen Seed:** 50 consecutive generations of snapshot -> replay -> seed growth -> re-snapshot -> replay verified identical against flat reference trees.
  2. **Nested Left Recursion:** Multi-tier left recursion (`Expr <- Expr '+' Term`, `Term <- Term '*' Factor`) verified on deep input expressions (40+ terms) with 100% semantic and record match vs flat parser.
  3. **Many Siblings:** 2,000 siblings attached to a single root node verified under shared fragment composition; all 2,000 child parent pointers correctly rebased to index 0.
  4. **Record Suppression:** `&` and `!` lookahead probes inside left-recursive rules verified to suppress and restore records cleanly without corrupting replay spans.
  5. **Resource Limits & Sticky Failures:** Memory exhaustion at all phases (`freeze`, `join`, `restoreUsing` frame stack, `put`) tested; verified deterministic rollback to checkpoint and sticky error propagation (`Status.resourceLimit`).
  6. **Failed Restores & Corruption Defense:** Forward parent references, out-of-bounds destination parents, and arithmetic overflow lengths safely rejected with `Status.invalidInput` or `Status.resourceLimit` and full rollback.
  7. **Alternating Selected/Nonselected Nodes:** Grammars alternating between selected and suppressed rule projections verified identical to flat parser.
  8. **Late Failure:** 50-step recursive matching followed by an unexpected syntax error verified to unwind cleanly without memory leaks or state corruption.
  9. **Cross-Parse Owner Destruction:** Successive parser results destroyed and verified; requested vs retained bytes tracked, proving zero dangling pointers or escaped fragments.
  10. **Oversized Offsets / Parent Indices:** Boundary parent indices (`size_t.max - 1`, illegal join attachments) verified safe against integer wrapping.
  11. **Sanitizer & Toolchain Verification:** Clean passes under DMD, LDC2 `-O3`, AddressSanitizer (ASan), and Valgrind Memcheck with 0 errors and 0 leaks (`definitely lost: 0`, `indirectly lost: 0`).

---

## 2. Invariants Audited & Verified

### 2.1. Seed Replay & Multi-Generation Fragment Composition
- **Mechanism:** In `records.d`, when a seed exceeds 128 nodes, `sharedSnapshot` captures the existing replay span without flattening. As the seed grows across subsequent iterations, newly appended nodes form small leaf fragments that are incrementally joined to the prior snapshot tree.
- **Audit Finding:** The fragment tree height scales logarithmically or linearly with generations, and `restoreUsing` rebalances frames via an explicit arena-allocated stack. All node fields (`kind`, `begin`, `end`, `parent`) remain bit-identical to the flat copying baseline across 50 generations.

### 2.2. Parent Index Rebasing
- **Mechanism:** When fragments are frozen, parent indices relative to the fragment base are normalized. External roots (`parent < base`) are marked `size_t.max`. During `restoreUsing`, nodes with `parent == size_t.max` rebase to the destination's enclosing `parent`, while internal nodes rebase by `frame.base + node.parent`.
- **Audit Finding:** Multi-sibling topologies (up to 2,000 children) and nested left-recursive rule hierarchies maintain exact parent-child edges. No parent pointer wraps or points to an out-of-order sibling.

### 2.3. Rollback & Span Invalidation
- **Mechanism:** `rollback(checkpoint)` decrements `spanCount` for any replay span with `spans[i].end > checkpoint`. If `nodes` is accessed mutably or `finish` touches an interior node of a span, `invalidateShared` marks that span unshared so it is re-frozen on subsequent snapshots.
- **Audit Finding:** Truncated replays correctly discard partial spans, forcing fallback to clean leaf re-freezing. Failed restores roll back `_length` to the checkpoint before returning false.

### 2.4. Resource Limits & Memory Isolation
- **Mechanism:** Allocations in `SharedRecordStore` and `RecordBuffer` draw from the result's arena.
- **Audit Finding:** When arena capacity is capped (`limit` reached), all operations fail deterministically:
  - `freeze` returns empty snapshot with `store.status = Status.resourceLimit`.
  - `join` returns empty snapshot with `store.status = Status.resourceLimit`.
  - `restore` aborts, rolls back the buffer, and sets `output.status = Status.resourceLimit`.
  - Fragments never escape their owning `CompactResult`; destruction of `CompactResult` frees all allocated blocks without residual leaks.

---

## 3. Toolchain & Sanitizer Matrix

| Environment | Flags | Test Suite | Result |
|---|---|---|---|
| **DMD** | `-unittest -w -nothrow -version=NPeggedSharedOutput` | [`tests/fragment_audit.d`](file:///home/alex-work/repos/triste/tests/fragment_audit.d) | **PASS** (10/10 tests) |
| **LDC2** | `-O3 -release -d-version=NPeggedSharedOutput` | [`tests/fragment_audit.d`](file:///home/alex-work/repos/triste/tests/fragment_audit.d) | **PASS** (10/10 tests) |
| **LDC2 ASan** | `-fsanitize=address -g -d-version=NPeggedSharedOutput` | [`tests/fragment_audit.d`](file:///home/alex-work/repos/triste/tests/fragment_audit.d) | **PASS** (0 errors, 0 leaks) |
| **Valgrind** | `--tool=memcheck --leak-check=full --errors-for-leak-kinds=definite,indirect` | [`tests/fragment_audit.d`](file:///home/alex-work/repos/triste/tests/fragment_audit.d) | **PASS** (0 errors, 0 lost) |

---

## 4. Conclusion & Disposition

Milestone P12 is **accepted**. The shared-output subsystem upholds all memory safety, parent rebasing, rollback, and resource-limit invariants without defects. No code repairs were required.
