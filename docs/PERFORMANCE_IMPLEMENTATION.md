# Performance Implementation Record

This document records the empirical implementation history, compiler verification, and benchmark measurements for NPegged performance optimizations.

---

## 1. Milestone 1: Slab Allocation Subsystem (Completed)

* **Files:** `src/npegged/storage.d`, callers in `src/npegged/peg.d`.
* **Changes:**
  - Implemented 4 KiB slab allocation cursor in `Arena`.
  - Added dedicated blocks for oversized requests without displacing the current slab.
  - Enforced exact reserved-byte accounting and sticky resource-limit failures.
* **Results:**
  - Allocation calls dropped by 95%–98% on medium-to-large inputs.
  - Memory leak clean under Valgrind Memcheck and AddressSanitizer.

---

## 2. Milestone 2: Recognition Mode & Scalar Repetition Scanners (Completed)

* **Files:** `src/npegged/peg.d`, `src/npegged/grammar.d`.
* **Changes:**
  - Introduced `RecognitionNode` (32 bytes) and `State!(CT, Check)` specialization.
  - Implemented `check!(Parser.opCall)` for synchronous borrowed input validation with zero match/child AST allocations.
  - Implemented `repeat.scan` for tight byte-loop scanning of `charClass` and ASCII `charRange`.
  - Added single-slice input borrowing for fused repetition captures.
* **Results:**
  - Whitespace-heavy JSON scanning reached 177 MB/s (105x faster than Pegged).
  - Ambiguity and JSON validation achieved **1.8x – 4.7x handwritten speed** (passing the $\le 5\times$ target).

---

## 3. Milestone 3: Grammar Graph Analysis & Selective Memoization (Completed)

* **Files:** `src/npegged/analysis.d`, `src/npegged/grammar.d`.
* **Changes:**
  - Implemented `GrammarAnalysis`: computes nullability and 256-bit FIRST byte sets (`CharSetMask`) as fixed points over expression graphs.
  - Integrated Tarjan's Strongly Connected Components (SCC) algorithm to detect left-recursive rule cycles.
  - Added `Memoization.selective`: non-left-recursive, non-conservative rules bypass memo tables.
  - Automated `predictiveChoice` jump-table generation for disjoint alternatives.
  - Regenerated bootstrap parser `src/npegged/parser.d`.
* **Results:**
  - 100% `@nogc nothrow` CTFE analysis.
  - All `src/` modules maintained $>90\%$ branch and line coverage (e.g., `analysis.d` 98.96%, `grammar.d` 92.01%).

---

## 4. Milestone 4: Compact Records Subsystem (Completed in `records.d`)

* **Files:** `src/npegged/records.d`, `src/npegged/peg.d`.
* **Changes:**
  - Implemented `CompactNode` (24 bytes: `kind`, `begin`, `end`, `parent`) and `RecordBuffer`.
  - Implemented transactional output checkpoints and rollback on speculative choices.
  - Avoided quadratic match string copying and generic tree projection.
* **Results:**
  - JSON tree and spans modes achieved **2.2x – 4.9x handwritten speed** (passing the $\le 5\times$ target).

---

## 5. Current Baseline Summary & Remaining Work

### 5.1. Performance Status Matrix

| Grammar / Suite | Mode | NPegged Mean | Handwritten Mean | Ratio | Status ($\le 5\times$) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **JSON (Small, Medium, Large)** | Validation | 0.048 ms – 0.743 ms | 0.013 ms – 0.267 ms | **2.2x – 4.7x** | **PASS** |
| **JSON (All cases)** | Spans | 0.007 ms – 0.671 ms | 0.004 ms – 0.209 ms | **1.8x – 4.9x** | **PASS** |
| **JSON (All cases)** | Compact Tree | 0.012 ms – 0.743 ms | 0.004 ms – 0.267 ms | **2.2x – 4.7x** | **PASS** |
| **Ambiguity (First, Retry, Invalid)** | All modes | 0.017 ms – 0.033 ms | 0.007 ms – 0.012 ms | **2.4x – 3.7x** | **PASS** |
| **Arithmetic (Workload)** | Validation | 0.024 ms – 0.125 ms | 0.006 ms – 0.021 ms | **4.0x – 6.0x** | Near Threshold |
| **CSV (Workload)** | Validation | 0.032 ms – 0.350 ms | 0.005 ms – 0.052 ms | **5.0x – 9.7x** | Requires Left-Factoring & DFA |
| **Numbers (Scientific)** | Validation | 0.018 ms | 0.003 ms | **5.7x** | Requires Left-Factoring & DFA |
| **PEG Meta-Grammar** | Validation | 0.180 ms – 1.150 ms | 0.018 ms – 0.097 ms | **9.5x – 12.1x** | Requires Regular Token DFA |
| **Legacy Generic AST** | Full Tree | 3.5 ms – 341 ms | 0.005 ms – 0.577 ms | **200x – 1,164x** | Requires Universal Compact AST |

### 5.2. Next Optimization Milestones
1. **Left-Factoring Engine:** Transform shared-prefix choices in CSV, Numbers, and Arithmetic into factored choices with predictive choice jump tables.
2. **CTFE DFA Compiler:** Compile regular token rules (numbers, identifiers, whitespace, comments, strings) into 1-cycle-per-byte transition state machines.
3. **Universal Compact AST:** Retire quadratic match slice duplication across all grammar generation paths.
4. **SIMD Acceleration:** Vectorize delimiter search for bulk data.
