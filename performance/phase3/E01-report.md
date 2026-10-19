# E01 — Integrated Phase 3 Performance Gate & Differential Oracle Audit

## 1. Executive Summary & Gate Disposition

- **Milestone:** E01 — Integrated 1.5× Performance Audit (Final Phase 3 Gate)
- **Final Gate Status:** **TARGET UNMET AT ≤1.5× TARGET** (91 / 513 observations pass ≤1.5×, 17.7%; 28 / 171 unique cases pass ≤1.5×, 16.4%).
- **Baseline Status at ≤5.0×:** **100% PASS UNIQUE MEDIANS** (512 / 513 observations pass ≤5.0×, 99.8%; 171 / 171 unique case medians pass ≤5.0×, 100.0%).
- **Current Global Median Ratio:** **2.141×** of handwritten D reference baseline (A03 baseline: 2.102×, P15 release: 2.132×, post-H07: 2.122×).
- **Tail Ratios:** P90 = **3.384×**, P95 = **4.150×**, Worst = **5.165×** (PEGGrammar.Permissive validation run 3 at 5.165×; unique case median is 4.811×).
- **Best Ratio:** **0.592×** (JSON.SingleNumber spans run 3 at 0.592×; candidate 38.6 ns vs reference 65.2 ns).
- **Semantic & Output Parity:** **100% PASS** (all 513 checks match handwritten D acceptance, tokens, spans, AST structure, and hashes byte-for-byte; zero data loss).
- **Phase 3 Success Disposition:** **UNMET — Phase 3 is NOT successful at meeting the ≤1.5× target gate-wide.** Per the universal contract in `PERFORMANCE_PLAN_PHASE3.md`, the target is not reset to 5.0×; rather, the documented attribution waterfall provides the basis for subsequent compiler/lowering work.

## 2. Historical Gate Progression Across Milestones

| Dataset / Milestone | Revision | Total Checks | ≤1.5× Checks | ≤5.0× Checks | Median Ratio | P90 Ratio | P95 Ratio | Worst Ratio |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| **Post-H07 Gate** | `4726c4e` | 513 | 97 (18.9%) | 513 (100.0%) | 2.122× | 3.416× | 4.185× | 4.816× |
| **P15 Release Matrix** | `34f475c` | 513 | 84 (16.4%) | 512 (99.8%) | 2.132× | 3.390× | 4.120× | 5.075× |
| **A03 Phase 3 Baseline** | `8e9407b` | 513 | 93 (18.1%) | 512 (99.8%) | 2.102× | 3.491× | 4.129× | 5.182× |
| **B03 Pre-Optimization Gate** | `dcf6b1b` | 513 | 89 (17.3%) | 510 (99.4%) | 2.226× | 3.445× | 4.072× | 5.611× |
| **E01 Final Integrated Audit** | `2328f44` | 513 | 91 (17.7%) | 512 (99.8%) | 2.141× | 3.384× | 4.150× | 5.165× |

## 3. Ratio Distribution & Output Mode Breakdown

```
Current Ratio Distribution (E01 vs Handwritten D Baseline):
  [ <= 1.0x     ] █████                     (51 checks, 9.9%)
  [ 1.0x - 1.5x ] ████                      (40 checks, 7.8%)
  [ 1.5x - 2.0x ] ████████████              (128 checks, 25.0%)
  [ 2.0x - 3.0x ] ████████████████████      (201 checks, 39.2%)
  [ 3.0x - 4.0x ] ██████                    (66 checks, 12.9%)
  [ 4.0x - 5.0x ] ███                       (26 checks, 5.1%)
  [ > 5.0x      ]                           (1 checks, 0.2%)
```

### Breakdown by Output Mode

| Output Mode | Total Paired Checks | ≤1.5× Pass | 1.5× - 5.0× Range | >5.0× Exceeded | Median Ratio | P90 Ratio | P95 Ratio | Max Ratio |
|---|---|---|---|---|---|---|---|---|
| **`validation`** | 171 | 35 (20.5%) | 135 (78.9%) | 1 (0.6%) | 1.950× | 3.702× | 4.330× | 5.165× |
| **`spans`** | 171 | 26 (15.2%) | 145 (84.8%) | 0 (0.0%) | 2.374× | 3.415× | 4.150× | 4.575× |
| **`tree`** | 171 | 30 (17.5%) | 141 (82.5%) | 0 (0.0%) | 2.114× | 3.177× | 3.407× | 4.606× |
| **Total** | **513** | **91 (17.7%)** | **421 (82.1%)** | **1 (0.2%)** | **2.141×** | **3.384×** | **4.150×** | **5.165×** |

## 4. Grammar Family Breakdown & Deficit Allocation

Workloads grouped by grammar family across all modes and runs:

| Grammar Family | Unique Cases | Total Checks | ≤1.5× Pass | Median Ratio | Worst Ratio | Candidate Wall (ns) | Reference Wall (ns) | Target Deficit (ns) | Share of Deficit |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **`PEGGrammar`** | 30 | 90 | 18 (20.0%) | 3.004× | 5.165× | 395,582.8 | 200,321.4 | 184,796.2 | **37.4%** |
| **`Arithmetic`** | 33 | 99 | 9 (9.1%) | 2.235× | 3.128× | 403,602.1 | 204,425.1 | 118,515.7 | **24.0%** |
| **`CSV`** | 36 | 108 | 9 (8.3%) | 2.017× | 4.606× | 250,987.5 | 93,991.1 | 110,588.0 | **22.4%** |
| **`JSON`** | 30 | 90 | 18 (20.0%) | 2.233× | 3.702× | 188,848.0 | 106,315.6 | 61,780.0 | **12.5%** |
| **`Numbers`** | 33 | 99 | 12 (12.1%) | 1.830× | 2.843× | 131,294.4 | 88,339.9 | 18,865.7 | **3.8%** |
| **`Ambiguous`** | 9 | 27 | 25 (92.6%) | 1.119× | 1.625× | 6,026.9 | 5,473.0 | 29.3 | **0.0%** |
| **Total** | **171** | **513** | **91 (17.7%)** | **2.141×** | **5.165×** | **1,376,341.6** | **698,866.0** | **494,574.8** | **100.0%** |

## 5. Differential Oracle & Exact Correctness Verification

- **Differential Suite (`tests/differential.d`):** Verified on both **DMD** and **LDC2** under `-defaultlib=druntime` / `-defaultlib=druntime-ldc` and `-fno-exceptions`. 100% agreement across 17 source modules between reference combinators and candidate direct lowerings.
- **Full Test Suite & Unit Coverage:** All 17 modules in `src/` exceed 90% branch and line coverage under `scripts/coverage.sh`.
- **Memory & Sanitizer Safety:**
  - **ASan/LSan (`ldc2 -fsanitize=address`):** Clean exit code 0; zero leaks detected.
  - **Valgrind Memcheck (`valgrind --tool=memcheck --leak-check=full`):** 0 errors from 0 contexts, 0 bytes definitely lost, 0 bytes indirectly lost across full unit suite and integration tests.
- **Resource Boundaries & Sticky Failure:** Verified under `tests/bounded_shared_output.d` and `tests/pure_islands_budget.d`: exact status codes (`resourceLimit` vs `outOfMemory`), boundary-adjacent quota checks, deterministic state rollback, and zero unhandled exceptions (`nothrow`).

## 6. Audit of Specialized & Opt-In Modes (Phase 3 Subsystems)

Phase 3 evaluated four distinct optimization and acceleration initiatives outside the default gate:

### 6.1. Shared Output for Left Recursion (C01, C02, C03)
- **Active Performance (C01):** Active shared output achieves genuine **~0.39–0.41× flat latency** (approx 2.5× speedup) on dense, successful 2048-term left-recursive chains by drastically reducing snapshot copies ($O(N)$ vs $O(N^2)$).
- **Bounded Memory Correctness (C02):** Proved concrete finite-memory incompatibility: at a 4119-byte scratch limit, flat mode succeeds while shared mode requires 8215 bytes for its initial fragment allocation. Shared output cannot be safely activated for general finite-budget default operation without altering semantic quota failures.
- **Gate Relevance (C03):** Proved that **0/6 maintained gate grammar families contain left-recursive rules** under selective memoization. Optimizing shared replay materialization has an Amdahl fraction of f = 0 for the gate. The optimization branch was deferred as gate-irrelevant while keeping R06 opt-in.

### 6.2. Action-Bearing Pure Islands (D01, D02)
- **Active Performance (D01):** Proved up to **~0.0029× latency** (approx 340× speedup) for proved pure sub-rules (`Root` recognition) in direct action grammars with explicitly unlimited budgets.
- **Guarded Fallback & Eligibility (D02):** Proved that default ParseContext limits result in **0% default-limit eligibility**. Guarded fallback incurs small compile-flag and dispatch overheads (~3–5%). General finite-budget accounting is not feasible with the current representation because scalar routes skip intermediate parser steps and arena accounting.
- **Policy:** Retained as a specialized, documented opt-in mode (`docs/PURE_ISLAND_POLICY.md`).

### 6.3. Recursive Ascent for Left Recursion (X07)
- **Semantic Parity Audit (X07):** Evaluated manual `directAscent` prototype against generated left-recursive reference parser across 273 configurations. Proved **224 complete-tree parity failures and 21 parse-status discrepancies** at quota boundaries.
- **Disposition:** Prototype is **not generally equivalent** to generated left-recursion semantics. Retained strictly as a specialized/manual experimental helper; no automatic lowering or promotion into maintained grammar pipelines.

### 6.4. Outlining Record-Buffer Growth (B03) & Memo Bypass (B04)
- **B03 Growth Outlining:** Moving `RecordBuffer.put` cold growth path out of line regressed several high-density workloads (`Numbers.BinaryLong` +16.2%, `Arithmetic.Deep` +10.4%) and failed acceptance criteria. Rejected and closed with `NO_CHANGE`.
- **B04 Memo Bypass:** Comprehensive Callgrind profiles and AST inspection proved **zero memoized rules** in the default gate under selective memoization (f = 0, Amdahl gain ceiling = 0.0%). Closed with `NO_CHANGE`.

## 7. Amdahl Deficit Waterfall & Subsequent Project Blueprint

Based on the A04 deficit partitioning and B02/B04 time attributions, the global 1.5× deficit is distributed across the following architectural categories:

1. **Combinator Dispatch & Control Flow Overhead (~55% of gate deficit):**
   - The default production gate runs under `ParserBackend.combinators`. Deep template nesting, indirect delegate/function pointer calls, and per-combinator state passing create fixed overhead per rule match.
   - **Recommendation for Future Project:** Lower the whole-grammar recognition engine to scalar control flow via `ParserBackend.direct` with exact finite-budget instrumentation.
2. **Repetition & Delimiter Scanning Loops (~28% of gate deficit):**
   - Character-level loops in `PEGGrammar` and `CSV` suffer from scalar byte-by-byte advances through combinators rather than vector or chunked scanners.
   - **Recommendation:** Expand scanner lowering to cover delimited repetition patterns (`sepBy`, `rep1`) directly without combinator boundaries.
3. **Compact Record Allocation & Materialization (~17% of gate deficit):**
   - Building flat `CompactNode` records in `spans` and `tree` modes incurs linear arena reservation, parent index rebasing, and span boundary tracking.
   - **Recommendation:** Implement single-pass output streaming into pre-sized arenas where token counts can be bounded statically.

## 8. Per-Unique-Case Breakdown (All 171 Unique Workload Cases)

Sorted from worst median ratio to best median ratio:

| Case Name | Output Mode | Suite | Median Ratio | 95% CI | Runs (r1, r2, r3) | Candidate Latency | Reference Latency | Deficit (ns) |
|---|---|---|---:|---:|---|---:|---:|---:|
| `PEGGrammar.Trailing` | `validation` | `handwritten-workloads` | **4.811×** | ±0.304 | [4.638×, 4.811×, 5.165×] | 181.7 ns | 36.6 ns | 126.8 ns |
| `PEGGrammar.Permissive` | `validation` | `handwritten-workloads` | **4.738×** | ±0.465 | [4.943×, 4.738×, 4.152×] | 160.7 ns | 35.8 ns | 106.9 ns |
| `CSV.MultiLine` | `tree` | `handwritten-workloads` | **4.584×** | ±0.053 | [4.584×, 4.606×, 4.517×] | 2538.0 ns | 559.1 ns | 1699.4 ns |
| `PEGGrammar.Truncated` | `validation` | `handwritten-workloads` | **4.473×** | ±0.238 | [4.124×, 4.502×, 4.473×] | 195.6 ns | 43.9 ns | 129.7 ns |
| `CSV.MultiLine` | `spans` | `handwritten-workloads` | **4.414×** | ±0.121 | [4.575×, 4.414×, 4.371×] | 2549.4 ns | 572.1 ns | 1691.3 ns |
| `PEGGrammar.ManyRules` | `validation` | `handwritten-workloads` | **4.330×** | ±0.057 | [4.330×, 4.273×, 4.373×] | 13951.7 ns | 3212.9 ns | 9132.3 ns |
| `CSV.Flat` | `spans` | `handwritten-workloads` | **4.217×** | ±0.047 | [4.160×, 4.242×, 4.217×] | 21525.7 ns | 5104.3 ns | 13869.2 ns |
| `PEGGrammar.ManyRules` | `spans` | `handwritten-workloads` | **4.186×** | ±0.025 | [4.150×, 4.186×, 4.190×] | 23602.5 ns | 5632.9 ns | 15153.1 ns |
| `CSV.Flat` | `tree` | `handwritten-workloads` | **4.175×** | ±0.014 | [4.175×, 4.191×, 4.166×] | 21185.0 ns | 5085.7 ns | 13556.5 ns |
| `PEGGrammar.Medium` | `spans` | `handwritten-workloads` | **3.810×** | ±0.025 | [3.834×, 3.810×, 3.790×] | 3879.0 ns | 1014.3 ns | 2357.6 ns |
| `PEGGrammar.Medium` | `validation` | `handwritten-workloads` | **3.807×** | ±0.035 | [3.789×, 3.807×, 3.849×] | 2432.9 ns | 633.4 ns | 1482.8 ns |
| `PEGGrammar.Small` | `validation` | `handwritten-workloads` | **3.731×** | ±0.231 | [3.449×, 3.731×, 3.845×] | 473.9 ns | 125.3 ns | 285.9 ns |
| `PEGGrammar.Deep` | `spans` | `handwritten-workloads` | **3.608×** | ±0.182 | [3.356×, 3.656×, 3.608×] | 10317.0 ns | 2885.1 ns | 5989.4 ns |
| `JSON.EscapeHeavy` | `validation` | `json-ambiguity` | **3.503×** | ±0.147 | [3.702×, 3.503×, 3.458×] | 3253.0 ns | 928.1 ns | 1860.8 ns |
| `CSV.MultilineQuoted` | `tree` | `handwritten-workloads` | **3.463×** | ±0.120 | [3.463×, 3.613×, 3.407×] | 272.2 ns | 79.9 ns | 152.3 ns |
| `JSON.EscapeHeavy` | `spans` | `json-ambiguity` | **3.415×** | ±0.011 | [3.415×, 3.424×, 3.405×] | 3334.1 ns | 979.2 ns | 1865.3 ns |
| `JSON.InvalidTruncated` | `tree` | `json-ambiguity` | **3.384×** | ±0.010 | [3.384×, 3.384×, 3.399×] | 4830.8 ns | 1422.5 ns | 2697.0 ns |
| `PEGGrammar.Permissive` | `spans` | `handwritten-workloads` | **3.381×** | ±0.176 | [3.411×, 3.381×, 3.129×] | 311.6 ns | 92.2 ns | 173.3 ns |
| `PEGGrammar.Small` | `spans` | `handwritten-workloads` | **3.375×** | ±0.076 | [3.322×, 3.455×, 3.375×] | 799.8 ns | 239.8 ns | 440.2 ns |
| `PEGGrammar.Trailing` | `spans` | `handwritten-workloads` | **3.353×** | ±0.141 | [3.353×, 3.315×, 3.547×] | 316.9 ns | 94.5 ns | 175.1 ns |
| `CSV.SingleLine` | `tree` | `handwritten-workloads` | **3.334×** | ±0.150 | [3.334×, 3.349×, 3.113×] | 310.9 ns | 94.2 ns | 169.5 ns |
| `CSV.MultilineQuoted` | `spans` | `handwritten-workloads` | **3.313×** | ±0.070 | [3.334×, 3.218×, 3.313×] | 268.6 ns | 82.3 ns | 145.1 ns |
| `JSON.EscapeHeavy` | `tree` | `json-ambiguity` | **3.296×** | ±0.028 | [3.278×, 3.328×, 3.296×] | 3235.6 ns | 987.0 ns | 1755.2 ns |
| `JSON.InvalidTruncated` | `spans` | `json-ambiguity` | **3.281×** | ±0.082 | [3.156×, 3.284×, 3.281×] | 4254.2 ns | 1301.2 ns | 2302.4 ns |
| `JSON.DeepNesting` | `spans` | `json-ambiguity` | **3.238×** | ±0.055 | [3.194×, 3.238×, 3.291×] | 4194.9 ns | 1297.9 ns | 2248.0 ns |
| `CSV.SingleLine` | `spans` | `handwritten-workloads` | **3.197×** | ±0.412 | [3.352×, 3.197×, 2.657×] | 309.6 ns | 97.7 ns | 163.1 ns |
| `PEGGrammar.Medium` | `tree` | `handwritten-workloads` | **3.067×** | ±0.029 | [3.067×, 3.109×, 3.063×] | 4432.0 ns | 1447.0 ns | 2261.5 ns |
| `JSON.DeepNesting` | `tree` | `json-ambiguity` | **3.021×** | ±0.024 | [3.021×, 2.985×, 3.022×] | 4971.6 ns | 1649.5 ns | 2497.4 ns |
| `PEGGrammar.ManyRules` | `tree` | `handwritten-workloads` | **3.019×** | ±0.012 | [3.023×, 3.019×, 3.002×] | 28968.6 ns | 9584.1 ns | 14592.4 ns |
| `PEGGrammar.Truncated` | `spans` | `handwritten-workloads` | **2.932×** | ±0.133 | [2.978×, 2.932×, 2.755×] | 356.3 ns | 121.7 ns | 173.7 ns |
| `PEGGrammar.Truncated` | `tree` | `handwritten-workloads` | **2.930×** | ±0.165 | [3.177×, 2.919×, 2.930×] | 394.8 ns | 134.5 ns | 193.1 ns |
| `Arithmetic.Truncated` | `validation` | `handwritten-workloads` | **2.920×** | ±0.150 | [2.881×, 2.920×, 3.128×] | 221.9 ns | 75.0 ns | 109.4 ns |
| `PEGGrammar.Deep` | `validation` | `handwritten-workloads` | **2.909×** | ±0.092 | [2.973×, 2.909×, 2.811×] | 5003.8 ns | 1718.1 ns | 2426.6 ns |
| `PEGGrammar.Small` | `tree` | `handwritten-workloads` | **2.896×** | ±0.167 | [2.896×, 2.912×, 2.649×] | 921.4 ns | 318.7 ns | 443.3 ns |
| `CSV.EmptyQuoted` | `tree` | `handwritten-workloads` | **2.854×** | ±0.237 | [2.854×, 2.672×, 3.090×] | 191.3 ns | 69.3 ns | 87.3 ns |
| `JSON.InvalidTrailing` | `spans` | `json-ambiguity` | **2.852×** | ±0.122 | [3.027×, 2.852×, 2.832×] | 113.9 ns | 40.2 ns | 53.6 ns |
| `CSV.EmptyQuoted` | `spans` | `handwritten-workloads` | **2.846×** | ±0.371 | [2.423×, 2.846×, 3.070×] | 181.4 ns | 64.5 ns | 84.6 ns |
| `PEGGrammar.Trailing` | `tree` | `handwritten-workloads` | **2.815×** | ±0.183 | [2.654×, 2.977×, 2.815×] | 329.4 ns | 117.0 ns | 153.9 ns |
| `PEGGrammar.Deep` | `tree` | `handwritten-workloads` | **2.811×** | ±0.141 | [2.811×, 3.005×, 2.773×] | 12517.9 ns | 4456.2 ns | 5833.6 ns |
| `Numbers.BinaryInvalid` | `spans` | `handwritten-workloads` | **2.685×** | ±0.084 | [2.697×, 2.563×, 2.685×] | 42.9 ns | 16.2 ns | 18.5 ns |
| `PEGGrammar.Permissive` | `tree` | `handwritten-workloads` | **2.682×** | ±0.236 | [2.682×, 3.009×, 2.622×] | 332.8 ns | 124.1 ns | 146.7 ns |
| `PEGGrammar.Empty` | `spans` | `handwritten-workloads` | **2.673×** | ±0.319 | [3.049×, 2.673×, 2.497×] | 76.9 ns | 28.8 ns | 33.8 ns |
| `JSON.InvalidTruncated` | `validation` | `json-ambiguity` | **2.671×** | ±0.057 | [2.720×, 2.620×, 2.671×] | 3064.3 ns | 1147.1 ns | 1343.7 ns |
| `Arithmetic.Deep` | `validation` | `handwritten-workloads` | **2.657×** | ±0.125 | [2.657×, 2.802×, 2.585×] | 3240.9 ns | 1207.8 ns | 1429.2 ns |
| `CSV.Truncated` | `tree` | `handwritten-workloads` | **2.653×** | ±0.153 | [2.804×, 2.533×, 2.653×] | 149.7 ns | 53.4 ns | 69.6 ns |
| `Numbers.ScientificEmpty` | `spans` | `handwritten-workloads` | **2.640×** | ±0.170 | [2.640×, 2.843×, 2.549×] | 43.5 ns | 17.0 ns | 17.9 ns |
| `JSON.DeepNesting` | `validation` | `json-ambiguity` | **2.637×** | ±0.032 | [2.647×, 2.637×, 2.594×] | 3048.2 ns | 1158.9 ns | 1309.8 ns |
| `Arithmetic.Medium` | `validation` | `handwritten-workloads` | **2.630×** | ±0.031 | [2.630×, 2.623×, 2.673×] | 725.4 ns | 276.6 ns | 310.6 ns |
| `Numbers.BinaryInvalid` | `tree` | `handwritten-workloads` | **2.616×** | ±0.078 | [2.616×, 2.674×, 2.537×] | 41.6 ns | 15.9 ns | 17.7 ns |
| `Arithmetic.Nested` | `spans` | `handwritten-workloads` | **2.602×** | ±0.031 | [2.649×, 2.602×, 2.602×] | 1765.0 ns | 667.9 ns | 763.2 ns |
| `Arithmetic.Unary` | `validation` | `handwritten-workloads` | **2.599×** | ±0.328 | [2.374×, 2.599×, 2.949×] | 168.7 ns | 63.6 ns | 73.2 ns |
| `Arithmetic.Empty` | `spans` | `handwritten-workloads` | **2.596×** | ±0.147 | [2.644×, 2.399×, 2.596×] | 76.7 ns | 29.5 ns | 32.4 ns |
| `PEGGrammar.Empty` | `validation` | `handwritten-workloads` | **2.595×** | ±0.053 | [2.532×, 2.623×, 2.595×] | 46.0 ns | 17.9 ns | 19.1 ns |
| `Arithmetic.Flat` | `validation` | `handwritten-workloads` | **2.583×** | ±0.073 | [2.483×, 2.604×, 2.583×] | 21498.2 ns | 8288.3 ns | 9065.7 ns |
| `Arithmetic.Nested` | `validation` | `handwritten-workloads` | **2.573×** | ±0.079 | [2.573×, 2.651×, 2.511×] | 1181.2 ns | 459.0 ns | 492.7 ns |
| `Numbers.ScientificTruncated` | `tree` | `handwritten-workloads` | **2.571×** | ±0.167 | [2.701×, 2.571×, 2.406×] | 41.1 ns | 16.4 ns | 16.6 ns |
| `Numbers.ScientificTruncated` | `spans` | `handwritten-workloads` | **2.558×** | ±0.153 | [2.521×, 2.558×, 2.771×] | 42.9 ns | 16.8 ns | 17.8 ns |
| `CSV.Truncated` | `spans` | `handwritten-workloads` | **2.533×** | ±0.233 | [2.533×, 2.182×, 2.544×] | 141.3 ns | 55.5 ns | 58.0 ns |
| `Arithmetic.Truncated` | `spans` | `handwritten-workloads` | **2.528×** | ±0.124 | [2.717×, 2.528×, 2.527×] | 347.9 ns | 136.6 ns | 143.1 ns |
| `Numbers.ScientificTrailing` | `spans` | `handwritten-workloads` | **2.515×** | ±0.152 | [2.570×, 2.515×, 2.314×] | 44.6 ns | 17.7 ns | 18.0 ns |
| `Numbers.ScientificEmpty` | `tree` | `handwritten-workloads` | **2.494×** | ±0.023 | [2.482×, 2.521×, 2.494×] | 45.8 ns | 18.4 ns | 18.1 ns |
| `Numbers.ScientificTrailing` | `tree` | `handwritten-workloads` | **2.481×** | ±0.286 | [2.131×, 2.622×, 2.481×] | 42.1 ns | 17.0 ns | 16.7 ns |
| `Arithmetic.Medium` | `spans` | `handwritten-workloads` | **2.460×** | ±0.065 | [2.539×, 2.460×, 2.427×] | 1076.1 ns | 433.1 ns | 426.5 ns |
| `Arithmetic.Deep` | `spans` | `handwritten-workloads` | **2.435×** | ±0.023 | [2.404×, 2.435×, 2.442×] | 5053.8 ns | 2078.7 ns | 1935.7 ns |
| `Numbers.HexaInvalid` | `tree` | `handwritten-workloads` | **2.421×** | ±0.060 | [2.421×, 2.498×, 2.396×] | 38.0 ns | 15.6 ns | 14.6 ns |
| `JSON.InvalidEscape` | `tree` | `json-ambiguity` | **2.415×** | ±0.062 | [2.415×, 2.325×, 2.423×] | 191.8 ns | 80.1 ns | 71.6 ns |
| `Arithmetic.Small` | `validation` | `handwritten-workloads` | **2.397×** | ±0.292 | [2.835×, 2.382×, 2.397×] | 259.3 ns | 101.1 ns | 107.6 ns |
| `CSV.Flat` | `validation` | `handwritten-workloads` | **2.384×** | ±0.047 | [2.435×, 2.353×, 2.384×] | 2047.7 ns | 862.5 ns | 754.0 ns |
| `Arithmetic.Flat` | `spans` | `handwritten-workloads` | **2.374×** | ±0.018 | [2.370×, 2.374×, 2.399×] | 33561.5 ns | 14082.7 ns | 12437.4 ns |
| `Numbers.HexaInvalid` | `spans` | `handwritten-workloads` | **2.364×** | ±0.159 | [2.364×, 2.548×, 2.273×] | 36.9 ns | 16.2 ns | 12.5 ns |
| `JSON.InvalidEscape` | `spans` | `json-ambiguity` | **2.339×** | ±0.393 | [1.748×, 2.339×, 2.360×] | 185.6 ns | 78.7 ns | 67.6 ns |
| `Arithmetic.Trailing` | `validation` | `handwritten-workloads` | **2.306×** | ±0.328 | [1.912×, 2.306×, 2.478×] | 114.7 ns | 49.8 ns | 40.1 ns |
| `Arithmetic.Truncated` | `tree` | `handwritten-workloads` | **2.292×** | ±0.122 | [2.292×, 2.444×, 2.235×] | 383.8 ns | 166.9 ns | 133.3 ns |
| `Arithmetic.Empty` | `validation` | `handwritten-workloads` | **2.284×** | ±0.064 | [2.284×, 2.337×, 2.224×] | 41.8 ns | 18.5 ns | 14.1 ns |
| `Arithmetic.Small` | `spans` | `handwritten-workloads` | **2.282×** | ±0.231 | [2.282×, 2.604×, 2.225×] | 403.8 ns | 174.3 ns | 142.4 ns |
| `CSV.Trailing` | `tree` | `handwritten-workloads` | **2.267×** | ±0.029 | [2.283×, 2.233×, 2.267×] | 105.8 ns | 46.7 ns | 35.8 ns |
| `JSON.Medium` | `spans` | `json-ambiguity` | **2.265×** | ±0.010 | [2.254×, 2.265×, 2.271×] | 2108.9 ns | 928.8 ns | 715.7 ns |
| `JSON.InvalidNumber` | `validation` | `json-ambiguity` | **2.247×** | ±0.143 | [2.053×, 2.291×, 2.247×] | 119.0 ns | 54.0 ns | 38.0 ns |
| `JSON.InvalidNumber` | `spans` | `json-ambiguity` | **2.243×** | ±0.398 | [2.745×, 2.069×, 2.243×] | 196.1 ns | 87.5 ns | 65.0 ns |
| `JSON.InvalidTrailing` | `tree` | `json-ambiguity` | **2.218×** | ±0.360 | [2.504×, 1.869×, 2.218×] | 155.9 ns | 69.1 ns | 52.3 ns |
| `Arithmetic.Unary` | `spans` | `handwritten-workloads` | **2.216×** | ±0.074 | [2.141×, 2.216×, 2.271×] | 261.5 ns | 118.0 ns | 84.5 ns |
| `JSON.Medium` | `tree` | `json-ambiguity` | **2.206×** | ±0.020 | [2.206×, 2.223×, 2.188×] | 2159.9 ns | 971.6 ns | 702.4 ns |
| `JSON.InvalidEscape` | `validation` | `json-ambiguity` | **2.189×** | ±0.179 | [1.925×, 2.209×, 2.189×] | 110.1 ns | 49.8 ns | 35.3 ns |
| `CSV.Trailing` | `spans` | `handwritten-workloads` | **2.184×** | ±0.065 | [2.184×, 2.110×, 2.222×] | 105.1 ns | 48.1 ns | 32.9 ns |
| `JSON.Small` | `spans` | `json-ambiguity` | **2.178×** | ±0.120 | [2.178×, 2.006×, 2.199×] | 486.1 ns | 221.0 ns | 154.5 ns |
| `JSON.InvalidNumber` | `tree` | `json-ambiguity` | **2.144×** | ±0.220 | [1.874×, 2.252×, 2.144×] | 198.1 ns | 92.5 ns | 59.4 ns |
| `CSV.InvalidSpacing` | `tree` | `handwritten-workloads` | **2.134×** | ±0.042 | [2.186×, 2.134×, 2.115×] | 101.1 ns | 47.1 ns | 30.5 ns |
| `Arithmetic.Deep` | `tree` | `handwritten-workloads` | **2.130×** | ±0.026 | [2.099×, 2.144×, 2.130×] | 6779.6 ns | 3216.2 ns | 1955.2 ns |
| `Arithmetic.Trailing` | `spans` | `handwritten-workloads` | **2.128×** | ±0.435 | [2.427×, 1.665×, 2.128×] | 213.8 ns | 100.5 ns | 63.1 ns |
| `Arithmetic.Trailing` | `tree` | `handwritten-workloads` | **2.095×** | ±0.125 | [2.134×, 2.095×, 1.926×] | 226.8 ns | 106.9 ns | 66.4 ns |
| `CSV.InvalidSpacing` | `spans` | `handwritten-workloads` | **2.079×** | ±0.234 | [2.079×, 2.426×, 2.058×] | 102.0 ns | 49.1 ns | 28.4 ns |
| `JSON.Small` | `tree` | `json-ambiguity` | **2.069×** | ±0.014 | [2.069×, 2.079×, 2.054×] | 481.0 ns | 232.5 ns | 132.2 ns |
| `CSV.EmptyQuoted` | `validation` | `handwritten-workloads` | **2.067×** | ±0.080 | [2.067×, 2.030×, 2.167×] | 38.8 ns | 18.4 ns | 11.2 ns |
| `JSON.Medium` | `validation` | `json-ambiguity` | **2.064×** | ±0.185 | [1.950×, 2.273×, 2.064×] | 1588.5 ns | 761.0 ns | 447.0 ns |
| `Arithmetic.Nested` | `tree` | `handwritten-workloads` | **2.053×** | ±0.042 | [2.114×, 2.047×, 2.053×] | 2330.7 ns | 1135.3 ns | 627.7 ns |
| `Arithmetic.Medium` | `tree` | `handwritten-workloads` | **2.051×** | ±0.031 | [2.083×, 2.051×, 2.029×] | 1377.2 ns | 675.7 ns | 363.7 ns |
| `Arithmetic.Unary` | `tree` | `handwritten-workloads` | **2.037×** | ±0.007 | [2.037×, 2.043×, 2.031×] | 325.6 ns | 159.8 ns | 85.8 ns |
| `Numbers.ScientificLong` | `validation` | `handwritten-workloads` | **2.011×** | ±0.006 | [2.008×, 2.011×, 2.019×] | 7634.5 ns | 3783.8 ns | 1958.8 ns |
| `JSON.InvalidTrailing` | `validation` | `json-ambiguity` | **1.999×** | ±0.200 | [1.839×, 1.999×, 2.192×] | 83.3 ns | 38.3 ns | 25.9 ns |
| `CSV.LongField` | `spans` | `handwritten-workloads` | **1.995×** | ±0.008 | [2.003×, 1.995×, 1.989×] | 3916.8 ns | 1968.1 ns | 964.7 ns |
| `Arithmetic.InvalidNumber` | `tree` | `handwritten-workloads` | **1.993×** | ±0.240 | [1.993×, 2.107×, 1.696×] | 157.1 ns | 82.8 ns | 32.9 ns |
| `Arithmetic.Small` | `tree` | `handwritten-workloads` | **1.989×** | ±0.259 | [2.068×, 1.638×, 1.989×] | 494.7 ns | 249.7 ns | 120.1 ns |
| `Numbers.HexaLong` | `tree` | `handwritten-workloads` | **1.986×** | ±0.009 | [1.986×, 1.973×, 1.988×] | 3868.7 ns | 1948.2 ns | 946.4 ns |
| `Numbers.HexaLong` | `spans` | `handwritten-workloads` | **1.983×** | ±0.009 | [1.983×, 1.970×, 1.984×] | 3892.3 ns | 1962.9 ns | 948.1 ns |
| `Arithmetic.InvalidNumber` | `validation` | `handwritten-workloads` | **1.954×** | ±0.143 | [1.954×, 2.156×, 1.922×] | 64.5 ns | 32.8 ns | 15.3 ns |
| `Numbers.ScientificEmpty` | `validation` | `handwritten-workloads` | **1.945×** | ±0.041 | [1.929×, 1.999×, 1.945×] | 32.1 ns | 16.5 ns | 7.4 ns |
| `Arithmetic.InvalidNumber` | `spans` | `handwritten-workloads` | **1.924×** | ±0.011 | [1.924×, 1.921×, 1.940×] | 136.8 ns | 70.5 ns | 31.0 ns |
| `JSON.Small` | `validation` | `json-ambiguity` | **1.919×** | ±0.150 | [1.759×, 1.919×, 2.021×] | 359.1 ns | 178.7 ns | 91.1 ns |
| `Numbers.ScientificTrailing` | `validation` | `handwritten-workloads` | **1.906×** | ±0.113 | [1.906×, 1.781×, 1.978×] | 33.0 ns | 17.3 ns | 7.0 ns |
| `CSV.Empty` | `tree` | `handwritten-workloads` | **1.897×** | ±0.034 | [1.910×, 1.852×, 1.897×] | 97.0 ns | 50.8 ns | 20.8 ns |
| `Numbers.BinaryInvalid` | `validation` | `handwritten-workloads` | **1.888×** | ±0.059 | [1.973×, 1.888×, 1.878×] | 29.9 ns | 15.9 ns | 6.0 ns |
| `Arithmetic.Flat` | `tree` | `handwritten-workloads` | **1.886×** | ±0.004 | [1.885×, 1.886×, 1.892×] | 41688.5 ns | 22111.3 ns | 8521.5 ns |
| `CSV.MultilineQuoted` | `validation` | `handwritten-workloads` | **1.846×** | ±0.197 | [1.893×, 1.846×, 1.570×] | 42.0 ns | 22.7 ns | 8.0 ns |
| `CSV.Empty` | `spans` | `handwritten-workloads` | **1.808×** | ±0.159 | [1.971×, 1.692×, 1.808×] | 90.0 ns | 49.8 ns | 15.4 ns |
| `Numbers.Scientific` | `spans` | `handwritten-workloads` | **1.807×** | ±0.029 | [1.779×, 1.807×, 1.830×] | 88.9 ns | 49.4 ns | 14.9 ns |
| `Numbers.Scientific` | `tree` | `handwritten-workloads` | **1.785×** | ±0.028 | [1.791×, 1.746×, 1.785×] | 88.3 ns | 50.5 ns | 12.6 ns |
| `Numbers.Binary` | `validation` | `handwritten-workloads` | **1.752×** | ±0.207 | [1.664×, 2.016×, 1.752×] | 33.1 ns | 18.3 ns | 5.6 ns |
| `Arithmetic.Empty` | `tree` | `handwritten-workloads` | **1.746×** | ±0.167 | [1.933×, 1.640×, 1.746×] | 121.5 ns | 66.4 ns | 22.0 ns |
| `CSV.LongQuoted` | `tree` | `handwritten-workloads` | **1.738×** | ±0.252 | [1.738×, 1.756×, 1.362×] | 3381.3 ns | 1960.8 ns | 440.1 ns |
| `CSV.LongQuoted` | `spans` | `handwritten-workloads` | **1.737×** | ±0.049 | [1.663×, 1.739×, 1.737×] | 3405.0 ns | 1959.8 ns | 465.2 ns |
| `CSV.LongField` | `tree` | `handwritten-workloads` | **1.736×** | ±0.008 | [1.736×, 1.738×, 1.724×] | 3364.8 ns | 1948.8 ns | 441.5 ns |
| `CSV.LongTruncated` | `tree` | `handwritten-workloads` | **1.734×** | ±0.003 | [1.738×, 1.734×, 1.734×] | 3367.5 ns | 1942.5 ns | 453.7 ns |
| `Numbers.ScientificLong` | `spans` | `handwritten-workloads` | **1.729×** | ±0.014 | [1.745×, 1.719×, 1.729×] | 6682.1 ns | 3858.6 ns | 894.3 ns |
| `Numbers.ScientificLong` | `tree` | `handwritten-workloads` | **1.728×** | ±0.007 | [1.722×, 1.735×, 1.728×] | 6607.7 ns | 3836.6 ns | 852.8 ns |
| `CSV.LongTruncated` | `spans` | `handwritten-workloads` | **1.728×** | ±0.125 | [1.733×, 1.728×, 1.539×] | 3408.6 ns | 1972.7 ns | 449.6 ns |
| `Numbers.HexaLong` | `validation` | `handwritten-workloads` | **1.727×** | ±0.009 | [1.718×, 1.734×, 1.727×] | 3299.3 ns | 1906.5 ns | 439.5 ns |
| `CSV.LongQuoted` | `validation` | `handwritten-workloads` | **1.721×** | ±0.042 | [1.721×, 1.725×, 1.659×] | 3302.9 ns | 1930.9 ns | 406.5 ns |
| `CSV.LongField` | `validation` | `handwritten-workloads` | **1.716×** | ±0.010 | [1.707×, 1.726×, 1.716×] | 3312.0 ns | 1934.3 ns | 410.7 ns |
| `CSV.LongTruncated` | `validation` | `handwritten-workloads` | **1.716×** | ±0.005 | [1.716×, 1.716×, 1.723×] | 3292.9 ns | 1915.7 ns | 419.3 ns |
| `Numbers.Binary` | `spans` | `handwritten-workloads` | **1.678×** | ±0.023 | [1.675×, 1.678×, 1.712×] | 81.4 ns | 48.2 ns | 9.1 ns |
| `PEGGrammar.Empty` | `tree` | `handwritten-workloads` | **1.664×** | ±0.082 | [1.565×, 1.664×, 1.707×] | 103.1 ns | 62.0 ns | 10.1 ns |
| `CSV.Truncated` | `validation` | `handwritten-workloads` | **1.608×** | ±0.132 | [1.454×, 1.684×, 1.608×] | 32.0 ns | 19.9 ns | 2.1 ns |
| `Numbers.HexaInvalid` | `validation` | `handwritten-workloads` | **1.590×** | ±0.102 | [1.590×, 1.527×, 1.705×] | 24.8 ns | 15.7 ns | 1.3 ns |
| `Numbers.Scientific` | `validation` | `handwritten-workloads` | **1.588×** | ±0.540 | [2.379×, 1.588×, 1.523×] | 36.4 ns | 22.1 ns | 3.3 ns |
| `Numbers.Hexa` | `validation` | `handwritten-workloads` | **1.584×** | ±0.098 | [1.583×, 1.584×, 1.733×] | 31.7 ns | 20.0 ns | 1.7 ns |
| `Numbers.ScientificTruncated` | `validation` | `handwritten-workloads` | **1.568×** | ±0.169 | [1.549×, 1.817×, 1.568×] | 27.7 ns | 17.7 ns | 1.2 ns |
| `CSV.Trailing` | `validation` | `handwritten-workloads` | **1.566×** | ±0.059 | [1.597×, 1.566×, 1.496×] | 25.6 ns | 17.1 ns | 0.0 ns |
| `Numbers.Hexa` | `tree` | `handwritten-workloads` | **1.563×** | ±0.088 | [1.563×, 1.437×, 1.579×] | 81.7 ns | 52.6 ns | 2.7 ns |
| `CSV.SingleLine` | `validation` | `handwritten-workloads` | **1.552×** | ±0.133 | [1.552×, 1.755×, 1.551×] | 58.8 ns | 37.4 ns | 2.6 ns |
| `Numbers.Binary` | `tree` | `handwritten-workloads` | **1.552×** | ±0.230 | [1.734×, 1.328×, 1.552×] | 81.2 ns | 51.9 ns | 3.3 ns |
| `Ambiguous.Invalid` | `spans` | `json-ambiguity` | **1.522×** | ±0.121 | [1.625×, 1.411×, 1.522×] | 312.6 ns | 205.4 ns | 4.5 ns |
| `CSV.InvalidSpacing` | `validation` | `handwritten-workloads` | **1.506×** | ±0.040 | [1.506×, 1.489×, 1.556×] | 25.1 ns | 16.8 ns | 0.0 ns |
| `Numbers.Hexa` | `spans` | `handwritten-workloads` | **1.501×** | ±0.060 | [1.470×, 1.574×, 1.501×] | 80.7 ns | 52.8 ns | 1.5 ns |
| `CSV.Empty` | `validation` | `handwritten-workloads` | **1.499×** | ±0.027 | [1.499×, 1.506×, 1.462×] | 23.2 ns | 15.5 ns | 0.0 ns |
| `Ambiguous.Invalid` | `tree` | `json-ambiguity` | **1.382×** | ±0.063 | [1.423×, 1.382×, 1.312×] | 292.2 ns | 215.4 ns | 0.0 ns |
| `Ambiguous.Invalid` | `validation` | `json-ambiguity` | **1.369×** | ±0.030 | [1.409×, 1.369×, 1.359×] | 273.1 ns | 199.0 ns | 0.0 ns |
| `Ambiguous.First` | `spans` | `json-ambiguity` | **1.282×** | ±0.119 | [1.315×, 1.119×, 1.282×] | 225.8 ns | 176.1 ns | 0.0 ns |
| `CSV.MultiLine` | `validation` | `handwritten-workloads` | **1.232×** | ±0.017 | [1.232×, 1.252×, 1.223×] | 376.1 ns | 307.5 ns | 0.0 ns |
| `Ambiguous.First` | `tree` | `json-ambiguity` | **1.088×** | ±0.040 | [1.055×, 1.126×, 1.088×] | 192.3 ns | 176.7 ns | 0.0 ns |
| `JSON.LargeString` | `spans` | `json-ambiguity` | **1.027×** | ±0.015 | [1.036×, 1.010×, 1.027×] | 4026.9 ns | 3934.7 ns | 0.0 ns |
| `JSON.LargeString` | `tree` | `json-ambiguity` | **1.027×** | ±0.006 | [1.027×, 1.032×, 1.022×] | 4002.4 ns | 3888.7 ns | 0.0 ns |
| `JSON.WhitespaceHeavy` | `validation` | `json-ambiguity` | **1.022×** | ±0.006 | [1.022×, 1.027×, 1.016×] | 3015.1 ns | 2947.4 ns | 0.0 ns |
| `Numbers.BinaryLong` | `validation` | `handwritten-workloads` | **1.007×** | ±0.002 | [1.007×, 1.004×, 1.008×] | 3822.7 ns | 3808.5 ns | 0.0 ns |
| `Ambiguous.First` | `validation` | `json-ambiguity` | **1.003×** | ±0.021 | [1.010×, 0.975×, 1.003×] | 133.9 ns | 133.2 ns | 0.0 ns |
| `JSON.LargeString` | `validation` | `json-ambiguity` | **0.957×** | ±0.027 | [0.958×, 0.957×, 0.916×] | 3723.3 ns | 3892.6 ns | 0.0 ns |
| `JSON.WhitespaceHeavy` | `tree` | `json-ambiguity` | **0.911×** | ±0.005 | [0.911×, 0.912×, 0.904×] | 2700.1 ns | 2962.8 ns | 0.0 ns |
| `JSON.WhitespaceHeavy` | `spans` | `json-ambiguity` | **0.910×** | ±0.003 | [0.905×, 0.910×, 0.910×] | 2689.9 ns | 2963.2 ns | 0.0 ns |
| `Arithmetic.LongNumber` | `tree` | `handwritten-workloads` | **0.887×** | ±0.002 | [0.886×, 0.887×, 0.889×] | 3444.1 ns | 3880.4 ns | 0.0 ns |
| `Arithmetic.LongNumber` | `spans` | `handwritten-workloads` | **0.881×** | ±0.005 | [0.877×, 0.881×, 0.885×] | 3434.9 ns | 3897.8 ns | 0.0 ns |
| `Numbers.BinaryLong` | `tree` | `handwritten-workloads` | **0.876×** | ±0.003 | [0.878×, 0.874×, 0.876×] | 3363.0 ns | 3840.6 ns | 0.0 ns |
| `Ambiguous.Retry` | `spans` | `json-ambiguity` | **0.874×** | ±0.299 | [1.280×, 0.874×, 0.784×] | 213.5 ns | 244.3 ns | 0.0 ns |
| `Arithmetic.LongNumber` | `validation` | `handwritten-workloads` | **0.873×** | ±0.000 | [0.873×, 0.873×, 0.873×] | 3337.2 ns | 3821.0 ns | 0.0 ns |
| `Numbers.BinaryLong` | `spans` | `handwritten-workloads` | **0.873×** | ±0.001 | [0.873×, 0.873×, 0.875×] | 3368.7 ns | 3851.2 ns | 0.0 ns |
| `Ambiguous.Retry` | `tree` | `json-ambiguity` | **0.771×** | ±0.031 | [0.771×, 0.788×, 0.735×] | 191.0 ns | 251.3 ns | 0.0 ns |
| `PEGGrammar.LongTruncated` | `tree` | `handwritten-workloads` | **0.702×** | ±0.002 | [0.699×, 0.702×, 0.703×] | 4073.0 ns | 5796.4 ns | 0.0 ns |
| `PEGGrammar.LongLiteral` | `tree` | `handwritten-workloads` | **0.701×** | ±0.011 | [0.712×, 0.693×, 0.701×] | 4117.5 ns | 5871.6 ns | 0.0 ns |
| `Ambiguous.Retry` | `validation` | `json-ambiguity` | **0.669×** | ±0.045 | [0.672×, 0.669×, 0.601×] | 134.5 ns | 201.2 ns | 0.0 ns |
| `PEGGrammar.LongLiteral` | `spans` | `handwritten-workloads` | **0.619×** | ±0.002 | [0.617×, 0.620×, 0.619×] | 3568.4 ns | 5768.5 ns | 0.0 ns |
| `PEGGrammar.LongTruncated` | `spans` | `handwritten-workloads` | **0.609×** | ±0.003 | [0.612×, 0.607×, 0.609×] | 3514.6 ns | 5784.2 ns | 0.0 ns |
| `PEGGrammar.LongLiteral` | `validation` | `handwritten-workloads` | **0.597×** | ±0.003 | [0.597×, 0.595×, 0.600×] | 3417.4 ns | 5719.1 ns | 0.0 ns |
| `PEGGrammar.LongTruncated` | `validation` | `handwritten-workloads` | **0.592×** | ±0.000 | [0.592×, 0.592×, 0.593×] | 3384.2 ns | 5708.0 ns | 0.0 ns |

## 9. Toolchain, Compiler & Environment Manifest

- **Git Commit Revision:** `2328f449440bb2255852f392412218b2d95515f4`
- **Working Tree Status:** Clean (`worktreeDirty=False`)
- **Compiler:** `ldc2`
- **CPU:** `AMD Ryzen 7 PRO 5850U with Radeon Graphics`
- **Platform:** `Linux-7.2.8-2-cachyos-x86_64-with-glibc2.44`
- **Benchmark Runner Binary Size:** 5,102,128 bytes (Text segment: 3,146,449 bytes)
- **Build & Export Time:** 103.69 seconds
- **Iterations per Benchmark Case:** 2,000
- **Recorded Samples per Run:** 7
- **Target Performance Ratio:** 1.5× against handwritten reference
- **Raw Gate Data Artifact:** [`performance/phase3/E01-gate.json`](file:///home/alex-work/repos/triste/performance/phase3/E01-gate.json)
- **Summary Data Artifact:** [`performance/phase3/E01-summary.json`](file:///home/alex-work/repos/triste/performance/phase3/E01-summary.json)

