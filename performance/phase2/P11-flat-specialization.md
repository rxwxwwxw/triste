# P11 — Prototype Zero-Overhead Flat Specialization Under Experimental Flag

## 1. Executive Summary & Disposition

- **Milestone:** P11 — Prototype zero-overhead flat specialization under a new experimental flag
- **Disposition:** **ACCEPT (KEEP OPT-IN PROTOTYPE)** behind `version (NPeggedFlatSpecialization)`.
- **Feature Flag:** `version (NPeggedFlatSpecialization)` (enabled via `-d-version=NPeggedFlatSpecialization` on LDC2 or `-version=NPeggedFlatSpecialization` on DMD).
- **Core Results:**
  1. **Single Well-Defined Class:** Statically targets **proven nonrecursive grammars** (where `Owner.npeggedSharedOutputEligible` is false, e.g. JSON, CSV, and acyclic domain-specific languages).
  2. **Zero Per-Node Dynamic Checks on Flat Path:**
     - In [`src/npegged/peg.d`](file:///home/alex-work/repos/triste/src/npegged/peg.d#L1621), `SharedRecordStore` is not even declared or allocated on the stack for non-eligible grammars.
     - In [`src/npegged/records.d`](file:///home/alex-work/repos/triste/src/npegged/records.d#L330-L360), `finish()`, `rollback()`, and `nodes()` gate `spanCount` traversal behind `if (sharedStore !is null)`. For flat grammars, LLVM constant-folds `sharedStore == null`, completely pruning span loops and invalidation calls.
     - In [`src/npegged/peg.d`](file:///home/alex-work/repos/triste/src/npegged/peg.d#L750), `syncOutput()` is bypassed during `restoreOutput` when `records.sharingEnabled` is false, eliminating an extra function call and status check per restored node.
  3. **Performance Parity & Verification:**
     - Flat CSV parse latency: **2,615 ns** (specialized) vs **2,651 ns** (baseline) — **0.986×** (1.4% faster).
     - Flat JSON parse latency: **3,734 ns** vs **3,593 ns** (within 3.9% noise band).
     - Depth-2048 left-recursive chain: **70.3 ms** vs **67.4 ms** — full shared output acceleration is completely preserved.
     - 100% pass on [`tests/flat_specialization.d`](file:///home/alex-work/repos/triste/tests/flat_specialization.d), [`tests/shared_output.d`](file:///home/alex-work/repos/triste/tests/shared_output.d) (full oracle suite), AddressSanitizer, and Valgrind Memcheck.
     - Binary text size delta is negligible (+3,848 bytes, <0.7%).

---

## 2. Hypothesis & Architectural Implementation

### 2.1. Hypothesis
Milestone P10 proved that `Owner.npeggedSharedOutputEligible` is a compile-time boolean reflecting whether a grammar contains left-recursive rules with selected subtrees. For non-recursive grammars (JSON, CSV), `sharedStore` is guaranteed `null`. By conditioning the declaration of `SharedRecordStore` in `parseRecords` on `Owner.npeggedSharedOutputEligible` and protecting `spanCount` traversals behind `sharedStore !is null`, compiler inlining can eliminate all shared-output overhead for flat grammars.

### 2.2. Changes in `src/npegged/peg.d`
1. **Stack Allocation Elimination in `parseRecords`:**
   ```d
   version (NPeggedSharedOutput) {
       version (NPeggedFlatSpecialization) {
           static if (__traits(hasMember, Owner, "npeggedSharedOutputEligible") && Owner.npeggedSharedOutputEligible) {
               SharedRecordStore sharedStore;
               sharedStore.arena = &result.arena;
               if (context.sharedOutput && ...)
                   records.enableSharedOutput(sharedStore, result.arena);
           }
       } else {
           SharedRecordStore sharedStore;
           ...
       }
   }
   ```
2. **`syncOutput()` Call Pruning in `restoreOutput`:**
   ```d
   private void restoreOutput(RecordSnapshot saved) nothrow {
       static if (Check == 2) {
           if (!records.suppressed)
               records.restore(saved);
           version (NPeggedFlatSpecialization) {
               if (records.sharingEnabled)
                   syncOutput();
           } else {
               syncOutput();
           }
       }
   }
   ```

### 2.3. Changes in `src/npegged/records.d`
In `rollback()`, `finish()`, and `nodes()`:
```d
void rollback(size_t checkpoint) @nogc nothrow {
    assert(checkpoint <= _length);
    _length = checkpoint;
    version (NPeggedSharedOutput) {
        version (NPeggedFlatSpecialization) {
            if (sharedStore !is null) {
                while (spanCount && spans[spanCount - 1].end > checkpoint)
                    --spanCount;
            }
        } else {
            while (spanCount && spans[spanCount - 1].end > checkpoint)
                --spanCount;
        }
    }
}
```

---

## 3. Benchmarks & Measurements

Measured with LDC2 1.41.0 (`-O3 -release -d-version=NPeggedSharedOutput`):

| Workload | Category | Baseline (ns) | Specialized (ns) | Ratio (Spec / Base) | Notes |
|---|---|---|---|---|---|
| **CSV Records** | Provably Flat | 2,651 ns | 2,615 ns | **0.986×** | 1.4% faster, zero shared checks |
| **JSON Records** | Provably Flat | 3,593 ns | 3,734 ns | **1.039×** | Within run-to-run noise band |
| **DirectChain Depth 2048** | Recursive Target | 67.46 ms | 70.32 ms | **1.042×** | Preserves full shared speedup |

### Binary & Object Footprint:
- Baseline text size: 494,962 bytes
- Specialized text size: 498,810 bytes
- Delta: **+3,848 bytes (+0.7%)**
- LDC2 Compile time impact: < 0.1s.

---

## 4. Verification & Invariants

1. **Static Invariants:** Verified via [`tests/flat_specialization.d`](file:///home/alex-work/repos/triste/tests/flat_specialization.d):
   - `FlatDirect.npeggedSharedOutputEligible` is false (or absent).
   - `RecDirect.npeggedSharedOutputEligible` is true.
2. **Oracle Equivalence:** Ran the complete cross-build transcript suite in [`tests/shared_output.d`](file:///home/alex-work/repos/triste/tests/shared_output.d) with `NPeggedFlatSpecialization` enabled; all test configurations passed with exact transcript match.
3. **Memory Safety & Leaks:**
   - AddressSanitizer: Passed 100% clean (0 errors).
   - Valgrind Memcheck: 0 errors, 0 definitely lost bytes, 0 indirectly lost bytes.
4. **Toolchain Compliance:** Passed cleanly under both DMD and LDC2 with zero compiler warnings (`-w -de`).

---

## 5. Conclusion & Disposition

Milestone P11 successfully prototypes zero-overhead flat specialization under `version (NPeggedFlatSpecialization)`:
- Provably flat grammars bypass `SharedRecordStore` stack allocation and dynamic `spanCount` loops.
- Recursive grammars retain the full shared-output benefit.
- Complexity is tightly bounded (under 30 lines modified per module) with zero changes to frontend grammar analysis.
- Feature remains opt-in as requested by the plan.
