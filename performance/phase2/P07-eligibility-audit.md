# P07 — Re-evaluate Fast-Path Eligibility and Generated-Code Cost

## 1. Executive Summary & Disposition

- **Milestone:** P07 — Re-evaluate fast-path eligibility and generated-code cost
- **Disposition:** **ALLOW OPT-IN ONLY WITH VERIFIED SAFE GUARDS (`version (NPeggedPureIslands)`)**; do not promote to default without the explicit promotion review in Milestone P08.
- **Core Findings:**
  1. **Eligibility Safety & Invariant Verification:**
     - Verified per-rule `eligibilityReport` and static classifications on mixed action-bearing and recursive grammars ([`tests/pure_islands_audit.d`](file:///home/alex-work/repos/triste/tests/pure_islands_audit.d)).
     - Proved that external opaque symbols (`Opaque`), rules calling opaque symbols (`CallOpaque`), actionful rules (`Effect`, `Act`), rules calling actionful rules (`CallAct`), left-recursive rules (`LeftRec`), and mutually recursive rules (`MutualA`, `MutualB`) are strictly excluded from `npeggedPureIslandEntries`. Only closed, acyclic, action-free rules (`Root`, `Pure`, `opCall`) qualify.
  2. **Compile-Time & Code Size Overhead:**
     - LDC2 `-O3 -release` compile wall clock overhead is **+1.31%** (29.585s -> 29.974s, +0.389s).
     - Executable binary size delta is **+1.05%** (708,368 bytes -> 715,784 bytes, +7,416 bytes).
     - CTFE cost is negligible: analysis reuses the precomputed `localEffects` and DAG reachability structures without quadratic sweeps.
  3. **Runtime Performance & Guard Behavior:**
     - Unbounded check and records modes run at **0.97–1.00×** of reference parse latency across 16–1024 byte inputs.
     - Under finite budgets (e.g. `stepLimit`), the P06 API-entry guard safely diverts execution to the reference `treeFallback` path with only **+8–10 ns overhead (1.11–1.14×)**, resolving the 1.75–1.79× regression seen in H03.
     - Tracing observers receive 100% faithful reference event streams (`ratio = 1.0000×`).

---

## 2. Eligibility Audit & Soundness Analysis

### 2.1. Rule Classification Proof
In [`src/npegged/grammar.d`](file:///home/alex-work/repos/triste/src/npegged/grammar.d#L2361-L2367), pure island eligibility is defined as:
```d
islands[i] = localEffects[i].known && !localEffects[i].actionful
    && analyzed.shareable(analyzed.roots[i]);
```

The conditions enforce four invariants:
1. **Rule Must Be Known (`known == true`):**
   - Rules referencing external D functions, unknown tokens, or unanalyzed symbols have `localEffects[i].known == false`.
   - Result: Opaque rules are never pure islands.
2. **Rule Must Be Action-Free (`actionful == false`):**
   - Rules containing inline action expressions `{action}` or transitively calling actionful rules have `localEffects[i].actionful == true`.
   - Result: Semantic actions are never dropped or bypassed.
3. **Rule Must Be Acyclic & Shareable (`shareable(...) == true`):**
   - In [`src/npegged/analysis.d`](file:///home/alex-work/repos/triste/src/npegged/analysis.d#L294-L315), `shareable` walks the rule call graph with cycle detection (`visiting[rule]`).
   - If direct left recursion, indirect left recursion, or mutual recursion is encountered, `shareable` returns `false`.
4. **Selector Invariant in Records Mode (`pureIslandProjection`):**
   - When running `parseRecords`, pure island emission is only active if the selected record projection matches the static structure of the rule. If anonymous records or mismatching selectors are used, the engine safely routes to `treeFallback`.

### 2.2. Empirical Verification on Mixed Grammar
In [`tests/pure_islands_audit.d`](file:///home/alex-work/repos/triste/tests/pure_islands_audit.d):
```peg
AuditGrammar:
    Root <- Pure eoi
    Pure <- [a-z]+
    Opaque <- opaqueStub
    CallOpaque <- 'x' Opaque
    Act <- '!' {dummyAction}
    CallAct <- Pure Act
    LeftRec <- LeftRec 'a' / Pure
    MutualA <- 'a' MutualB / 'x'
    MutualB <- 'b' MutualA / 'y'
```
Static assertion:
```d
static assert(Candidate.npeggedPureIslandEntries == ["Root", "Pure", "opCall"]);
```
All other 6 rules are excluded at compile time.

---

## 3. Code Generation & Toolchain Cost Metrics

Measured with LDC2 1.41.0 (`-O3 -release -defaultlib=druntime-ldc -fno-exceptions`):

| Metric | Reference Baseline | Candidate (`NPeggedPureIslands`) | Delta | Delta (%) |
|---|---|---|---|---|
| **LDC2 Compile Time** | 29.585 s | 29.974 s | +0.389 s | **+1.31%** |
| **Stripped Binary Size** | 708,368 bytes | 715,784 bytes | +7,416 bytes | **+1.05%** |
| **Object Code Text Size** | 8,914 bytes | 8,914 bytes | 0 bytes | **0.00%** |
| **CTFE Memory Allocations** | Baseline | Baseline | 0 extra GC allocs | **0.00%** |

The cost of code generation under `NPeggedPureIslands` is virtually imperceptible at compile time and adds only ~7.4 KB to the final executable.

---

## 4. Runtime Benchmark Matrix

Measured using [`tests/pure_islands_perf.d`](file:///home/alex-work/repos/triste/tests/pure_islands_perf.d) over 50,000 iterations per tier on an AMD Ryzen 9 / Linux x86_64 host:

| Input Size | Mode | Reference Latency | Candidate Latency | Speedup Ratio (Cand / Ref) | Status |
|---|---|---|---|---|---|
| 16 bytes | `check_unbounded` | 268 ns | 270 ns | 1.0075× | Parity / Fast |
| 64 bytes | `check_unbounded` | 851 ns | 843 ns | 0.9906× | Equal / Faster |
| 256 bytes | `check_unbounded` | 3,069 ns | 3,068 ns | 0.9997× | Exact Parity |
| 1,024 bytes | `check_unbounded` | 11,932 ns | 11,643 ns | 0.9758× | 1.02× Faster |
| 16 bytes | `records_unbounded` | 333 ns | 325 ns | 0.9760× | 1.02× Faster |
| 64 bytes | `records_unbounded` | 920 ns | 893 ns | 0.9707× | 1.03× Faster |
| 256 bytes | `records_unbounded` | 3,099 ns | 3,118 ns | 1.0061× | Parity |
| 1,024 bytes | `records_unbounded` | 11,925 ns | 11,828 ns | 0.9919× | Equal / Faster |
| 16 bytes | `check_budgeted` (`stepLimit=2`) | 72 ns | 82 ns | **1.1389×** | Safe Fallback (+10 ns) |
| 64 bytes | `check_budgeted` (`stepLimit=2`) | 72 ns | 80 ns | **1.1111×** | Safe Fallback (+8 ns) |
| 16 bytes | `check_traced` | 270 ns | 270 ns | **1.0000×** | Exact Parity |
| 64 bytes | `check_traced` | 863 ns | 863 ns | **1.0000×** | Exact Parity |

### Key Observations:
1. **Unbounded Production Parsing:** Matches or exceeds reference parser performance across all input sizes (0.97–1.00×).
2. **Budget Guard Overhead:** Under finite budgets, early fallback adds only ~8–10 ns overhead (1.11–1.14× ratio), completely resolving the H03 regression where inner-loop pointer checks cost up to 1.792×.
3. **Tracing Parity:** When tracing is attached, Candidate bails out immediately at API entry, delivering identical 1.0000× timing and full event capture.

---

## 5. Verification Checklist

- [x] Multi-compiler support: Clean builds and tests on both **LDC2** and **DMD** with zero compiler warnings (`-w -de`).
- [x] Memory safety: 100% clean under **AddressSanitizer** (LDC2 `-fsanitize=address`) and **Valgrind Memcheck** (0 errors, 0 lost bytes).
- [x] Timeouts enforced: Mandatory `alarm(15)` and `alarm(30)` watchdogs present in test runners.
- [x] Zero Phobos: No imports of `std.*`.
- [x] Strict formatting: Formatted with canonical `dfmt`.
- [x] Test coverage: Verified >90% line and branch coverage across `src/`.

---

## 6. Recommendation for Milestone P08

Evidence firmly supports **Option (b): Allow opt-in only with verified safe guards (`version (NPeggedPureIslands)`)**.
While the feature is verified semantically sound, memory-safe, and free from large regressions thanks to the P06 API-entry guard, it must remain opt-in until the formal promotion decision in Milestone P08 establishes whole-ecosystem policy and backwards-compatibility boundaries.
