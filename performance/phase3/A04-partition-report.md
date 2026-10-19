# A04 — 1.5× Performance Deficit Partition Report

## 1. Executive Summary & Deficit Attribution

- **Total Observations:** 513 paired comparisons (171 unique case/output pairs across 3 repeated runs).
- **Exceeding 1.5×:** **420 / 513 observations (81.9%)** and **143 / 171 unique cases (83.6%)**.
- **Cumulative Wall-Clock Latency:** Candidate NPegged: **1.390 ms** | Reference Handwritten: **0.705 ms**.
- **Cumulative 1.5× Time Deficit:** **0.501 ms** (representing the wall-clock time that candidate execution exceeds $1.5\times$ of reference).
- **Key Discovery (Count vs Wall-Clock Inversion):**
  - **Small inputs (< 100 bytes)** account for **65.5% of failing checks by count** (275 / 420 failures), but only **5.4% of the wall-clock time deficit**.
  - **Medium and large inputs (>= 100 bytes)** account for only 34.5% of failing checks by count, but **94.6% of the wall-clock deficit**.
  - Optimizing purely for failure count without weighting by latency would over-index on sub-microsecond timer noise, while optimizing for scalable throughput addresses the overwhelming bulk of runtime cost.

## 2. Partition by Grammar Family

| Grammar Family | Unique Cases | Total Checks | $\le 1.5\times$ Pass | Failing Checks | Deficit Wall-Clock (ms) | Deficit Share | Candidate Time | Reference Time |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **`Ambiguous`** | 9 | 27 | 24 (88.9%) | 3 (11.1%) | 0.000 ms | **0.0%** | 0.006 ms | 0.006 ms |
| **`Arithmetic`** | 33 | 99 | 9 (9.1%) | 90 (90.9%) | 0.118 ms | **23.6%** | 0.407 ms | 0.207 ms |
| **`CSV`** | 36 | 108 | 8 (7.4%) | 100 (92.6%) | 0.113 ms | **22.5%** | 0.254 ms | 0.094 ms |
| **`JSON`** | 30 | 90 | 18 (20.0%) | 72 (80.0%) | 0.063 ms | **12.6%** | 0.192 ms | 0.108 ms |
| **`Numbers`** | 33 | 99 | 16 (16.2%) | 83 (83.8%) | 0.018 ms | **3.7%** | 0.133 ms | 0.090 ms |
| **`PEGGrammar`** | 30 | 90 | 18 (20.0%) | 72 (80.0%) | 0.188 ms | **37.6%** | 0.399 ms | 0.201 ms |
| **Total** | **171** | **513** | **93** | **420** | **0.501 ms** | **100.0%** | **1.390 ms** | **0.705 ms** |

## 3. Partition by Input Size & Noise Profile

| Input Size Class | Size Range | Failing Checks | Deficit Wall-Clock (ms) | Deficit Share | Candidate Mean Latency | Ref Mean Latency | Noise Profile |
|---|---|---:|---:|---:|---:|---:|---|
| **`small`** | < 100 bytes | 275 / 288 (95.5%) | 0.027 ms | **5.4%** | 251.9 ns | 105.7 ns | High jitter; sub-microsecond setup overhead dominates |
| **`medium`** | 100 – 1,000 bytes | 64 / 90 (71.1%) | 0.134 ms | **26.7%** | 3070.1 ns | 1075.8 ns | Moderate jitter; rule traversal & memo overheads |
| **`large`** | > 1,000 bytes | 81 / 135 (60.0%) | 0.340 ms | **67.9%** | 7714.3 ns | 4283.0 ns | Low jitter; scalable scanner & allocation bottlenecks |

## 4. Partition by Output Mode & Selected Record Density

| Output Mode | Obligation | Failing Checks | Median Ratio | Deficit Wall-Clock (ms) | Deficit Share | Primary Cost Driver |
|---|---|---:|---:|---:|---:|---|
| **`validation`** | Recognition only; zero output nodes | 136 / 171 (79.5%) | 1.991x | 0.107 ms | **21.4%** | Combinator dispatch, memo checks, character scanning |
| **`spans`** | Flat span intervals; parent = max | 143 / 171 (83.6%) | 2.341x | 0.202 ms | **40.4%** | Dynamic buffer allocation, span bookkeeping, slice captures |
| **`tree`** | Full hierarchy; parent indices intact | 141 / 171 (82.5%) | 2.026x | 0.191 ms | **38.2%** | AST node hierarchy tracking, parent index rewrites, growth copies |

## 5. Partition by Outcome (Accepted vs Failed vs Truncated)

| Parse Outcome | Checks | Failing Checks | Deficit Wall-Clock (ms) | Deficit Share | Characteristic |
|---|---:|---:|---:|---:|---|
| **Valid / Complete Parse** | 315 | 243 (77.1%) | 0.470 ms | **93.9%** | Complete grammar traversal; all matching rules evaluated |
| **Early Syntax Error / Mismatch** | 135 | 126 (93.3%) | 0.004 ms | **0.9%** | Fast failure at first syntax violation; minimal runtime |
| **Truncated Input** | 63 | 51 (81.0%) | 0.026 ms | **5.2%** | Deep traversal followed by premature EOF; tests failure frontier |

## 6. Partition by Grammar Recursion Shape

| Shape | Grammar Families | Failing Checks | Deficit Wall-Clock (ms) | Deficit Share | Packrat / Ascent Impact |
|---|---|---:|---:|---:|---|
| **Direct / Indirect Left Recursion** | Arithmetic, PEGGrammar | 162 (85.7%) | 0.307 ms | **61.3%** | Iterative seed growth; memo snapshot & rollback cycles |
| **Non-Left Recursive (LL / PEG)** | CSV, JSON, Numbers, Ambiguous | 258 (79.6%) | 0.194 ms | **38.7%** | Linear descent; choice probing and token scanning dominates |

## 7. Representative Workloads (Top Bottlenecks)

The top 8 representative workloads account for **78.4% of the entire 1.5× deficit**. Targeting these cases provides maximum gate-wide leverage:

| Rank | Workload | Mode | Bytes | Nodes | Median Ratio | Deficit (ms) | Deficit Share | Bottleneck Characteristics |
|---|---|---|---:|---:|---:|---:|---:|---|
| **1** | `PEGGrammar.ManyRules` | `tree` | 1538 | 641 | **3.032x** | 0.045 ms | **9.0%** | High rule count; heavy choice discrimination and packrat lookup overhead |
| **2** | `PEGGrammar.ManyRules` | `spans` | 1538 | 128 | **4.119x** | 0.044 ms | **8.9%** | High rule count; heavy choice discrimination and packrat lookup overhead |
| **3** | `CSV.Flat` | `tree` | 1025 | 514 | **4.221x** | 0.042 ms | **8.4%** | Tight repetitive delimiter scanning and continuous record node appends |
| **4** | `CSV.Flat` | `spans` | 1025 | 513 | **4.166x** | 0.041 ms | **8.2%** | Tight repetitive delimiter scanning and continuous record node appends |
| **5** | `Arithmetic.Flat` | `spans` | 1025 | 513 | **2.362x** | 0.036 ms | **7.3%** | Deep left-recursive expression chains; repeated packrat seed growth |
| **6** | `Arithmetic.Flat` | `validation` | 1025 | 0 | **2.593x** | 0.027 ms | **5.4%** | Deep left-recursive expression chains; repeated packrat seed growth |
| **7** | `PEGGrammar.ManyRules` | `validation` | 1538 | 0 | **4.294x** | 0.027 ms | **5.4%** | High rule count; heavy choice discrimination and packrat lookup overhead |
| **8** | `Arithmetic.Flat` | `tree` | 1025 | 1541 | **1.900x** | 0.027 ms | **5.3%** | Deep left-recursive expression chains; repeated packrat seed growth |
| | **Top 8 Cumulative** | | | | | **0.290 ms** | **57.9%** | |

## 8. Guarded Control Workloads

These workloads already pass well within $\le 1.5\times$. Any optimization MUST NOT regress these controls:

| Control Workload | Mode | Bytes | Median Ratio | Candidate Latency | Reference Latency | Reason for Inclusion |
|---|---|---:|---:|---:|---:|---|
| `PEGGrammar.LongLiteral` | `tree` | 8202 | **0.713x** | 4121.0 ns | 5784.0 ns | Long token literal match; DFA / scanner fast path must stay fast |
| `Numbers.BinaryLong` | `spans` | 8194 | **0.872x** | 3387.2 ns | 3883.4 ns | Pure binary number string; tests leaf numeric token recognition with zero allocation regression |
| `Ambiguous.Retry` | `validation` | 257 | **0.611x** | 134.1 ns | 219.0 ns | Backtracking choice retry; tests branch prediction and failure-recovery bounds |

## 9. Next Steps for Optimization Prioritization

Based on the partition analysis:
1. **B01 Equal-Work Comparator Audit:** Verify whether handwritten comparators for `PEGGrammar.ManyRules`, `CSV.Flat`, and `Arithmetic.Flat` carry identical obligations (node allocation, error preservation, input copying).
2. **B02 Two-Dimensional Time Attribution:** Separate fixed setup overhead ($T_{fixed}$) from per-byte scanning ($a$) and per-node allocation ($b$) on the top representative workloads.
3. **Deprioritize Micro-Noise:** Do not invest in specialized tricks for sub-100B cases (like `PEGGrammar.Permissive` or `Trailing`), which account for 65.5% of count failures but only 5.4% of runtime cost.
