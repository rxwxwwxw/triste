# A01 — Provenance and Activation Inventory Report

## 1. Executive Summary

Milestone **A01** establishes an audit of source provenance, build configurations, and optimization activation conditions across the NPegged repository, evaluating the current source revision (`f5b666241fbc38cf8ae43c1d1bea034533025599`) against historical Phase 1 and Phase 2 claims (post-H07, P07, P09, P11, P13, P15, and X01–X03).

### Key Findings
1. **Accidental Benchmark Inactivity Discovered in Historical Studies (P09, P11, P13):**
   - In [`benchmark/p09_crossover.d`](file:///home/alex-work/repos/triste/benchmark/p09_crossover.d), [`benchmark/p11_flat_bench.d`](file:///home/alex-work/repos/triste/benchmark/p11_flat_bench.d), and [`benchmark/p13_tuning.d`](file:///home/alex-work/repos/triste/benchmark/p13_tuning.d), the test harness created `ParseContext` instances without explicitly unsetting the finite execution limits (`stepLimit = 10_000_000`, `depthLimit = 1024`, `memoryLimit = 256 MiB`).
   - In [`src/npegged/peg.d:1949-1952`](file:///home/alex-work/repos/triste/src/npegged/peg.d#L1949-L1952), `records.enableSharedOutput` contains a strict guard:
     ```d
     if (context.sharedOutput && context.trace is null && context.stepLimit == size_t.max
             && context.depthLimit == size_t.max && context.memoryLimit == size_t.max
             && outputLimit == size_t.max)
         records.enableSharedOutput(sharedStore, result.arena);
     ```
   - Because finite limits were left at their default values, `enableSharedOutput` was **never invoked** in `p09_crossover.d` or `p11_flat_bench.d`. The historical claim of a 2.16× speedup at depth 64 in P09 actually reflected flat buffer execution or harness variance, while `P11`'s "zero overhead" was measured on an inactive shared store.
2. **Current Production Performance Gate Configuration:**
   - The production gate (`scripts/performance_gate.py`) runs 513 paired comparisons against handwritten D baselines across 3 output modes (`validation`, `spans`, `tree`).
   - All gate runs execute in **default production mode**:
     - `ParserBackend.combinators` (the `NPeggedDirect` backend flag is absent in `src/`).
     - Finite `ParseContext` budgets: `memoryLimit = 256 MiB`, `stepLimit = 10_000_000`, `depthLimit = 1024`.
     - `outputLimit = 256 MiB` (default for `parseRecords`).
     - `OwnInput = false` (borrowed immutable slices).
     - `context.trace = null`.
     - `context.sharedOutput = false` (`NPeggedSharedOutput` is inactive).
     - Pure islands guarded fallback (`NPeggedPureIslands` is inactive under finite limits).
3. **Current HEAD vs P15 Source Provenance:**
   - The historical P15 gate recorded in `P15-performance-gate.json` was run at revision `34f475c` (tagged at release `8d89343`).
   - The current branch HEAD is `f5b6662`, which contains 4 subsequent commits:
     - `a0361f5`: P16 documentation and mode recommendation tables.
     - `9ec8953`: X01 bounded literal-prefix discrimination in `analysis.d` and `grammar.d`.
     - `7ea6a8a`: X02 phrase cache prototype in `peg.d`.
     - `f5b6662`: X03 recursive ascent prototype in `peg.d`.

---

## 2. Historical Claims & Activation Matrix

Every historical claim is audited below and classified according to the taxonomy defined in `PERFORMANCE_PLAN_PHASE3.md`:

| Claim ID | Milestone / Source | Claimed Result | Required Config for Active Path | Actual Config in Benchmark | Status | Disposition & Root Cause |
|---|---|---|---|---|---|---|
| **CLAIM-H07-GATE** | post-H07 (`gate-h07.json`) | 513/513 $\le 5\times$, 97/513 $\le 1.5\times$, median 2.122× | Production default limits | Production default limits | `different revision` | Recorded at `4726c4e`; valid historical baseline. |
| **CLAIM-P15-GATE** | P15 (`P15-performance-gate.json`) | 512/513 $\le 5\times$, 84/513 $\le 1.5\times$, median 2.132× | Production default limits | Production default limits | `different revision` | Recorded at `34f475c`; 1 outlier was `PEGGrammar.Trailing` (validation run 3 at 5.075×). |
| **CLAIM-H07-DFA** | H07 | DFA token scanner fast-fail on Check 1 and Check 2 without inner records | `Check == 1 \|\| (Check == 2 && !HasInnerRecords)` | Verified in unit & gate tests | `matched` | Present in [`src/npegged/dfa.d:623-633`](file:///home/alex-work/repos/triste/src/npegged/dfa.d#L623-L633). |
| **CLAIM-P07-PURE** | P07 | 0.97–1.00× on pure islands in unbounded mode; safe finite fallback | `pureIslandsEnabled` + all limits `size_t.max` + `trace is null` | Unbounded in diagnostic; finite in fallback | `matched` | Guard logic present in `peg.d:352-367`. Inactive under production defaults. |
| **CLAIM-P09-CROSS** | P09 (`p09_crossover.d`) | DenseChain depth 64 achieved 2.16× speedup with shared output | `sharedOutput = true` + `stepLimit == size_t.max` + `depthLimit == size_t.max` + `memoryLimit == size_t.max` + `outputLimit == size_t.max` | `outputLimit = size_t.max`, but finite `stepLimit`, `depthLimit`, `memoryLimit` | **`inactive`** | **Bug in benchmark harness:** default finite limits prevented `enableSharedOutput` from executing. |
| **CLAIM-P11-FLAT** | P11 (`p11_flat_bench.d`) | Zero overhead on JSON/CSV with flat specialization flag | `NPeggedFlatSpecialization` on an active shared store | Finite limits; shared store inactive | **`inactive`** | Specialized path was not tested against an active shared store. |
| **CLAIM-P13-TUNE** | P13 (`p13_tuning.d`) | 4096-byte / 128-node snapshot threshold tuning | Unlimited limits + `outputLimit = size_t.max` | Finite limits + default `outputLimit = 256 MiB` | **`inactive`** | Shared store was inactive during measurement. |
| **CLAIM-R03-MEMO** | R03 | Narrow memo invalidation | Experimental re-execution rules | N/A | `inactive` | Rejected in Phase 1 due to soundness violations. |
| **CLAIM-H04-BYPASS** | H04 | Local memo bypass for single-use rules | Bypass check | N/A | `inactive` | Rejected in Phase 1 due to backtracking blowup. |
| **CLAIM-R06-SHARED** | R06 | Shared output records for left-recursive replay | Unlimited budgets + `version(NPeggedSharedOutput)` | Finite production budgets | `inactive` | Maintained as opt-in only. |
| **CLAIM-X01-PREFIX** | X01 | Bounded literal prefix discrimination | Analysis enabled at compile time | Present in HEAD (`9ec8953`) | `different revision` | Present in current branch; not in P15 release. |
| **CLAIM-X02-CACHE** | X02 | Ordinary-rule phrase cache | Prototype struct `PhraseCache` | Present in HEAD (`7ea6a8a`) | `different revision` | Struct in `peg.d`, not wired into grammar compiler. |
| **CLAIM-X03-ASCENT** | X03 | Recursive ascent for action-free direct left recursion | Prototype `directLeftAscent` | Present in HEAD (`f5b6662`) | `different revision` | Template in `peg.d`, not wired into grammar compiler. |

---

## 3. Toolchain & Environment Metadata

- **Working Directory:** `/home/alex-work/repos/triste`
- **Current Git HEAD:** `f5b666241fbc38cf8ae43c1d1bea034533025599`
- **Compiler Versions:**
  - LDC2: `1.43.0` (based on DMD v2.113.0 and LLVM 22.1.8, host CPU: znver3 / AMD Ryzen 7 PRO 5850U)
  - DMD: `2.113.0`
- **Operating System:** Linux x86_64, glibc 2.39
- **Machine-readable Manifest:** [`performance/phase3/A01-manifest.json`](file:///home/alex-work/repos/triste/performance/phase3/A01-manifest.json)
