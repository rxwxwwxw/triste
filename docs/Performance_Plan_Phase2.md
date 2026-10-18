# NPegged performance — Phase 2 plan after F01–F05, R01–R07, H01–H08

**Goal:** ship the measured wins, achieve the tightened <=1.5x performance target relative to handwritten D baselines (now that the 5.0x milestone is complete across all 513 gates), safely exploit the action-grammar pure-island fast path, and determine whether recursive output can become fast *without* penalizing flat grammars. The default reference parser remains available. Each milestone is one small, independently reviewable agent task, with tests and a written go/no-go decision.

## 1. Conclusions that the new plan must respect

| Observed evidence | Interpretation | Consequence |
|---|---|---|
| F01: 380/387 paired gates pass; 7 ratio failures. F05: 4 tiny nonrecursive PEG failures specifically diagnosed. | Different gate populations may have been counted; small denominators make ratios noisy. | Enumerate all seven failures from actual reports and reconcile the four subset; do not assume they are the same seven or that all remain failures now. |
| F02 semantic oracle compares status/end/exact failEnd/records/memory. | A usable correctness contract exists. | Extend it for new modes; don't replace it. |
| F04/R04: left-recursive **record snapshot copying** is quadratic; R01: recognition scales linearly through 8,192 terms. | Output, not recognition invalidation, is the important proven asymptotic bottleneck. | Focus scaling work on record representation and materialization, not memo invalidation. |
| R03 dependency-invalidation experiment: 11–12× sibling-visit regressions. | A tempting narrowing strategy was actively harmful. | **Closed/rejected** until a materially new algorithm plus independent proof/profile exists. No silent reintroduction. |
| R05: 65 KB frozen at depth 2,048 vs 67 MB flat-copy baseline. R06: 0.388–0.436× deep-recursion runtime; 5–25% flat JSON/CSV overhead. | Persistent output is effective but not universally cheap. | Keep `NPeggedSharedOutput` explicit opt-in; test specialization before considering automatic selection. |
| H03 `NPeggedPureIslands`: pure entries 0.0024–0.0028× time, but budget-edge controls block promotion. | Potentially exceptional, but must isolate exactly *which* modes/semantics are comparable. | Address bounded-work semantics and fallback selection before changing any default. |
| H04 local memo bypass: ~2× regressions when guards are off. | Fewer memo calls do not imply better runtime. | **Closed/rejected.** |
| H05/H08 LDC2/LLVM `-O3` already combines whitespace guards and cursor dispatch. | Source simplification offers no demonstrated executable improvement. | **Closed.** No speculative rewrite of direct emitter. |
| H06/H07: 2,220 of 2,224 replays were diagnostic failed scans; H07 eliminated all 2,220, leaving four. JSON examples 0.874× and ~0.949×. | High-confidence source-level improvement already promoted. | Add permanent regression checks; don't restart broad DFA development to chase only four residual replays. |

**Prioritization:** (1) preserve H07 + settle remaining gate failures, (2) investigate H03 fast-path budget safety, (3) conditionally specialize R06 output for recursive workloads. A fourth lane of low-risk measurement can run alongside these, but **only one production parser change per agent commit**.

## 2. Global contract for each milestone

- Compare like-for-like: recognition vs recognition; selected compact records (same selector and ownership policy) vs identical selected records; full tree vs full tree.
- Differential oracle includes parse status, success, `end`, **exact** `failEnd`, record tuples `(kind, begin, end, parent)`, input ownership, action count/order, trace sequence, CTFE where supported, budget boundaries, resource failure stickiness, EOF/UTF-8/NUL, predicates, choice/backtracking, direct/indirect/nullable left recursion.
- Preserve guaranteed `@nogc nothrow` runtime behavior and arena ownership/lifetime. For shared fragments, explicitly verify stale pointers, cross-parse retention, parent rebasing, rollback, and bounded materialization. Do not silently change parse budgets to amortized/approximate accounting.
- Use uninstrumented optimized LDC release builds for timings; run counters separately. Save source hash, machine/compiler/flags, parse entrypoint, mode/version switches, input scale and output density, raw per-sample timings and medians. For tiny cases report absolute nanoseconds and confidence/repeatability alongside ratios.
- A production promotion requires: no semantic delta; no new timeouts, compiler, coverage or sanitizer failures; repeatable benefit on target workload; and **no material regressions** on flat and guarded-off controls. A 15–20% gain is a sensible gate for additional design complexity, not a license to degrade normal workloads.
- Any unsupported optimization case takes the existing reference path. Never quietly change API defaults during these experiments.

## 3. Immediate reliability + remaining gate lane (P01–P04)

### P01 — Reconcile results and freeze the Phase 1 ledger (very small; no parser changes)

**Depends:** none. **Files:** results/metadata and new performance ledger only.

**Work:** match each F/H/R outcome to actual report and source hash; label *promoted*, *opt-in*, *diagnostic*, *rejected*; reconcile F01's seven failed ratios with F05's four tiny nonrecursive cases and the final H07 source state. Identify which performance gates are failing **after** H07, and whether their ratio threshold is based on per-run or aggregate values.

**Deliverable:** `performance/phase2/phase1-ledger.md` and machine-readable gate-failure CSV/JSON with exact case, compiler, output obligation, reference/candidate times, and source revision.

**Done when:** no gate count ambiguity remains; reports from different revisions are never mixed. **Stop** if results directory is incomplete: record missing files rather than fabricating measurements.

### P02 — Turn H07 into a permanent replay/semantic regression (small)

**Depends:** P01. **Likely files:** `src/npegged/dfa.d`, existing DFA/scanner regression tests and benchmark scripts. Keep test additions separate from production changes.

**Work:** pin the representative failed-scan traces that drove `failureDiagnostic` replay in `Check == 2 && !HasInnerRecords`. Assert exact `failEnd`, success/failure, records, step/depth limits on EOF/truncated strings/failed escape sequences/backtracking, including a token with inner records that must fall back. Check replay counts with `NPeggedScannerMetrics`, then compare normal uninstrumented times.

**Done when:** the fast-failure condition and its fallback semantics are protected by targeted tests; the high-volume replay category does not return; code/runtime work in instrumentation-off builds is verified negligible. **Not a new optimization task.**

### P03 — Profile *only* the current unresolved tiny-gate cases (small)

**Depends:** P01/P02. **Files:** benchmark scripts and results, no runtime source changes.

**Work:** capture current failing cases and distribution across repetitions. For each, measure parser-only latency vs harness/allocation/setup overhead, direct vs reference backend, `Sp` empty probes, memo hits, and DFA replay counters. Inspect generated assembly only for the worst **surviving** case. Control CPU frequency, process noise, compiler flags and output obligation.

**Done when:** one concise table separates stable failures from near-threshold noise, with an attributable call/site and an estimated upper bound on benefit. Earlier `Sp`/guard source proposals remain closed unless new disassembly proves otherwise.

### P04 — Fix one proven tiny-gate bottleneck, *or close the lane* (small, conditional)

**Depends:** P03. **Files:** the single measured hotspot plus its tests. **Work:** choose precisely one non-rejected change from P03; write a failing microbenchmark/semantic regression first, implement a <=1-subsystem change, and rerun the complete performance gate. No generalized emitter rewrite, memo bypass, or duplicate whitespace guard.

**Done when:** the complete 387-gate matrix (as defined by P01) passes with required repeated-run acceptance and the target case improves reproducibly without notable new outliers. **If P03 cannot identify a robust fix, publish a blocked/no-change report and stop.** Do not churn source to optimize benchmark noise.

## 4. Pure-island semantics lane (P05–P08)

### P05 — Produce minimal reproducible `NPeggedPureIslands` budget failures (small, no optimization)

**Depends:** F02/H03; can run alongside P02/P03. **Likely files:** targeted tests and `eligibilityReport` fixtures; `src/npegged/grammar.d` only for diagnostic context.

**Work:** reduce every reported budget-edge mismatch to a tiny grammar and input. Sweep `stepLimit` around actual consumed work (0,1,2,…,N+2), `depthLimit` near call depth, `memoryLimit` around allocations, both recognition and selected records, action-grammar pure public entry and mixed pure→action/opaque calls, `trace` enabled/disabled. Compare exact status and `failEnd`, not only boolean parse success. Record generated call path, including guard-on/guard-off.

**Done when:** the failure has one known root cause and a deterministic regression fixture. Quantify which of `NPeggedPureIslands`' reported 0.0024–0.0028× gains remains after equal-output setup and guarded-off controls.

### P06 — Prototype **one** exact budget/accounting repair behind the existing opt-in (small/medium, conditional)

**Depends:** P05. **Likely files:** `src/npegged/grammar.d` or `src/npegged/peg.d` (one primary subsystem) and tests.

**Work:** select the smallest of (a) exact work-unit charge at an already-proved optimized primitive/loop, or (b) a conservative runtime guard that uses the reference path whenever an explicit budget, tracing, action, or unknown rule means equivalence is unproved. The optimized path must account for all work effects that are observably specified. Prefer guardable opt-in over a broad rewrite. Capture source-generated CSE/code size.

**Done when:** all P05 counterexamples pass; routine unbounded/default-path speed benefit persists; guard-off normal paths remain no worse than before. **Revert** if an exact work-unit model requires reconstructing generic PEG evaluation just to save calls.

### P07 — Re-evaluate fast-path eligibility and generated-code cost (small)

**Depends:** P06, or P05 if P06 is rejected. **Files:** report/tests/benchmarks first; optional one-line eligibility guard.

**Work:** compare per-rule `eligibilityReport` before/after for action-bearing grammars; benchmark a real mixed grammar and tiny pure-entry fixtures, including record/tree modes and tracing. Measure source/object size, LDC compile time and CTFE work. Confirm unknown and recursive rules are not erroneously classified pure.

**Done when:** evidence supports one of: leave opt-in; allow opt-in only with verified safe guards; or propose a distinct default-promotion PR with exhaustive gates. No deployment change in this task.

### P08 — Explicit promotion decision for pure islands (very small, decision task)

**Depends:** P07. **Files:** report/documentation, no core change unless the decision is implemented in a *separate* PR.

**Work:** decide based on exact semantics, normal-user workloads and compiler cost. State which parse modes, budget policies, trace/action configurations and entry shapes are eligible.

**Done when:** supported configurations and fallback behavior are documented; semantic or performance uncertainty keeps the feature opt-in rather than silently widening it.

## 5. Recursive-record output lane (P09–P14)

### P09 — Measure R06 break-even by **captured nodes**, not only input terms (small)

**Depends:** P01. **Files:** benchmark harness and one report; no parser changes.

**Work:** compare flat vs `NPeggedSharedOutput` on direct/indirect left recursion at depths 16–4096 (or resource-limited cutoff), selected record densities 0/1/few/many nodes per growth, mixed left-recursive/flat grammars, JSON/CSV, and success/late failure. Record median time, snapshots frozen/copied, committed output count, arena requested/retained/high-water bytes, fragment allocations, and time to materialize final output. Hold selector and ownership fixed. Plot **crossover depth and nodes per growth**.

**Done when:** a workload-shape table identifies when shared snapshots win, break even, and lose. A depth-only threshold is insufficient evidence for auto-selection.

### P10 — Feasibility analysis for compile-time output specialization (very small; no runtime change)

**Depends:** P09, H01/H02. **Likely files:** `src/npegged/analysis.d`, `src/npegged/grammar.d` diagnostics and test report.

**Work:** identify whether the existing left-recursion SCCs and record selector can prove a rule/entry needs persistent snapshots, or can prove a grammar is recursion-free. Document implications of opaque references, `treeFallback`, parameterized rules, nested reentry and suppressed records. Evaluate whether a **compile-time separate record-path instantiation** can avoid the 5–25% flat-workload penalty, instead of adding a branch to every `put`/`rollback`.

**Done when:** a classification table and small proposed code-change diagram exist, including explicitly conservative fallback for unknown cases. No rewrite of analysis.

### P11 — Prototype zero-overhead flat specialization under a *new experimental flag* (medium, conditional)

**Depends:** P10 with viable classification. **Likely files:** `src/npegged/records.d` and `src/npegged/peg.d` or generated specialization in `grammar.d`; tests. Implement only a **single** well-defined class first (e.g. proven nonrecursive grammar).

**Work:** keep original flat `RecordBuffer` path for provably flat entries and shared fragments for the known recursive target, without per-node dynamic checks on the flat path. Do not infer recursion from input length. Preserve generic fallback for unknown grammars. Keep feature opt-in and benchmark source/object/CTFE cost.

**Done when:** all differential cases pass; flat JSON/CSV overhead falls close to measurement noise and at least most of the depth-2048 0.388–0.436× benefit remains for the recursive target. **Revert** on complexity explosion, sustained flat regression, or unproven parent/rollback invariants.

### P12 — Audit fragment lifetime, parent rebasing, rollback, and resource limits (small)

**Depends:** P11 if attempted, otherwise validate existing R06. **Likely files:** `src/npegged/records.d`, `src/npegged/peg.d` tests.

**Work:** focused differential and resource-limit tests for repeated frozen seed, nested left recursion, many siblings, `suppressRecords`, truncation, failed restores, alternating selected/nonselected nodes, late failure, cross-parse owner destruction, oversized offsets/parent indices. Run ASan/Valgrind and verify stable committed record order. Compare requested vs retained bytes; fragment snapshots must not escape owners.

**Done when:** no parent corruption, dangling fragments, loss of sticky resource errors, diagnostic delta, or unbounded residual storage is found. Fix one flaw per commit if necessary.

### P13 — Optional one-localized output-fragment tuning experiment (small, conditional)

**Depends:** P09/P12. **Likely files:** one of `records.d` or `peg.d` plus tests.

**Work:** only if P09 shows an actual remaining hotspot, try one of fragment allocation batching, delayed flatten/materialization, or leaf-segment coalescing. Preserve identical `CompactNode` offsets and parent indices. Measure both deep recursion and flat output. No simultaneous storage layout overhaul.

**Done when:** repeatable benefit and semantic/resource parity; else revert and close. R03-style dependency invalidation is not within scope.

### P14 — Decide R06 policy using a 2×2 workload matrix (small; decision, not redesign)

**Depends:** P09–P12, P13 if needed. **Files:** reports/docs only unless a separate promotion PR is approved.

**Work:** compare `{flat shared-off, shared opt-in}` and `{nonrecursive input, recursive input}` for worst-case and typical workloads, with a separate mixed grammar case. Decide: (a) opt-in indefinitely, (b) compile-time per-entry path, or (c) explicitly documented high-performance parser variant. Automatic selection requires proven semantics and no measurable penalty to known flat grammars.

**Done when:** an implementation choice, trigger conditions, fast-path coverage and rollback policy are recorded. Do not promote purely because a synthetic 2048-term recursion test is 2.3–2.6× faster.

## 6. Closeout (P15–P16)

### P15 — Full release correctness, toolchain, and performance matrix (small as an agent *task*, substantial machine time)

**Depends:** all accepted code changes; does not require completing conditional experiments. **Files:** scripts/reports only.

**Work:** source-matched DMD/LDC/GDC tests (where installed), `@nogc nothrow`, CTFE, sanitizer/Valgrind, coverage, compiler/CTFE wall time, all 387 paired gates, all recursive scaling matrix cases, all action/trace/limits/memory/records cases. Clearly label `NPeggedSharedOutput` and `NPeggedPureIslands` as default/opt-in according to decisions. Store raw results and manifests; never compare mixed revisions.

**Done when:** final report separates functional pass/fail from performance pass/fail; unresolved cases have explicit owner and disposition.

### P16 — Publish default-versus-fast-mode recommendations (very small)

**Depends:** P15. **Files:** user-facing docs plus changelog.

**Work:** provide a concise decision table for reference/full tree, direct selective recognition, direct compact records, recursive records, action-bearing pure islands, and explicit budgets/tracing. Include where `NPeggedSharedOutput`, `NPeggedPureIslands`, and `NPeggedScannerMetrics` apply and how semantics/fallback are preserved; diagnostic metrics never presented as production timing. Give actual source-matched numbers, not historical maxima.

**Done when:** users can choose modes without guessing; default API remains backward-compatible unless a future separate compatibility decision is made.

## 7. Execution order for one or two local agents

**Single-agent critical path:** P01 → P02 → P03 → [P04 only if stable hotspot] → P05 → [P06] → P07 → P08 → P09 → P10 → [P11] → P12 → [P13] → P14 → P15 → P16.

**Two-agent plan after P01:**

- **Agent A: small gate + pure islands** — P02/P03, optional P04, then P05–P08.
- **Agent B: recursive records** — P09/P10, optional P11, P12–P14.
- Merge parser source changes *one at a time*. Rerun the differential oracle and representative guarded-off controls at each merge, then P15 globally.

**Closed work — don't regenerate tickets without new measurements:** R03 dependency invalidation, H04 guarded local memo bypass, H05 redundant `Sp` guard, H08 manual cursor-code simplification. Also don't create a broad scanner redesign to chase H06's four residual replays without a whole-parser cost case. Recognition recursion is not a current scaling blocker.

### Copy/paste agent task contract

> Work only on **P01** in `Performance_Plan_Phase2.md`, using the actual current checkout and its `results/` reports. Verify source hashes and toolchain first. The Phase 1 milestones F01–F05/R01–R07/H01–H08 are completed: do not repeat them or revert promoted H07 behavior. Make only changes allowed in P01; write the specified artifact; run relevant validation; state exact commands, results, and missing evidence. Do not proceed to a second milestone without review. Never promote an opt-in backend or alter PEG semantics as a side effect.

For later tasks, replace `P01` with the requested milestone ID. Each commit message starts with `perf(Pnn): ...`; each task report has **hypothesis**, **code/reports inspected**, **diff scope**, **tests**, **before/after source hashes**, **raw sample IDs**, **observed gain and regressions**, and an explicit **accept/keep-opt-in/revert/no-change** disposition.

## 8. Recommendation if engineering time is limited

Do **P01–P03** first: a clear, source-matched final gate state is more valuable than speculative micro-optimization. Next, prioritize **P05** because H03's budget limitations block an already demonstrated potentially very large improvement. Treat **P09–P10** as the next higher-impact investigation if recursive record users matter; **do not** pay 5–25% in normal JSON/CSV cases just to accelerate deep recursion globally. The already-promoted H07 should be protected and left alone unless a regression is measured.
