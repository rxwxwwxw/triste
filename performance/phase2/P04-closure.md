# P04 — Tiny-Gate Lane Closure & No-Change Report

## 1. Executive Summary & Lane Disposition

Milestone **P04** evaluates whether a viable single-subsystem optimization exists for the tiny-gate
workloads, or whether the tiny-gate optimization lane should be formally closed under the Phase 2 plan's
stop rule (*"If P03 cannot identify a robust fix, publish a blocked/no-change report and stop. Do not churn source to optimize benchmark noise"*).

**Disposition: The tiny-gate lane is formally closed with NO production parser source changes.**
The existing direct selective parser generation remains optimal, verified, and 100% compliant with
the acceptance gate suite.

---

## 2. Gate Verification & Acceptance Status

The complete 513-check performance gate matrix (171 paired checks across validation, spans, and tree
output obligations $\times$ 3 independent runs) was verified post-H07 in `performance/phase2/gate-h07.json`:

- **Total Paired Checks:** **513 / 513 checks passed**.
- **Failing Gates Count:** **0 failures**.
- **Target Threshold:** All checks satisfy $\le 5.0\times$ handwritten baselines.
- **Worst Surviving Case:** `PEGGrammar.Permissive` runs at a stable mean ratio of **4.80×** across all runs
  (4.805× in Run 1, 4.778× in Run 2, 4.816× in Run 3; $\sigma < 0.02\times$).

---

## 3. Structural Analysis: Why Source Churn is Prohibited

The detailed profiling in **P03** (`performance/phase2/P03-profile.md`) demonstrated why further
in-source micro-optimization of the tiny PEG grammar is unwarranted and counterproductive:

1. **Fixed Lifecycle Overhead Dominates the Gap:**
   - Handwritten baseline latency (`PegParser.parse(input)`): **33.5 ns**.
   - NPegged `Arena` and `State` initialization + teardown: **29.1 ns** (**86.9%** of the entire handwritten runtime).
   - Before NPegged executes a single instruction of grammar logic, fixed setup and teardown consume nearly the
     entire handwritten baseline budget.
2. **Parser Body Latency is Already Low:**
   - The actual parsing body of `PEGGrammar.Permissive` executes in **86.5 ns** (**2.58×** handwritten).
   - Combined with harness observation wrapping (~15 ns) and fixed lifecycle costs (~29 ns), the total parse latency
     reaches ~161 ns ($161 / 33.5 = 4.80\times$).
3. **Safety & Budget Accounting Cannot Be Bypassed:**
   - In NPegged, every rule entry safely bounds resource consumption:
     - `stepCount++` and bounds check against `state.stepLimit`.
     - `depth++` / `depth--` and bounds check against `state.depthLimit`.
     - Tracking of furthest failure position (`state.maxFailEnd`).
   - Across the 6 rule invocations in `Permissive`, this contract accounts for ~25–30 ns. Removing these checks
     would violate the `AGENTS.md` mandate for deterministic RAII, resource limits, and contract mirroring.
4. **No Hot Whitespace Bottleneck:**
   - Diagnostic trace analysis proved that `BenchPEG.Sp` is called only 4 times during `Permissive`.
   - 3 of the 4 calls match actual whitespace (after `:`, `<--`, and `/`).
   - Exactly **1 call** matches empty input.
   - Introducing an empty-whitespace guard would save at most ~7 ns on a single call, but would add speculative
     branching to the other 3 whitespace sites and degrade performance across broader workloads, as proved in H05.
5. **DFA Replay Bottlenecks are Eliminated:**
   - Milestone P02 regression tests confirmed that DFA scanner replays are strictly **0**.

---

## 4. Prior Negative Findings Confirmed

The following architectural proposals explored in Phase 1 remain firmly **closed**:
- **H04 (Local Memo Bypass):** Reverted due to ~2× scaling regressions when guards were bypassed.
- **H05 (Empty Sp Bitmask Guards):** Closed because LLVM/LDC already batches FIRST sets into bitmask checks.
- **H08 (Direct-Code Emitter Simplification):** Closed because LLVM `-O3` already performs register-allocated loop
  lowering and straight-line cursor jumps.

---

## 5. Formal Conclusion & Next Steps

Per the Phase 2 plan rules:
1. The tiny-gate lane (**P01–P04**) is complete:
   - **P01:** Reconciled historical ledger and proved 0 failures post-H07.
   - **P02:** Pinned DFA scanner fast-failure regression tests.
   - **P03:** Profiled latency breakdown, isolating harness setup and safety limits as the root of the 4.80× ratio.
   - **P04:** Formally closed the tiny-gate optimization lane without source churn.
2. The active development focus now moves directly to the **Pure-Islands Semantics Lane (P05–P08)**, starting with
   Milestone **P05** (reproducing and isolating `NPeggedPureIslands` budget-edge failures).
