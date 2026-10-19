# X02 — Evaluation of Ordinary-Rule Phrase Caches (0/1/2/4/8 Entries)

## 1. Experiment Memo & Hypothesis

In packrat parsers, full memoization stores every rule evaluation in an unbounded hash table to support seed growth for left recursion and avoid redundant parsing. However, full memoization imposes high allocation overhead and cache misses on ordinary (non-left-recursive) rules.

Milestone X02 investigates decoupling ordinary-rule caching from mandatory left-recursion state via optional bounded phrase caches of capacity $C \in \{0, 1, 2, 4, 8\}$.

### Hypotheses Tested:
1. **Adversarial Shared Prefix:** Under $M$ choice branches sharing a prefix, an $N$-entry phrase cache ($N \ge 1$) eliminates $O(M \cdot L)$ rescans.
2. **Ping-Pong Thrashing:** Alternating backtracking across $K$ positions causes $N < K$ caches to thrash (0% hits with eviction overhead), while $N \ge K$ recovers full hit rates.
3. **Linear Scanning Overhead:** On linear, non-backtracking inputs, phrase cache lookups add a measurable tax with 0% hit rate.

## 2. Empirical Results

Evaluated with LDC2 (-O3) under `tests/test_phrase_cache.d`:

### 2.1. Adversarial Shared-Prefix Workload (16 Branches, 100-Byte Prefix)

| Capacity | Raw Rule Evaluations | Cache Hits | Rescan Avoidance |
|---|---|---|---|
| **0 entries** | 1,600 | 0 | 0.0% (Baseline rescans every branch) |
| **1 entry** | 100 | 1,500 | 93.75% (15x reduction in evaluations) |
| **2 entries** | 100 | 1,500 | 93.75% (15x reduction in evaluations) |
| **4 entries** | 100 | 1,500 | 93.75% (15x reduction in evaluations) |
| **8 entries** | 100 | 1,500 | 93.75% (15x reduction in evaluations) |

### 2.2. Ping-Pong Interleaved Backtracking Workload (Alternating 2 Positions)

| Capacity | Cache Hits | Evictions | Thrashing Behavior |
|---|---|---|---|
| **1 entry** | 0 | 399 | **100% Thrashing** (0% hit rate; each store evicts the other) |
| **2 entries** | 398 | 0 | **Optimal** (99.5% hit rate; zero evictions after warm-up) |
| **4 entries** | 398 | 0 | 99.5% hit rate; zero evictions after warm-up |
| **8 entries** | 398 | 0 | 99.5% hit rate; zero evictions after warm-up |

### 2.3. Linear Non-Backtracking Workload (Lookup Tax)

| Capacity | Total Overhead (ns / run) | Relative Overhead vs C=0 |
|---|---|---|
| **0 entries** | 0 ns | 1.0x (Zero overhead, no-op inlined) |
| **1 entry** | ~0 ns | ~1.0x (Direct single-slot compare) |
| **2 entries** | 2,900 ns | Small tag-check tax |
| **4 entries** | 4,300 ns | Noticeable linear scan tax |
| **8 entries** | 8,900 ns | Significant linear scan tax |

## 3. Analysis & Key Findings

1. **Catastrophic 1-Entry Thrashing:** A single-entry cache ($C=1$) provides huge benefits for simple ordered choices sharing a start position, but completely fails (0% hits, high eviction churn) under multi-position interleaved backtracking.
2. **Associative FIFO Sweet Spot ($C=2$):** A 2-entry associative FIFO cache completely resolves 2-position thrashing (398/400 hits, 0 evictions) while maintaining minimal storage and low lookup tax.
3. **Diminishing Returns for $C \ge 4$:** Capacities of 4 and 8 entries showed no hit-rate advantages over $C=2$ on typical 2-position local choices, while multiplying lookup latency by 1.5x to 3.0x on non-backtracking paths.

## 4. Policy Recommendation & Decision

- **Recommendation:** Keep phrase caches **opt-in and experimental** rather than deploying as the default for ordinary rules.
- **Rationale:** High-performance parsers achieve superior speedups by eliminating shared-prefix backtracking statically via compile-time prefix factoring (Milestone X01 and `optimizeRule`), avoiding runtime lookup taxes altogether.
- **Deployment Guideline:** If phrase caching is enabled for grammars with un-factorable dynamic backtracking, **$C=2$ is the recommended default capacity**, balancing thrashing avoidance against linear-path lookup penalties.
