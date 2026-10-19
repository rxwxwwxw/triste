# B02 — Two-Dimensional Time Attribution Report

## 1. Executive Summary & Attribution Model

- **Milestone:** B02 — Two-dimensional time attribution
- **Descriptive Model:** $T \approx T_{\text{fixed}} + a \cdot \text{inputBytes} + b \cdot \text{nodes} + c \cdot \text{failedProbes}$
  *(Note: This linear regression model represents a descriptive decomposition of empirical wall-clock cost across the 513 paired observations; it is not causal proof.)*
- **Key Findings:**
  1. **Fixed Invocation Cost ($T_{fixed}$):** NPegged incurs **449.5 ns** vs Handwritten **210.5 ns** (fixed deficit: **194.1 ns**). This reflects `ParseContext` initialization, `RecordBuffer` setup, and bump arena bookkeeping.
  2. **Per-Byte Scanning Cost ($a$):** NPegged incurs **0.393 ns/byte** vs Handwritten **0.349 ns/byte** (per-byte deficit: **0.024 ns/byte**). Token character matching is efficient, running within ~1.12× of handwritten scanning.
  3. **Per-Output-Node Cost ($b$):** NPegged incurs **30.881 ns/node** vs Handwritten **13.807 ns/node** (per-node deficit: **9.964 ns/node**). NPegged pays **2.24× higher cost per output node** due to transactional buffer bounds checks, growth reallocations, and parent-pointer tracking.
  4. **Per-Failed-Probe Cost ($c$):** NPegged incurs **87.962 ns/probe** vs Handwritten **16.378 ns/probe** (per-probe deficit: **62.102 ns/probe**). Choice exploration and failure backtracking in PEG pays combinator chaining and diagnostic recording overhead.

## 2. Global Model Parameters & Goodness of Fit

| Parameter | NPegged Candidate | Handwritten Reference | Deficit (NP – 1.5×HW) | Unit | Interpretation |
|---|---:|---:|---:|---|---|
| **$T_{fixed}$** | **449.51 ns** | **210.53 ns** | **194.13 ns** | ns | Fixed entry/context/arena setup |
| **$a$** (Bytes) | **0.3928 ns** | **0.3495 ns** | **0.0235 ns** | ns / byte | Per-byte scanning throughput |
| **$b$** (Nodes) | **30.8811 ns** | **13.8075 ns** | **9.9644 ns** | ns / node | Node construction & buffer growth |
| **$c$** (Probes) | **87.9619 ns** | **16.3782 ns** | **62.1021 ns** | ns / probe | Choice traversal & failure rollback |
| **$R^2$** | **0.8389** | **0.8240** | **0.6691** | — | Variance explained by model |
| **MAE** | **962.0 ns** | **563.9 ns** | **681.7 ns** | ns | Mean absolute error of fit |

## 3. Separation of Parser Obligations by Output Mode

| Output Mode | Target Engine | $T_{fixed}$ (ns) | $a$ (ns/B) | $b$ (ns/node) | $c$ (ns/probe) | $R^2$ | Primary Cost Driver |
|---|---|---:|---:|---:|---:|---:|---|
| **`validation`** | NPegged | 561.4 | 0.397 | 0.000 | 84.294 | 0.3823 | Choice testing and character scanning ($c$ and $a$) |
| | Handwritten | 295.0 | 0.345 | 0.000 | 19.197 | 0.5109 | |
| | **Deficit** | **175.3** | **0.036** | **0.000** | **53.870** | **0.4461** | |
| **`spans`** | NPegged | 148.5 | 0.401 | 50.814 | 106.720 | 0.9427 | High per-node allocation overhead ($b = 51.2$ ns/node) |
| | Handwritten | 137.6 | 0.353 | 17.285 | 22.479 | 0.7856 | |
| | **Deficit** | **9.1** | **0.030** | **24.415** | **71.718** | **0.9421** | |
| **`tree`** | NPegged | 303.7 | 0.400 | 28.401 | 67.595 | 0.9711 | AST tree construction & hierarchical parent tracking |
| | Handwritten | 125.9 | 0.354 | 13.758 | 4.928 | 0.9450 | |
| | **Deficit** | **177.4** | **0.017** | **7.586** | **59.332** | **0.7249** | |

## 4. Breakdown Across Grammar Families

| Family | Deficit Share | Dominant Parameter | NPegged Model | Handwritten Model | Analysis |
|---|---:|---|---|---|---|
| **`PEGGrammar`** | **37.6%** | Choice Probes ($c$) | $T = 441 + 0.36L + 22.7N + 116.5C$ | $T = 141 + 0.68L + 9.9N + 20.2C$ | High rule diversity; heavy packrat lookup and choice dispatch. |
| **`CSV`** | **22.5%** | Node Materialization ($b$) | $T = -22 + 0.39L + 38.8N + 125.7C$ | $T = -5 + 0.23L + 8.6N + 48.4C$ | High node density (1 node per 2 bytes); record buffer growth dominates. |
| **`Arithmetic`** | **23.6%** | Left Recursion Ascent ($a$, $b$) | $T = 1190 + 0.41L + 29.5N + 51.2C$ | $T = 433 + 0.47L + 15.0N + 19.0C$ | Expression precedence growth; iterative packrat seed ascent. |
| **`JSON`** | **12.6%** | Balanced ($a$, $b$, $c$) | $T = 1130 + 0.34L + 19.3N + 42.7C$ | $T = 312 + 0.44L + 9.1N + 13.4C$ | Recursive descent with object/array branching. |
| **`Numbers`** | **3.7%** | Per-Byte Scanning ($a$) | $T = 35 + 0.43L + -65.9N + 35.1C$ | $T = 33 + 0.27L + 133.5N + 33.2C$ | Tight numeric lexing; already close to baseline. |

## 5. Concrete Expensive Sites & Amdahl Ceiling Bounds

Using the fitted model parameters and the wall-clock deficit distribution from A04, we evaluate four potential optimization targets to establish their maximum theoretical and attainable gate-wide leverage:

| Proposed Optimization Site | Target Parameter | Primary Affected Workloads | Total Deficit Addressed | Max Attainable Gate-Wide Speedup | Amdahl Assessment & Priority |
|---|---|---|---:|---:|---|
| **Site 1: `records.d:273-296` (`RecordBuffer.put` & inlining)** | Per-Node Cost ($b$) | `CSV.Flat`, `PEGGrammar.ManyRules`, all `spans`/`tree` | **0.197 ms (39.3%)** | **~19.6% latency reduction** | **HIGH PRIORITY (HIGH CEILING):** Inlining bounds checks and specialized non-transactional node appends directly reduces $b$. |
| **Site 2: `grammar.d:2470` (Choice dispatch & prefix discrimination)** | Failed Probes ($c$) | `PEGGrammar.ManyRules`, `PEGGrammar.Deep`, `Arithmetic` | **0.188 ms (37.6%)** | **~18.8% latency reduction** | **HIGH PRIORITY (HIGH CEILING):** Direct branch lowering on disjoint prefixes avoids combinator chaining and failed probe overhead. |
| **Site 3: `grammar.d:2370` (Flat scanner loop vectorization)** | Per-Byte Scanning ($a$) | `CSV.Flat`, `PEGGrammar.LongLiteral` | **0.083 ms (16.6%)** | **~8.3% latency reduction** | **MEDIUM PRIORITY:** Tightens scanner loops for delimiter-separated tokens. |
| **Site 4: `peg.d:288` (Fixed invocation / memo table setup)** | Fixed Cost ($T_{fixed}$) | Tiny / Small cases (< 100 bytes) | **0.027 ms (5.4%)** | **<= 5.4% latency reduction** | **LOW PRIORITY (LOW CEILING):** Deprioritized by Amdahl's Law; eliminating 100% of fixed setup cannot move the global gate significantly. |

## 6. Optimization Recommendation for Subsequent Tasks

The two-dimensional attribution analysis establishes that:
1. **Top Gate Bottleneck 1 (Node Materialization $b$):** Record construction in `records.d` is 2.24× slower than handwritten node emission. Inlining node appends and simplifying parent pointer indexing provides the largest attainable gate-wide improvement (up to ~19.6% latency reduction).
2. **Top Gate Bottleneck 2 (Choice Dispatch $c$):** Sequential combinator failure in PEGGrammar rules pays 5.37× higher penalty per alternative than handwritten `switch`/lookahead branches.
3. **Deprioritized Low-Ceiling Work:** Micro-optimizations targeting fixed setup on small inputs ($T_{fixed}$) are bounded at a maximum of 5.4% improvement and should not be pursued.
