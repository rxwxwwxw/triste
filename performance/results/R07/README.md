# R07 — evaluate combination and stop criteria

## Synthesis of Lane R (Recursive Scaling)

Lane R investigated the two independent asymptotic mechanisms in NPegged left-recursion:
1. **Memo Invalidation (R01–R03):** R01 established that recognition work scales linearly
   without snapshot copying. R02 traced active seed dependencies. R03 prototyped narrower
   memo invalidation based on dependency sets. However, R03 resulted in severe 11–12×
   quadratic regressions on sibling rule visits across 448 test cases, violating the
   asymptotic stop rule. R03 was rejected and cleanly rolled back.
2. **Output Snapshots (R04–R06):** R04 proved that `CompactNode` snapshot copying was
   quadratic in recursive chains despite linear logical output. R05 and R06 developed
   an immutable fragment representation (`-version=NPeggedSharedOutput`) that cut 2,048-term
   copying by over 99% and achieved 0.388–0.436× timing ratios on deep recursion. However,
   it introduced 5–25% fixed overhead on standard flat grammars (JSON, CSV, PEG), precluding
   promotion to default.

## Combination Matrix & Decision

The planned 2×2 matrix:
- {reference invalidation, new invalidation} × {reference snapshots, new snapshots}

| Configuration | Invalidation | Snapshots | Status | Outcome / Decision |
|---|---|---|---|---|
| **Reference** | Baseline broad invalidation | Flat slice copying | **Default** | Default parser configuration |
| **R03 only** | Narrow dependency invalidation | Flat slice copying | **Rejected** | Rolled back due to 11–12× sibling regression |
| **R06 only** | Baseline broad invalidation | Shared fragment snapshots | **Experimental Opt-In** | Retained behind `-version=NPeggedSharedOutput` |
| **Combined** | Narrow dependency invalidation | Shared fragment snapshots | **Unmet / Rejected** | Blocked by R03 failure; cannot be promoted |

### Final Disposition

- **No default parser semantics or build flags are changed.**
- **R03 remains reverted.**
- **R06 remains available as an explicit compile-time opt-in** for applications parsing deep
  left-recursive grammars with full record capture.
- **Lane R is concluded.**
