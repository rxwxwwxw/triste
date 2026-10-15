# NPegged Performance Review & Codebase Status

**Date:** 2026-10-15  
**Baseline Revision:** Current `src/` tree with Slab Allocator, Recognition Mode, Grammar Analysis, and Compact Records.  
**Objective:** Evaluate current performance bottlenecks across all output modes against handwritten parsers, identify why generic combinators remain ~1000x slower on legacy AST paths and 5x–12x slower on complex validation workloads, and establish the technical foundations for grammar factoring and DFA compilation.

---

## 1. Architectural Status of `src/`

The engine under `src/npegged/` has evolved from a naive Pegged port into a modular, multi-mode PEG framework. Below is a detailed assessment of each subsystem:

### 1.1. Storage Subsystem (`src/npegged/storage.d`)
* **Current Implementation:** `Arena` allocates objects using 4 KiB contiguous slabs with bump-pointer cursors for small allocations (`<= 4 KiB`), reserving dedicated blocks for oversized requests. It enforces strict deterministic RAII lifecycles (`@disable this(this);`) and tracks reserved bytes, requested payload bytes, and allocation calls.
* **Strengths:** Zero Phobos, `@nogc nothrow`, deterministic deallocation without runtime GC sweep pauses. System allocator calls dropped by over 95% on medium-to-large inputs.
* **Remaining Limitations:** While slab allocation minimizes `malloc` overhead, it does not prevent excessive internal payload allocation when deep generic AST nodes or redundant match slices are constructed.

### 1.2. Combinator & Execution Engine (`src/npegged/peg.d`)
* **Multi-Mode State (`State!(CT, Check)`):**
  - **Tree Mode (`Check == false`):** Constructs legacy `ParseTree` nodes (96 bytes per node) and dynamic `string[]` matches.
  - **Recognition Mode (`Check == true`):** Returns lightweight `RecognitionNode` (32 bytes: `begin`, `end`, `failEnd`, `successful`) via `check!(Parser.opCall)`. Completely suppresses match, child, and failure array allocations during valid parsing.
* **Terminal Fast Paths:**
  - `literal`: Slice equality comparison on string literals.
  - `charRange`: Single-byte comparison when `high < 128`.
  - `charClass`: 256-bit bitmask lookup (`ulong[4]`) via `CharSetMask` in 1–2 CPU cycles.
  - `predictiveChoice`: Static `ubyte[256]` branch jump table for disjoint alternative sets.
* **Scalar Repetition Scanning (`repeat.scan`):**
  - Tight byte loops for repetitions of `charClass` and ASCII `charRange`, capturing a single slice for fused transforms (`fuse!`, `~`).
* **Remaining Bottlenecks:**
  - **Combinator Call Stack Overhead:** Even in recognition mode, composite expressions (e.g. `(Add / Sub)*`, `(!'"' .)*`) still invoke nested template functions per character or iteration.
  - **Pervasive Tick Checking:** `s.tick()` is invoked up to twice per byte in loops to enforce `context.stepLimit`, adding conditional branch checks across every hot path even when `stepLimit == size_t.max`.
  - **Lack of Composite Scanner Specialization:** Repetitions of sequences (e.g., delimited strings or floating point numbers) cannot use `repeat.scan` and fall back to full generic combinator recursion.

### 1.3. Grammar Graph Analysis (`src/npegged/analysis.d`)
* **Current Implementation:** `GrammarAnalysis` builds a directed expression graph, solves nullability (`Nullable.yes`, `Nullable.no`, `Nullable.unknown`) and conservative 256-bit FIRST byte sets (`CharSetMask`) using fixed-point iteration, and identifies left-recursive rules using Tarjan's Strongly Connected Components (SCC) algorithm.
* **Strengths:** Fully `@nogc nothrow` CTFE/runtime solver; enables automated predictive choice dispatch and safe selective memoization.
* **Remaining Limitations:** Currently performs analysis at the symbol level only. Does not perform prefix factoring (left-factoring choices with shared prefixes) and does not detect regular sub-grammars for finite automaton conversion.

### 1.4. Grammar Frontend & Parser Generator (`src/npegged/grammar.d`)
* **Current Implementation:** Generates specialized D structs with static rule functions for all 4 compilation/execution permutations (`State!(false/true, false/true)`).
* **Optimization Passes:**
  - `Memoization.selective`: Non-left-recursive and non-conservative rules bypass memoization tables, saving hash table lookups and memory.
  - `predictiveChoice` generation: Automatically rewrites disjoint `or!(A, B)` into branch jump tables.
* **Remaining Limitations:**
  - Disjointness is evaluated strictly on top-level choice branches. If two branches share a common prefix (e.g. `Float <- Integer '.' Unsigned / Integer`), predictive choice is abandoned and falls back to naive ordered backtracking.
  - Generates combinator functions for every token instead of compiling lexical sub-grammars into unified scanners.

### 1.5. Compact Records (`src/npegged/records.d`)
* **Current Implementation:** `RecordBuffer` records preorder interval nodes (`CompactNode`: `kind`, `begin`, `end`, `parent` = 24 bytes) into a flat array in `Arena`, supporting transactional checkpoints and rollback on speculative choices.
* **Strengths:** Avoids recursive `ParseTree` allocation and quadratic match slice flattening. Reduces peak memory in tree/spans modes by over 90%.
* **Remaining Limitations:** Only wired into specialized benchmark comparisons; not yet the default AST format emitted by `npegged.grammar`.

---

## 2. Empirical Benchmark Findings & The ~1000x Gap

### 2.1. Measured Performance Spectrum

Our automated benchmark suite and performance gate reveal three distinct performance regimes:

| Regime | Workload / Mode | NPegged Speed vs Handwritten | Primary Bottleneck |
| :--- | :--- | :--- | :--- |
| **Optimized Recognition** | JSON & Ambiguity Validation (`check!`) | **1.8x – 4.7x slower** (PASSES $\le 5\times$) | Near parity; bounded by scalar loops and function prologue |
| **Optimized Compact Records** | JSON Tree & Spans (`RecordBuffer`) | **2.2x – 4.9x slower** (PASSES $\le 5\times$) | Flat array writes; minor overhead from speculative choice rollback |
| **Workload Validation** | Arithmetic, CSV, Numbers, PEG Validation | **5.0x – 12.6x slower** (FAILS $\le 5\times$) | Backtracking on shared prefixes, combinator function call overhead |
| **Legacy Generic AST** | Arithmetic, CSV, JSON Full `ParseTree` | **200x – 1,164x slower** (CATASTROPHIC) | 96-byte nodes, string slice copying, quadratic match concatenation |

### 2.2. Root Causes of the ~1000x Legacy AST Gap

Why is legacy `ParseTree` generation 1000x slower than handwritten parsing?
1. **Node Bloat:** `ParseTree` is 96 bytes per node (containing 4 slices, 3 offsets, a boolean, and an associative array pointer). In handwritten recursive descent, AST nodes are typically 16–24 bytes or omitted entirely during validation.
2. **Quadratic Match Duplication:** In Pegged and legacy NPegged, parent rules concatenate and duplicate their children's `matches` arrays. For an expression like `1 + 2 * (3 - 4)`, strings `"1"`, `"+"`, `"2"` are copied repeatedly into every ancestor node.
3. **Allocator Pressure:** Generating hundreds of temporary `string[]` and `ParseTree[]` slices creates millions of bytes of allocation traffic, overwhelming cache hierarchies even with slab allocators.

### 2.3. Root Causes of the 5x–12x Workload Gap

Why do even validation modes (`check!`) lag 5x–12x behind handwritten code in Arithmetic, CSV, and PEG meta-grammars?
1. **Linear Alternative Search:** In Arithmetic, parsing a primary operand tests `Parens`, fails, backtracks; tests `Neg`, fails, backtracks; tests `Number`, matches. The handwritten parser checks `current.type` in a single 1-cycle CPU switch!
2. **Shared Prefix Backtracking:** In CSV, field parsing tests `QuotedField`, backtracks on missing quote, then tests `UnquotedField`.
3. **Byte-at-a-Time Combinators:** In PEG meta-grammar, identifiers and character classes iterate through multiple template instantiations rather than scanning characters in a direct `while (isAlphaNum(c))` loop.
4. **Per-Byte Tick Accounting:** Continuous limit checks inside tight inner loops add instruction bloat and prevent loop vectorization.

---

## 3. Priority Decision & Strategic Direction

To reach the target of **$\le 5\times$ handwritten performance across all grammars and output obligations**, the engine cannot rely solely on micro-optimizing combinators. It must adopt compiler-grade grammar transformations:

1. **Automatic Grammar Factoring (Left-Factoring):** Automatically extract common prefixes in choices at compile time ($A B / A C \to A (B / C)$) to eliminate duplicate parsing and backtracking.
2. **Regular Sub-Grammar DFA Compilation:** Identify leaf token rules (numbers, identifiers, strings, whitespace, keywords) and compile them into deterministic finite automata (DFA) byte loops running at hardware memory bandwidth (1–3 GB/s).
3. **Batch Step Accounting:** Replace per-byte tick checks with batched block-level step accounting when `stepLimit == size_t.max`.
4. **SIMD Vectorization for Delimiters:** Vectorize string and column scanning using 128/256-bit SIMD intrinsics for quotes, escapes, and delimiters.
5. **Compact Records as the Universal Engine Output:** Retire quadratic match duplication; make `CompactNode` the standard AST representation across the entire framework.
