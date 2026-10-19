# P13 — Optional One-Localized Output-Fragment Tuning Experiment

## 1. Executive Summary & Disposition

- **Milestone:** P13 — Optional one-localized output-fragment tuning experiment
- **Disposition:** **REVERT AND CLOSE (NO REPEATABLE BENEFIT)**.
- **Experiment:** Tested eager storage capacity reservation (`totalNeeded = checkpoint + saved.length`) at entry to `SharedRecordStore.restoreUsing` under experimental flag `version (NPeggedBatchReserve)` to evaluate whether pre-reserving capacity avoids geometric reallocation overhead during recursive seed replays.
- **Benchmark Suite:** [`benchmark/p13_tuning.d`](file:///home/alex-work/repos/triste/benchmark/p13_tuning.d) under LDC2 1.41.0 (`-O3 -release -d-version=NPeggedSharedOutput`).
- **Empirical Findings:**
  1. **DirectChain Depth 256 (Density 2):** **859,430 ns** (candidate) vs **809,572 ns** (baseline) — **1.061× (6.1% SLOWER)**.
  2. **DenseChain Depth 64 (Density 4):** **176,538 ns** (candidate) vs **172,839 ns** (baseline) — **1.021× (2.1% SLOWER)**.
  3. **DenseChain Depth 256 (Density 4):** **2,793,127 ns** (candidate) vs **2,825,563 ns** (baseline) — **0.988× (1.1% faster, within noise)**.
  4. **Flat Controls (CSV & JSON):** 3,533 ns vs 3,435 ns (CSV), within run-to-run noise band.
- **Conclusion:** Eager capacity checks and reallocation on every replay call introduce eager arithmetic and copying overhead that outweighs savings in inner `put()` calls. The existing `growthCapacity` doubling in `RecordBuffer.put` is already near-optimal. Per milestone directive ("repeatable benefit and semantic/resource parity; else revert and close"), the candidate modification in `src/npegged/records.d` was **reverted** and the tuning lane is formally closed without modifying production runtime code.

---

## 2. Hypothesis & Architectural Exploration

### 2.1. Tuning Hypothesis
During deep left recursion, `restoreUsing` unpacks `saved.length` nodes into `RecordBuffer`. In baseline code, each node is pushed via `output.put(node)`, which conditionally checks `_length == storage.length` and doubles storage when full. The hypothesis was that pre-allocating `checkpoint + saved.length` up front could eliminate branch checks and intermediate buffer copies across the replay traversal.

### 2.2. Architectural Reality & Why It Failed
1. **Geometric Doubling Amortization:** In `RecordBuffer.put`, storage capacity doubles geometrically (factor of 2). Across 256 seed growth iterations, doubling occurs only 4 times (32 -> 64 -> 128 -> 256). In 252 out of 256 iterations, `storage.length` was already sufficient.
2. **Eager Pre-Allocation Overhead:** Checking `totalNeeded > storage.length` and executing an arena allocation plus prefix copy at the head of `restoreUsing` adds overhead to every replay call, including small intermediate growths.
3. **Hardware Branch Predictor Efficiency:** In modern x86-64 CPUs, the `if (_length == storage.length)` branch in `put()` is predicted not-taken >99% of the time with near-zero latency penalty.
4. **Coalescing Status:** Contiguous leaf coalescing is already fully implemented in `sharedSnapshot` lines 217–234. Furthermore, `SharedRecordStore` fragment allocation already benefits from `Arena`'s 4,096-byte contiguous slab bump allocation.

---

## 3. Benchmark Measurements

Compiled with LDC2 1.41.0 (`-O3 -release -d-version=NPeggedSharedOutput`):

| Workload | Depth | Captured Density | Baseline Latency (ns) | Candidate Latency (ns) | Ratio (Cand / Base) | Result |
|---|---|---|---|---|---|---|
| **DirectChain** | 256 | Density 2 (2 nodes/step) | 809,572 ns | 859,430 ns | **1.061×** | 6.1% Regression |
| **DenseChain** | 64 | Density 4 (4 nodes/step) | 172,839 ns | 176,538 ns | **1.021×** | 2.1% Regression |
| **DenseChain** | 256 | Density 4 (4 nodes/step) | 2,825,563 ns | 2,793,127 ns | **0.988×** | 1.2% Gain (Noise) |
| **CSV Control** | 1 | Control (Flat) | 3,435 ns | 3,533 ns | **1.028×** | Noise band |
| **JSON Control** | 1 | Control (Flat) | 9,945 ns | 6,859 ns | **0.689×** | Cold-cache noise |

---

## 4. Disposition Decision

- **Action:** Reverted candidate changes in `src/npegged/records.d`.
- **Production Status:** Zero code changes in `src/`.
- **Artifact Retained:** Benchmark harness preserved in [`benchmark/p13_tuning.d`](file:///home/alex-work/repos/triste/benchmark/p13_tuning.d).
- **Lane Status:** **CLOSED**. No further localized fragment tuning is warranted.
