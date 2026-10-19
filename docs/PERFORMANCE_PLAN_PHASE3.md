# NPegged performance: Phase 3 — measured path toward ≤1.5× handwritten parsers

## 0. Correct objective and evidence

The goal is **≤1.5× handwritten-reference time under equivalent parsing/output/ownership obligations**. The older ≤5× gate is a compatibility ceiling, not the success criterion.

| Historical dataset | ≤5× observations | ≤1.5× observations | Median ratio | Worst ratio |
|---|---:|---:|---:|---:|
| Post-H07 | 513 / 513 | 97 / 513 | 2.122× | 4.816× |
| P15 | 512 / 513 | 84 / 513 | 2.132× | 5.075× |

At P15, **429/513 measurements exceed 1.5×**. If all observations had equal weight and represented comparable work, reducing the typical 2.132× time ratio to 1.5× requires roughly **29.6% lower candidate latency** at an unchanged reference time. The worst 5.075× case requires approximately **70.4%** lower candidate latency. An isolated deep-recursion optimization cannot plausibly resolve such a broad gate deficit unless the gate population substantially overlaps that workload.

**Counting caveat:** 513 is the number of *saved checks/observations*, not necessarily 513 independent workload shapes. Group repetitions by case, mode, input and compiler; report both pass counts and unique-case counts. Apply exactly the pre-existing target contract, and do not relabel noisy failures as passes.

The reported 5× outlier in P15 is `PEGGrammar.Trailing`, validation, repetition 3. Do not reuse the incorrect `LongTruncated` label.

### Evidence confidence taxonomy

- **Confirmed in supplied source:** flags, entrypoint behavior, snapshot thresholds, fallback guards, backend selection, X02 and X03 prototype presence.
- **Reported historical measurements:** post-H07 and P15 ratios; R03/H04 rejections; H07 replay reduction; R06 active speedup; H03 pure-entry special-case speedup.
- **Unproven / require remeasurement:** P09/P13 shared-output crossover, P07 active pure-island benchmark, P11 “zero overhead,” X03 generality, and current-HEAD global gate score.

## 1. Source facts already checked

These are relative to the uploaded `npegged/` directory; actual repository paths may differ.

1. **Backend selection:** `grammar.d` defines `ParserBackend.combinators` / `ParserBackend.direct`. There is no `NPeggedDirect` version flag in the provided source. `ParserBackend.direct` lowers recognition control; other parse modes retain combinator paths unless separately optimized.
2. **Default limits:** `peg.d::ParseContext` initializes `stepLimit=10_000_000`, `depthLimit=1024`, and `memoryLimit=256 MiB`.
3. **Shared-output activation:** `peg.d::parseRecords` requires the `NPeggedSharedOutput` build version, generated `npeggedSharedOutputEligible`, `context.sharedOutput=true`, no tracing, unlimited step/depth/memory limits, and `outputLimit=size_t.max`. `grammar.d` additionally restricts eligible grammars. The default `parseRecords` output limit is **256 MiB**. Under the `NPeggedSharedOutput` version, `records.d::snapshot` uses shared snapshots only once the candidate snapshot has at least `4096 / CompactNode.sizeof` nodes; mere *mode activation* does not prove a snapshot was shared.
4. **Pure-island activation:** `NPeggedPureIslands` plus generated eligible entries/projection proof is required. The entry point requires no trace and unlimited limits, including the output arena for records. Default finite limits mean fallback.
5. **Ownership:** `parseRecords!(parser, selector, OwnInput=true)` defaults to **copying input** into an arena; `OwnInput=false` changes this. `check` is a recognition API, without that ownership copy. Benchmark like with like.
6. **H07 is present:** `dfa.d::dfaToken` fast-fails for `Check == 1` and `Check == 2 && !HasInnerRecords` under guarded conditions, before falling back to the original parser.
7. **X02/X03 are experimental:** `peg.d::PhraseCache` exists, but doesn't imply integration into grammar rules; `State::directLeftAscent` / `directAscent` exist without proof of general grammar lowering or equivalent arbitrary left-recursive parsing.
8. **P11 specialization is conditional:** both `NPeggedSharedOutput` and `NPeggedFlatSpecialization` branches are present. Do not call the latter zero-cost without source-matched builds and active-path measurements.

## 2. Universal contract for agent tasks

**One milestone = one narrow PR.** Each PR includes the exact commands used, source SHA, compiler/compiler flags, versions, grammar and entrypoint, input length, selected-output obligation, input ownership mode, default/explicit budgets, output limit, success/failEnd and record or tree parity, sample IDs, warmups, timing summary and disposition.

**Never compare:** recognition against tree construction; retained records against full trees; borrowed input against an owned copy without matching the reference; unlimited-budget optimization against a finite-budget reference without labeling the contract difference.

**Optimization activation is an assertion, not an assumption.** For a targeted active mode, fail the experiment if active-operation metrics are zero (for example, shared snapshot counters or pure-island entry counters). For fallback controls, assert the opposite. Record *both* mode selected and operations actually exercised; threshold effects may select a fast mode without generating shared snapshots.

**Correctness:** preserve exact status, `end`, `failEnd`, selected record tuple sequence and parent indices, input lifetime/ownership, action order, trace events, step/depth/memory limits, out-of-memory behavior, CTFE where supported, and `@nogc nothrow`. Differential oracle first, performance second. Limit-mode performance is separate from unbounded fast-path performance.

**Benchmark quality:** optimized uninstrumented LDC builds for performance; metrics in separate builds. For small inputs, report absolute latency, repetitions, variance/confidence and harness overhead in addition to ratios. Randomize/interleave comparator order, pin machine and compiler policy, and keep raw JSON in the repository. Distinguish timing regressions from correctness regressions and compiler/CTFE cost.

**Stop rules:** revert any correctness discrepancy; reject a change that benefits a niche workload but substantially regresses guarded-off or high-frequency normal cases; do not continue failed R03 or H04 variants without an independently justified new algorithm. A task with negative/noisy evidence can finish successfully with a written `NO_CHANGE` report.

## 3. Work program — small tasks in priority order

### A01 — Provenance and activation inventory (small, measurement only)

**Why:** current source and historical P15 datasets may not match; several studies accidentally benchmarked a disabled optimization.

**Files:** benchmark configuration, `performance/phase3/`, source metadata. Read `peg.d`, `grammar.d`, `records.d`, `dfa.d` without editing them.

**Do:** record source SHA and test build; enumerate every compile version, grammar/backend selection, `ParseContext` limit, records output limit, selector, input ownership, and trace setting used by each benchmark fixture. Publish a machine-readable config/activation matrix.

**Accept:** every historical claim has a source/config status of `matched`, `different revision`, `inactive`, or `unknown`; no fabricated current-HEAD numbers. **Exit:** `performance/phase3/A01-manifest.json` + concise report.

### A02 — Active-path smoke fixtures (small, tests only)

**Depends:** A01. **Files:** test harness and minimal new fixtures; no parser changes.

**Do:** create: (1) an eligible recursive-record grammar producing enough snapshots to pass the 4096-byte threshold, (2) a known ineligible/flat grammar, (3) a proven eligible pure entry in an action grammar, and (4) its guarded fallback with finite limits/tracing. Build with the correct flags, configure explicit unlimited limits for active tests, set `context.sharedOutput=true` and `outputLimit=size_t.max`, and collect counters in metrics builds.

**Accept:** assert shared mode enabled **and** shared snapshot/replay counters nonzero when appropriate; assert pure-island entries nonzero in the enabled case; assert each guarded fallback does *not* enter the fast path. Differential semantic parity passes. Do not make numerical speed claims here.

### A03 — Rebuild the current 1.5× gate (small/medium, measurement only)

**Depends:** A01; preferably A02. **Files:** gate runner and reports.

**Do:** rerun the full gate from one source revision, for the actual default production mode. Preserve raw repetitions, case identifiers, parse and output modes, input sizes, absolute candidate/reference timings and budgets. Compare with post-H07 and P15 *only as historical baselines*.

**Accept:** produce `A03-gate.json`, fail list and stable summary with both ≤5× and ≤1.5× counts, per-unique-case breakdown, median/p90/p95/worst, and confidence for noisy small cases. Exact source/toolchain manifest attached. Gate failure is a valid result; do not conceal it.

### A04 — Partition the 1.5× deficit (small, data-only)

**Depends:** A03. **Files:** analysis script, CSV/Markdown report.

**Do:** group by parser API/output mode, grammar family, success/failure/truncation, input size, selected record density, left recursion, direct/combinator lowering, and input ownership. Weight both by per-case counts and cumulative reference/candidate wall-clock cost. Show *which groups are responsible for the 429 historical failures on the new baseline*, not just the single worst ratio. Identify 5–10 representative and 3 guarded-control workloads.

**Accept:** top priority bottleneck groups have a measurable performance budget, and small/noisy cases are separated from scalable input-size effects. This task decides subsequent optimization order.

### B01 — Equal-work comparator audit (small, no parser changes)

**Depends:** A03/A04. **Files:** benchmark harness.

**Do:** verify that handwritten and generated parsers have the same acceptance rule, diagnostic obligations, selected nodes/tree obligation, input-ownership behavior, allocations excluded/included, and treatment of invalid/trailing input. Where APIs inherently differ, publish separate matched measurements; do not quietly change the official baseline.

**Accept:** every representative case has explicit comparable-contract evidence; incomparable pairs are reported, not counted as an optimization win. Include `OwnInput=true/false` where relevant.

### B02 — Two-dimensional time attribution (small, measurements only)

**Depends:** A04/B01. **Files:** instrumentation/benchmarks, no core edits unless needed to expose a safe counter.

**Do:** for representative workloads separate fixed invocation/setup costs from per-byte and per-output-node costs. Measure parse recognition vs selected records vs full tree *as separate obligations*, and instrument DFA attempts, memo hits, output allocations/copies, diagnostic paths, and parser-only vs end-to-end latency. Fit a descriptive model `T ≈ Tfixed + a·inputBytes + b·nodes + c·failedProbes`; do not present this model as proof of causal attribution.

**Accept:** each proposed optimization names a concrete expensive site and predicts an attainable gate-wide improvement; use Amdahl bounds to deprioritize low-ceiling work.

### B03 — One **high-coverage** measured optimization (conditional, small code patch)

**Depends:** B02. **Files:** precisely one primary source module + tests.

**Choose:** the highest-volume *previously untested* attributable cost across representative cases. Possibilities to test, **not presumed fixes**, include input copy/setup when obligations match, output growth or materialization, fallback dispatch, unnecessary memoization in a provably safe family, or failed-parse diagnostic work. Exclude rejected H04 memo-bypass and H05/H08 rewriters as-is.

**Accept:** exact oracle parity; repeatable improvement in a substantial fraction of the 1.5× failures; no statistically clear regressions in guarded-off controls; both representative and complete gate results. Otherwise revert. One hypothesis/PR only.

### B04 — Second independent gate-wide experiment (conditional)

**Depends:** A04/B02 and B03 decision. **Do:** target the next distinct demonstrated bottleneck, not another variant of a rejected optimization. Add before/after source-matched measurements and an explicit Amdahl/gate-coverage forecast.

**Accept:** same gates as B03; if improvement cannot plausibly move the global 1.5× distribution, close with `NO_CHANGE` and stop.

### C01 — Reproduce the **active** shared-output crossover (small, benchmark fix only)

**Depends:** A02. **Files:** repaired P09/P13 harness and raw results.

**Do:** run flat vs shared with explicit unlimited budgets and output limit, active `context.sharedOutput`, eligible grammar, metrics proof, and matched outputs. Sweep depths and selected-node densities; include success, late failure, sibling cases, and flat controls. Separate snapshot copying from replay/flattening. Run an *additional finite-budget fallback* control matrix, clearly labeled inactive.

**Accept:** publish measured activation counts and crossover curves. Recalculate P09/P13 conclusions; don't reuse the inactive 2.16× crossover claim. A result showing no broadly applicable gain is a successful measurement.

### C02 — Investigate bounded-output correctness *before* changing activation (small, design/test task)

**Depends:** C01. **Files:** records and arena semantics tests; report, not production optimization.

**Do:** enumerate cases where shared fragments' allocation/step/depth behavior differs from flat materialization. Define whether exact budget parity is possible, including ordinary default limits. Test under limits just below/above allocation and step thresholds. Analyze output-size-dependent branch selection versus rule-local/static selection.

**Accept:** documented proof obligations and go/no-go. **Never change defaults, treat limits as unbounded, or bypass arena accounting just to obtain speedup.**

### C03 — Shared-output optimization only if gate-relevant (conditional, one subsystem)

**Depends:** C01/C02 and A04. **Do:** if shared output is active and affects a meaningful number of 1.5× failures, address one remaining measured cost (e.g. replay materialization), with bounded semantics resolved or preserve opt-in-only mode. If deep recursion is scarcely represented in the gate, defer this task regardless of the attractive 2.3–2.6× niche result.

**Accept:** matched records, budgets, memory and parent indices; active speedup; no flat-path regression. Otherwise keep R06 opt-in.

### D01 — Reproduce **active** pure-island gain and fallback penalty (small, benchmarks only)

**Depends:** A02. **Do:** repair P07 to use actual unlimited budgets, verify nonzero `pureIslandEntries`, and compare with finite-budget/tracing fallback controls (whose fast-path entries should be zero). Include realistic mixed action grammars, output obligations and compiler/CTFE cost. Do *not* promote on the historically favorable 0.0024–0.0028× case alone.

**Accept:** source-matched active vs inactive times, selection counts, and full parity; a quantified fraction of ordinary callers eligible under default policies.

### D02 — Pure-island deployment decision (small, decision only)

**Depends:** D01 and A04. **Do:** decide whether current guard coverage makes the feature broadly useful, and whether an exact finite-budget variant is technically feasible. If not, document a specialized API/mode rather than removing budget guards.

**Accept:** maintain opt-in unless safety and whole-gate performance support broader policy. Any policy change is a separate PR with full oracle/gate run.

### X07 — Validate X03 recursive-ascent equivalence and limits (conditional, small tests first)

**Depends:** A04, only if expression-chain full-tree output matters to the gate. **Do:** construct a correct baseline parser with the same left-associative tree shape and compare complete trees, failure-frontier and limits; repair any invalid comparator/depth-failure test. Run more than five repetitions and several chain/branch shapes; verify that parsing status, not merely intermediate-node `successful`, is compared when a resource limit trips.

**Accept:** prove a restricted applicable grammar class and realistic improvement; otherwise keep `directAscent` specialized/manual. No automatic general left-recursion transformation.

### E01 — Integrated 1.5× audit (small/medium)

**Depends:** all accepted changes; do not wait for optional branches that were closed. **Do:** run current source-matched full gate and exact differential oracle; document default vs active opt-in policies separately. Store absolute times, pass counts, medians, tail ratios, zero data loss, build metadata, and any compiler/CTFE cost.

**Accept:** report the precise share of ≤1.5× checks; **do not call Phase 3 successful if the actual 1.5× target remains unmet**. If it remains unmet, use the measured A04/B02 waterfall to choose a subsequent project; do not reset the target to 5×.

## 4. Priority and parallelism

**Critical path for one agent:** A01 → A02 → A03 → A04 → B01 → B02 → B03 (if justified) → B04 (if justified) → E01.

**Parallel branch after A02:** C01 → C02 → C03 (conditional), D01 → D02, X07 (conditional). These branches are **validation**, not automatic optimization commitments. If constrained for time, prioritize A03/A04/B01/B02 over C/D/X because the global median gap likely requires a broadly applicable improvement.

**Closed without new evidence:** R03 narrow invalidation, H04 local memo bypass, H05 duplicate whitespace guards, H08 broad emitter simplification, chasing H07's four remaining replays. Keep H07 and the F/R/H diagnostic infrastructure; keep R06 and H03 opt-in.

## 5. Milestone template for a locally run coding agent

> **Work ONLY on milestone `<ID>`** of `PERFORMANCE_PLAN_PHASE3.md`. First inspect the actual repository, benchmark scripts and saved datasets. Use the exact compiler flags and version symbols, and record their activation/fallback counters. Make no parser source changes in measurement-only tasks. Preserve exact PEG semantics, resource limits, output and input ownership. Run focused differential tests, then matched benchmarks. Submit one narrow commit/report with (1) hypothesis; (2) revision/compiler/build config; (3) exact reproduction commands; (4) unmodified raw results; (5) active-path evidence; (6) before/after and worst-case controls; (7) acceptance or revert decision. **Do not proceed to the next milestone without review.**

### Suggested first assignment

> **A01.** Establish a source- and config-matched provenance/activation ledger for the current checkout and existing P07/P09/P11/P13/P15 datasets. Verify build flags, `ParserBackend` choice, `ParseContext` budgets, `outputLimit`, `OwnInput`, trace mode and expected optimization counters. Do not optimize or benchmark new features yet. Output `performance/phase3/A01-manifest.json` and `performance/phase3/A01-report.md`; enumerate unavailable source versions or raw data explicitly.

