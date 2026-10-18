# Phase 1 Performance Ledger & Gate Reconciliation

This document freezes the final results, status classifications, and source hashes of Phase 1
milestones (**F01–F05**, **R01–R07**, **H01–H08**) and reconciles the performance acceptance gate
failures between baseline F01 and the post-H07 state.

---

## 1. Phase 1 Milestones Ledger

| Milestone | Category | Status | Commit / Revision | Source Report | Key Finding / Decision |
|---|---|---|---|---|---|
| **F01** | Foundation | **Diagnostic** | `ce113d9` | [F01-baseline.json](file:///home/alex-work/repos/triste/performance/results/F01-baseline.json) | 380/387 checks passed; established initial baseline with 7 ratio failures. |
| **F02** | Foundation | **Diagnostic** | `39906d3` | [F02.md](file:///home/alex-work/repos/triste/performance/tasks/F02.md) | Built differential oracle checking status, end, failEnd, ParseTree, and memory. |
| **F03** | Foundation | **Diagnostic** | `42a26c6` | [F03/README.md](file:///home/alex-work/repos/triste/performance/results/F03/README.md) | Scaling matrices (16–1024 terms); collected timing, requested bytes, and arena footprint. |
| **F04** | Foundation | **Diagnostic** | `b1c8a71` | [F04/README.md](file:///home/alex-work/repos/triste/performance/results/F04/README.md) | Proved left-recursion bottleneck is output-dominated (node copying), not invalidation-dominated. |
| **F05** | Foundation | **Diagnostic** | see git log | [F05/README.md](file:///home/alex-work/repos/triste/performance/results/F05/README.md) | Diagnosed 4 tiny non-recursive PEG gate failures; flagged empty `Sp` candidate for H05. |
| **R01** | Scaling | **Diagnostic** | `658fb66` | [R01/README.md](file:///home/alex-work/repos/triste/performance/results/R01/README.md) | Proved recognition scaling is linear through 8,192 terms when record copying is excluded. |
| **R02** | Scaling | **Diagnostic** | `09834c0` | [R02/README.md](file:///home/alex-work/repos/triste/performance/results/R02/README.md) | Diagnostic trace mapped active seed dependencies; proved transitive dependencies required. |
| **R03** | Scaling | **Rejected** | see git log | [R03/README.md](file:///home/alex-work/repos/triste/performance/results/R03/README.md) | Narrow invalidation caused 11–12× quadratic regressions on sibling rule visits; reverted. |
| **R04** | Scaling | **Diagnostic** | `29e6791` | [R04/README.md](file:///home/alex-work/repos/triste/performance/results/R04/README.md) | Measured record copying; proved snapshot copies are quadratic despite linear output. |
| **R05** | Scaling | **Diagnostic / Isolated API** | `e29d83d` | [R05/README.md](file:///home/alex-work/repos/triste/performance/results/R05/README.md) | Prototyped immutable fragment snapshots; froze 65 KB vs 67 MB flat at depth 2048. |
| **R06** | Scaling | **Opt-In** | `8bb643f` | [R06/README.md](file:///home/alex-work/repos/triste/performance/results/R06/README.md) | Cut 2048-term time to 0.388–0.436×; kept behind `-version=NPeggedSharedOutput` due to flat overhead. |
| **R07** | Scaling | **Concluded under Stop Rule** | `4726c4e` | [R07/README.md](file:///home/alex-work/repos/triste/performance/results/R07/README.md) | Combination unviable due to R03 rejection; R06 remains explicit opt-in only. |
| **H01** | Hot Path | **Diagnostic** | `ac5f3cc` | [H01/README.md](file:///home/alex-work/repos/triste/performance/results/H01/README.md) | Added `eligibilityReport` diagnostic API explaining direct/memoization decisions. |
| **H02** | Hot Path | **Diagnostic** | `4a8e12b` | [H02/README.md](file:///home/alex-work/repos/triste/performance/results/H02/README.md) | Made analysis compute rule-local `known` and `actionful` facts, decoupling pure rules in reports. |
| **H03** | Hot Path | **Opt-In** | `4f0f987` | [H03/README.md](file:///home/alex-work/repos/triste/performance/results/H03/README.md) | Pure islands fast path (`-version=NPeggedPureIslands`); 0.0024–0.0028× on 128-word check. |
| **H04** | Hot Path | **Rejected** | `72a6dfd` | [H04/README.md](file:///home/alex-work/repos/triste/performance/results/H04/README.md) | Guarded local memo bypass caused ~2× scaling regressions on guarded-off controls; reverted. |
| **H05** | Hot Path | **Abandoned (Optimal)** | `e613f9e` | [H05/README.md](file:///home/alex-work/repos/triste/performance/results/H05/README.md) | Empty `Sp` inspection showed LLVM/LDC already batches 6 work units with FIRST masks. |
| **H06** | Hot Path | **Diagnostic** | `86ffd7e` | [H06/README.md](file:///home/alex-work/repos/triste/performance/results/H06/README.md) | Scanner diagnostics (`version(NPeggedScannerMetrics)`); revealed 2,220 of 2,224 replays were failed scans. |
| **H07** | Hot Path | **Promoted** | `05a567f` | [H07/README.md](file:///home/alex-work/repos/triste/performance/results/H07/README.md) | Extended failed-scan shortcut to `Check == 2 && !HasInnerRecords`. Eliminated 99.8% of replays. |
| **H08** | Hot Path | **Concluded (Optimal)** | `4726c4e` | [H08/README.md](file:///home/alex-work/repos/triste/performance/results/H08/README.md) | Verified LDC2/LLVM `-O3` already optimizes direct lowered expressions into register-allocated loops. |

---

## 2. Reconciliation of Performance Gate Failures (F01 vs. H07)

### Gate Threshold Rule
The acceptance gate rule is **per-run and strictly non-amortized**: every single case in **every individual run** must achieve a ratio $\le 5.0\times$ against the handwritten baseline. An aggregate mean $\le 5.0\times$ does not pass if an individual run exceeds the threshold.

### Baseline F01 Failures Reconciliation
In baseline F01 (`F01-baseline.json`, revision `bb6f136`), 380 of 387 checks passed. Exactly **7 checks failed** across 3 runs, all confined to 4 small non-recursive validation cases in `handwritten-workloads`:

| Case Name | Run | Output Mode | F01 Baseline Ratio | Post-H07 Ratio | Post-H07 Status | Delta Ratio |
|---|---|---|---:|---:|---|---:|
| `PEGGrammar.Permissive` | 1 | validation | **5.754×** | **4.805×** | **PASS** | 0.851× (-14.9%) |
| `PEGGrammar.Deep` | 1 | validation | **5.391×** | **3.173×** | **PASS** | 0.866× (-13.4%) |
| `PEGGrammar.Permissive` | 2 | validation | **5.175×** | **4.778×** | **PASS** | 1.061× (+6.1%) |
| `PEGGrammar.Truncated` | 2 | validation | **5.229×** | **4.325×** | **PASS** | 0.995× (-0.5%) |
| `PEGGrammar.Deep` | 2 | validation | **5.324×** | **4.421×** | **PASS** | 0.872× (-12.8%) |
| `PEGGrammar.Trailing` | 3 | validation | **5.146×** | **4.389×** | **PASS** | 0.846× (-15.4%) |
| `PEGGrammar.Deep` | 3 | validation | **5.420×** | **4.608×** | **PASS** | 0.863× (-13.7%) |

### Post-H07 Gate State
In the current post-H07 gate report (`performance/phase2/gate-h07.json`, revision `4726c4e`):
* **Total Paired Checks:** **513 / 513 checks executed** (171 checks per run across validation, spans, and tree modes × 3 runs).
* **Failing Gates Count:** **0 failures**.
* **Gate Verdict:** **PASS (100% of checks $\le 5.0\times$)**.
* **Machine-readable datasets:**
  - Full report: [gate-h07.json](file:///home/alex-work/repos/triste/performance/phase2/gate-h07.json)
  - Side-by-side reconciliation: [gate-reconciliation.json](file:///home/alex-work/repos/triste/performance/phase2/gate-reconciliation.json), [gate-reconciliation.csv](file:///home/alex-work/repos/triste/performance/phase2/gate-reconciliation.csv)
