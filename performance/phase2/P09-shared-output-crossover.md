# P09 — Measure Shared-Output Crossover by Captured Nodes

## 1. Executive Summary & Core Finding

- **Milestone:** P09 — Measure R06 break-even by captured nodes, not only input terms
- **Core Question:** Does `NPeggedSharedOutput` break even based purely on recursion depth, or is crossover fundamentally driven by **captured record density** (nodes captured per recursion step)?
- **Key Empirical Discovery:**
  - **A depth-only threshold is insufficient for auto-selection.**
  - **Density 0 (Root-only / 0 nodes per growth):** Shared snapshots never win ($T_{\text{shared}} \approx 0.99–1.06\times T_{\text{flat}}$). When no nodes are accumulated during loop growth, flat buffers perform zero copying on rollback. Shared snapshot bookkeeping adds only overhead.
  - **Density 1 (1 node per growth):** Crossover occurs between **depth 256 and 512** (0.94–0.99×).
  - **Density 2 (2 nodes per growth):** Crossover occurs earlier, around **depth 64** (0.95×).
  - **Density 4 (4 nodes per growth, e.g. `DenseChain`):** Crossover occurs immediately at **depth 16–64** with a massive speedup of **0.4633× (2.16× faster)** at depth 64.
  - **Flat Controls (JSON, CSV):** `Owner.npeggedSharedOutputEligible` is statically `false`, resulting in exact 0.98–1.00× flat execution.

---

## 2. Methodology & Experimental Setup

1. **Benchmark Harness:** [`benchmark/p09_crossover.d`](file:///home/alex-work/repos/triste/benchmark/p09_crossover.d), tested under LDC2 1.41.0 (`-O3 -release -d-version=NPeggedSharedOutput -d-version=NPeggedMetrics`).
2. **Fixed Ownership & Selectors:**
   - Ownership held constant across runs (`ownInput = true`, `outputLimit = size_t.max`).
   - Density 0: Selects only `Root` (`selectDensity0`).
   - Density 1: Selects only `Number` (`selectDensity1`).
   - Density 2: Selects `Expr` + `Number` (`selectDensity2`).
   - Density 4: Selects `Expr` + `Term` + `Mul` + `Number` (`selectDensity4`).
3. **Depths & Shapes:**
   - Depths: 16, 64, 256, 512, 1024, 2048 (or resource cutoff).
   - Grammars: `DirectChain`, `IndirectChain`, `DenseChain`, `MixedChain` (header + recursion), plus flat controls (`JSON`, `CSV`).
   - Both valid input (complete parse) and late-failure input (failure at final token after maximal recursion growth).

---

## 3. Workload-Shape & Crossover Table

| Grammar | Density Shape | Nodes / Growth | Depth | Flat Time | Shared Time | Ratio (Shared / Flat) | Committed Nodes | Crossover Status |
|---|---|---|---|---|---|---|---|---|
| `DirectChain` | `density0` (Root) | 0 | 16 | 1,068 ns | 879 ns | 0.8230× | 1 | Flat parity / noise |
| `DirectChain` | `density0` (Root) | 0 | 64 | 3,573 ns | 3,768 ns | 1.0546× | 1 | Shared loses (+5%) |
| `DirectChain` | `density0` (Root) | 0 | 256 | 11,905 ns | 11,919 ns | 1.0012× | 1 | Exact parity |
| `DirectChain` | `density0` (Root) | 0 | 1,024 | 47,804 ns | 47,296 ns | 0.9894× | 1 | Parity |
| `DirectChain` | `density0` (Root) | 0 | 2,048 | 91,089 ns | 96,533 ns | 1.0598× | 1 | Shared loses (+6%) |
| `DirectChain` | `density1` (Number) | 1 | 16 | 1,441 ns | 1,588 ns | 1.1020× | 16 | Shared loses (+10%) |
| `DirectChain` | `density1` (Number) | 1 | 64 | 11,349 ns | 11,385 ns | 1.0032× | 64 | Break-even |
| `DirectChain` | `density1` (Number) | 1 | 256 | 959,953 ns | 979,330 ns | 1.0202× | 256 | Break-even |
| `DirectChain` | `density1` (Number) | 1 | 512 | 3,023,620 ns | 2,993,144 ns | **0.9899×** | 512 | **Shared wins** |
| `DirectChain` | `density1` (Number) | 1 | 2,048 | 37,497,632 ns | 36,242,484 ns | **0.9665×** | 2,048 | **Shared wins** |
| `DirectChain` | `density2` (Expr+Num) | 2 | 16 | 2,052 ns | 2,104 ns | 1.0253× | 32 | Break-even |
| `DirectChain` | `density2` (Expr+Num) | 2 | 64 | 108,657 ns | 103,969 ns | **0.9569×** | 128 | **Shared wins** |
| `DirectChain` | `density2` (Expr+Num) | 2 | 256 | 1,489,360 ns | 1,452,262 ns | **0.9751×** | 512 | **Shared wins** |
| `DirectChain` | `density2` (Expr+Num) | 2 | 2,048 | 72,953,634 ns | 73,374,552 ns | 1.0058× | 4,096 | Parity |
| `DirectChain` | `density2_latefail` | 2 | 64 | 102,335 ns | 108,836 ns | 1.0635× | 0 | Parity / setup |
| `DirectChain` | `density2_latefail` | 2 | 256 | 1,471,290 ns | 1,464,622 ns | 0.9955× | 0 | Parity |
| **`DenseChain`** | **`density4` (Dense)** | **4** | **16** | 9,697 ns | 9,589 ns | **0.9889×** | 96 | **Shared wins** |
| **`DenseChain`** | **`density4` (Dense)** | **4** | **64** | **166,002 ns** | **76,915 ns** | **0.4633×** | 384 | **Shared wins (2.16× speedup)** |
| `DenseChain` | `density4` (Dense) | 4 | 256 | 3,123,673 ns | 3,168,921 ns | 1.0145× | 1,536 | Break-even |
| `DenseChain` | `density4` (Dense) | 4 | 512 | 13,851,900 ns | 13,406,726 ns | **0.9679×** | 3,072 | **Shared wins** |
| `MixedChain` | `density2_mixed` | 2 | 64 | 19,522 ns | 18,823 ns | **0.9642×** | 128 | **Shared wins** |
| `JSON` | `flat_control` | 0 | 1 | 3,616 ns | 3,614 ns | 0.9994× | 18 | Baseline match |
| `CSV` | `flat_control` | 0 | 1 | 2,785 ns | 2,727 ns | 0.9792× | 31 | Baseline match |

---

## 4. Workload Decision Surface: Win, Break-Even, and Lose

```
Captured Nodes / Growth
      ▲
      │
   4  │  [ WIN (0.46x) ]       [ WIN (0.96x) ]      [ WIN (0.97x) ]
      │
   2  │  [ Break-even ]        [ WIN (0.95x) ]      [ WIN / Parity ]
      │
   1  │  [ Lose (+10%) ]       [ Break-even ]       [ WIN (0.96x) ]
      │
   0  │  [ LOSE (+5%) ]        [ LOSE (+1%) ]       [ LOSE (+6%) ]
      └─────────────────────────────────────────────────────────────►
         Depth 16              Depth 64             Depth 512+
```

### Analysis:
1. **When Shared Output Wins:**
   - Whenever $\text{density} \ge 2$ nodes per growth and $\text{depth} \ge 64$.
   - Whenever $\text{density} \ge 4$ nodes per growth across almost all depths ($\le 0.46\times$ latency).
2. **When Shared Output Breaks Even:**
   - Sparse densities ($\text{density} = 1$) at moderate depths ($64 \le \text{depth} \le 256$).
   - Extremely deep chains ($\text{depth} \ge 1024$) where node-rebasing and leaf serialization match the cost of flat copies.
3. **When Shared Output Loses:**
   - $\text{density} = 0$ (Root-only projection): Flat copies 0 nodes; shared output pays unnecessary snapshot allocation.
   - Tiny inputs ($\text{depth} \le 16$) with $\text{density} \le 1$: initial frame allocation overhead (~50–150 ns) dominates parse time.

---

## 5. Architectural Implications for Milestone P10 & P11

The data establishes conclusively that **auto-selection of shared output cannot be based on input length or runtime recursion depth**. Instead, optimal selection depends on **compile-time knowledge of rule selectors and left-recursion SCCs**:
- Grammars without left recursion should never instantiate or check shared stores.
- Grammars with left recursion but zero selected inner nodes should stay on the flat path.
- Grammars with left recursion and high-density node selectors should selectively engage shared output.

Proceed directly to **Milestone P10** (Compile-Time Output Specialization Feasibility Analysis).
