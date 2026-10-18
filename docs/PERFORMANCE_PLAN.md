# NPegged performance roadmap — source-grounded, agent-sized milestones

## 1. One strategy, not several conflicting roadmaps

**Target:** retain the full reference parser, add a fast opt-in path for the *same* PEG and output contract, and address two different performance regimes:

1. **Tiny-input / general-grammar overhead:** the historical acceptance gate reports a handful of PEG validation ratios just over 5×. Work on dispatch, repeated boundary probes, effect-localized scalar code, and other *measured* remaining overhead. The last documented scalar-record snapshot passed **383/387 performance checks**, with four *performance* failures on small PEG validation cases; this is not 383/387 correctness tests.
2. **Recursive scaling:** historical 256→512-term measurements show indirect-recognition time ~60.9→231.6 μs, direct-records ~1.55→5.75 ms, indirect-records ~4.45→16.86 ms. Those are different manifestations of recursive invalidation and output copying and need separate experiments; the current source still has both mechanisms.


**Deliver work in three lanes, with explicit joins:**

- **Foundation F (required first):** reproducible baseline, differential oracle, cost attribution, small-input failure analysis.
- **Scaling R (after F):** independently reduce left-recursion invalidation and output snapshots, then consider combining.
- **Hot path H (after F):** per-rule effect eligibility and localized direct lowering, then measured scanner/boundary refinements.
- **Research X (after evidence):** speculative caches, recursive ascent, multi-token DFA, alternative error policy. These are not part of the acceptance-critical path.

An agent handles **one numbered task per PR**, targeting roughly one to three source files plus tests (exception: test harness setup). No task may silently broaden the accepted grammar or change output/lifetime semantics.

## 2. Source-verified facts and planning consequences

| Location in supplied archive | Observed behavior | Consequence |
|---|---|---|
| `npegged/grammar.d`, `grammar(...)` at ~2333/2779 | Defaults remain full memo + combinator backend; direct/selective are opt-in | Benchmark the actual modes before changing defaults |
| `grammar.d`, `emit` ~1962–1999 | `actionGrammar` disables all scalar direct rules; `analyzed.conservative` causes broad conservative memo policy | Replace *global* barriers with rule-local, conservative proofs |
| `grammar.d`, `emitDirect` ~1702–1930 | Direct scalar recognition/control, primitive lowering and bounded zero-width optimizations already exist | Optimize emitted code or eligibility; don't reimplement the backend |
| `peg.d`, `State.memoizedRule` ~831–930 | Seed-growth loop invalidates memo entries after growth; copies compact output snapshots | Two independent asymptotic experiments |
| `peg.d`, `invalidateMemo` ~762–786 | Iterates entries and unlinks retired completed entries from *both* active list and hash buckets | Measure *current* visits; don't claim it revisits all historical entries forever |
| `records.d`, `RecordBuffer.snapshot` ~91 | Copies `CompactNode` slices; rollback changes logical length, not arena allocation | Distinguish copied bytes, requested bytes and retained peak memory |
| `records.d`, `CompactNode` | A `uint` and three `size_t` fields (usually 32 B on 64-bit) | 16 B layout is a separate *optional* checked-size experiment |
| `peg.d`, `check`, `parseRecords` ~1000–1100 | Recognition and compact records already exist; `OwnInput=false` borrows caller input | Never compare borrowed records with an owned full tree as an equal-cost contract |
| `analysis.d`, `solve` ~1080 | Existing FIRST/nullability, left-edge SCC and whole-grammar `conservative` logic | Extend this graph, not replace it |
| `dfa.d`, `dfaToken` ~530 | Existing DFA fast path has semantic/budget/tracing guard and may replay original | Measure replay before designing combined scanner |

## 3. Acceptance contract: applies to every task

**Correctness matrix (before timing):** compare reference combinator and candidate direct backend with the same memo policy, selector, ownership and limits. Verify `status`, success, consumed `end`, exact `failEnd` (including on success), record sequence `(kind, begin, end, parent)`, and full `ParseTree` fields where that mode is selected. Separately test trace callback *sequence*, semantic-action count/order, CTFE, embedded NUL/UTF-8/non-ASCII bytes, EOF, invalid/truncated input, predicates, nested/backtracking choices, direct/indirect/nullable left recursion, step/depth/memory/output limits, and bounded termination. A mode that changes semantics requires **a separately named API policy**, not a hidden optimization.

**Performance matrix:** compare like with like: full tree vs full tree; selected records vs identical selected records; recognition vs recognition. At minimum test default/full combinator, selective combinator, direct selective recognition, direct selective records (borrowed **and** owned if the workload uses both). Record 3 independent runs × >=7 samples, raw samples and median ns/parse for small cases and throughput for large ones. Record compiler/version/flags, CPU, source commit and hash manifest, grammar and output policy, input size, allocations and peak bytes. Instrumented measurements are **not** timing measurements. Report worst cases, not only geometric means.

**Promotion rules:** (1) no semantic delta in the correctness matrix, (2) no new timeout/memory/compile failure, (3) measurable advantage in the *intended* case (as a default trigger, >=15–20% repeated improvement if code complexity increases), (4) no unexplained major regression elsewhere, and (5) no claim that a global <=5× target passed until **every** equal-output case passes in **each** of the three runs. Keep reference behavior and fallback in place. For large generation changes, also gate generated source/object size, compiler wall time and peak memory.

**Instrumentation contract:** put counters behind existing `version(NPeggedMetrics)` or a separately explicit diagnostic build; report the overhead of instrumentation independently. Count work at correct semantic boundaries, do not increment in hot timing builds. Budgeted parsing checks must not overflow (`size_t.max` is finite), and resource failures must remain sticky.

## 4. Foundation milestones — complete sequentially

### F01 — Establish reproducibility (very small)

**Files:** checkout build/config/scripts/docs only. **Do:** locate the scripts mentioned in the documents (`performance_gate.py`, `recursion-scaling.sh`, `recursion-matrix.sh`), identify actual compiler commands, hash sources, capture baseline and machine metadata. If absent, add *minimal* smoke runner rather than inventing historical benchmark results. **Done when:** one documented command executes a source-matched complete baseline, or a recorded blocker names the missing assets. Artifact: `performance/baseline-manifest.json`. **Do not optimize source.**

### F02 — Pin down differential semantics (small)

**Files:** new test fixture(s), `peg.d`/`grammar.d` tests if needed. **Do:** build a reusable `assertSameParse` helper for direct vs combinator, and one curated corpus for success, failure, action, trace, CTFE, selected records and finite limits. Use small exhaustive input enumeration (`{a,b,EOF}`, lengths 0–4) only for tiny fixture grammars, plus targeted long cases. **Done when:** a mismatched field is reported with grammar/input/mode/limit and the suite runs under a timeout. No production changes.

### F03 — Restore/extend the two scaling matrices (small)

**Files:** test/benchmark scripts and fixture grammars. **Do:** run input sizes 16,32,64,128,256,512,1024 as feasible; direct/indirect recursion, valid/invalid suffix, recognition/records/full tree, comb/direct. Record timing vs length and `arena.used`, `requestedBytes`, `outputArena.used` separately. **Done when:** raw CSV + metadata and a summary contain complete sample counts and explicit timeouts; preserve prior historical data without treating it as current.

### F04 — Attribute work with existing metrics (small)

**Files:** `peg.d`, `records.d`, diagnostic fixture. **Do:** retain `memoCalls/memoHits/seedGrowths/invalidationVisits/invalidatedEntries/snapshotBytes`; add counters for *restore nodes/bytes*, record growth-copy bytes, memo bucket traversal/rehash, and output snapshot count. Count restore operations at `RecordBuffer.restore` or wrapper, not approximate from snapshot bytes. **Done when:** deterministic unit tests assert counter deltas on simple parses and metrics compile out of timed builds. No algorithm change.

### F05 — Diagnose the four tiny PEG gate failures (small)

**Files:** benchmark harness plus focused fixture; optional tiny isolated fix afterward as a **separate** PR. **Do:** obtain fresh failed rows, distinguish input setup/teardown from parser-only time, inspect optimized code for the dominant failed shape, compare full/ selective memo and direct/combinator. **Done when:** each failure has its input shape, percent time by stage (where measurable), remaining generated calls/branches, and a proposed <=1-file fix or a justification for deferral. **Don't prematurely redesign left recursion to address a tiny nonrecursive workload.**

**Checkpoint F:** choose one *measured* hot-path ticket for H, and classify recursion as invalidation-dominated, output-dominated or both. If runtime/harness is absent from the supplied archive, do not fabricate these classifications.

## 5. Recursion scaling milestones — one mechanism at a time

### R01 — Reproduce and isolate the invalidation penalty (small)

**Depends:** F03, F04. **Files:** only recursion fixture and metrics/report. **Do:** compare direct/indirect growth in recognition mode (which has no record snapshots) and collect per-length visits, retired/rehash work, seed iterations, retained arena bytes. **Done when:** we can say which counter scales superlinearly and at which sizes. **No runtime change.**

### R02 — Add a diagnostic dependency trace (small/medium)

**Depends:** R01. **Files:** `peg.d`, targeted tests. **Do:** in a *diagnostic-only* build, record which memoized calls consult an active seed, including calls via already memoized results. Emit per-seed dependency edges and compare them with entries retired by the existing broad invalidator. Instrument nested active heads and overlapping positions. **Done when:** trace has stable IDs, bounded retained memory, and a regression corpus proving whether a proposed narrower invalidation set would be safe. **Do not change invalidation yet.**

### R03 — Prototype narrower invalidation behind an explicit switch (medium)

**Depends:** R02. **Files:** `peg.d` plus correctness tests. **Do:** use dependency-driven invalidation **only for a demonstrably sound subset** (for example, proven direct recursive components without actions or opaque calls). Keep the existing `invalidateMemo` fallback for any unproven call chain/position interaction. Ensure retired entries remain unlinked from both bucket chain and active list, active seeds never disappear and memory usage remains bounded. **Done when:** differential matrix including indirect/mutual/nullable recursion passes and recognition scaling improves. A proof gap or no benefit means stop/rollback the prototype.

### R04 — Measure record copying independently (small)

**Depends:** F04. **Files:** `records.d`, record fixture/report. **Do:** measure copied bytes in snapshots, restores, buffer reallocations and actual output nodes for the same direct/indirect chains. Compare a selector for only top/root nodes vs all named rules. **Done when:** plots separate *logical output size*, *requested bytes*, and *peak retained bytes*; no runtime behavior changes.

### R05 — Prototype shared output snapshots in isolation (medium)

**Depends:** R04. **Files:** `records.d` and tests only initially. **Do:** implement a separate experimental snapshot representation (e.g. immutable fragments/checkpoints), with tests for nested parents, replay rebasing, rollback and finite budgets. **Do not assume that seed growth appends a stable prefix**: PEG growth can replace earlier output. If structural sharing is not provably safe for a snapshot, fall back to copying it. **Done when:** restore yields byte-for-byte identical compact records and no longer copies each unchanged subtree in a synthetic deep-growth fixture. Keep existing snapshot API working.

### R06 — Integrate snapshot experiment into pure recursive records (medium)

**Depends:** R05; independent of R03. **Files:** `peg.d`, `records.d`, output tests. **Do:** wire shared snapshots behind an opt-in internal policy for an action-free supported subset. Preserve output suppression, sticky allocation errors, parent offsets, replay and selector identity. **Done when:** recursive record output is identical under all tests and observed copied bytes/scaling improves. Do **not** combine this with R03 in the same commit.

### R07 — Evaluate combination and stop criteria (small)

**Depends:** R03 and R06 if they passed. **Files:** benchmark/report only unless integration fix needed. **Do:** 2×2 matrix {old,new invalidation} × {old,new snapshots}, compare recursion recognition/records/full trees and normal PEG/CSV/JSON cases. **Done when:** decide promote independently, promote together, or revert each, with scaling exponents and memory/compile-cost trade-offs. No promotion based solely on one long synthetic expression.

## 6. Hot-path milestones — run after F, independent of R

### H01 — Report why a rule did not get the fast path (small)

**Files:** `analysis.d`, `grammar.d`; test report. **Do:** add an opt-in text/JSON eligibility report with rule names, root expression, selected backend, memo policy, left recursion, conservative/unknown evidence, action/effect evidence, scalar eligibility, direct fallback, and selected-record conditions. **Done when:** output is deterministic and tests cover grammar with one action, one opaque reference, one recursive rule and unaffected pure rules. **No generated-parser semantics change.**

### H02 — Make conservatism rule-local for reporting first (small)

**Depends:** H01. **Files:** `analysis.d`; tests. **Do:** compute rule-local *known/unknown* and *actionful* flags, propagated conservatively through callees, with parameterized/opaque references unknown. **Do not yet use flags to change memo policy.** **Done when:** a single unrelated opaque rule no longer marks all **reported** pure rules unknown; cycles and transitive callers remain conservatively classified.

### H03 — Allow proven pure islands within an action-bearing grammar (medium)

**Depends:** H02, F02. **Files:** `grammar.d`, differential tests. **Do:** replace the whole-grammar `actionGrammar` exclusion *only for proven pure, nonrecursive subgraphs* while retaining tree/action fallback wherever action captures or parse-controlling effects could matter. Verify mixed-mode calls across boundaries in `check`, records and full trees, with callback count/order and tracing enabled/disabled. **Done when:** emitted fast path can be confirmed for an identifier/whitespace rule in an otherwise actionful grammar; outputs and callbacks remain exact.

### H04 — Restrict broad conservative memoization only with proof (medium)

**Depends:** H02 and R01. **Files:** `grammar.d`, `analysis.d`, tests. **Do:** make selective memo policy depend on *local* proven recursion/unknown/effect facts rather than the whole grammar. Keep mandatory recursion entries non-evictable and honor overlapping backtracking. **Done when:** unchanged parse behavior and a profile shows fewer memo calls/allocations on a deliberately mixed pure+opaque grammar. Roll back on any worse scaling.

### H05 — Fix one source-verified fixed-cost hotspot (small)

**Depends:** F05, H01; choose **one** hotspot. **Files:** `grammar.d`/`peg.d` as required, new microfixture. Examples: duplicate `TopBoundary` lookahead, unnecessary cursor wrappers surviving LDC optimization, a repeated budget check in a proven bulk-scan region. **Do:** select by perf/assembly/counter evidence; preserve trace, failures, predicates and work limits. **Done when:** >=15–20% repeated win on the isolated targeted case and no outlier regression. Next hotspot is another ticket, not an extension of this one.

### H06 — Per-rule scanner fallback report (small)

**Files:** `dfa.d`, `grammar.d`, diagnostic fixture. **Do:** count how often DFA was eligible, guarded off, failed and replayed, and input bytes replayed; assign a reason (records, budget, trace, state budget, semantic proof, failure diagnostic). **Done when:** a report names the actual scanner hotspots. **Do not change DFA semantics yet.**

### H07 — One exact failed-scan shortcut (medium, conditional)

**Depends:** H06. **Files:** `dfa.d`, tests. **Do:** optimize *one* high-frequency, provably equivalent failed-token case, supplying identical `failEnd`, step accounting and record behavior. Compare against current primitive literal lowering before introducing a new lexer or broad DFA growth. **Done when:** exhaustive small alphabet/EOF/limits comparisons pass and measured whole-parser speed increases. Otherwise abandon.

### H08 — Direct-code simplification only where machine code warrants it (medium, conditional)

**Depends:** H05. **Files:** `grammar.d`, codegen tests. **Do:** simplify one emitted expression pattern (`and`, `or`, repetition, scalar rule calls) that still produces measured unnecessary work, not a general new IR in one PR. Retain recursion boundaries, exact diagnostics and work accounting. **Done when:** optimized assembly confirms removal, targeted parser improves, and grammar generation/compilation do not regress materially. Split any larger cursor-IR project into independently benchmarked lowering passes.

## 7. Research tickets, intentionally out of the critical path

- **X01 (analysis UX):** bounded literal-prefix discrimination after FIRST-byte overlap. Fixture `"ab" / "ac"`, `"a" / "ab"`, predicates/EOF; preserve ordered choice and diagnostic details. This follows H01 rather than substituting a new analysis framework.
- **X02 (memo policies):** optional 0/1/2/4/8-entry ordinary-rule phrase caches, separate from mandatory recursion state. Run adversarial shared-prefix tests to expose worst-case rescans before considering deployment.
- **X03 (recursive ascent):** action-free direct left recursion only, behind a prototype backend; compare associativity, capture shape, failure offsets, stack usage and compiler work against R03/R06. Indirect/nullable/action recursion retain the general backend.
- **X04 (combined scanner):** only lexical regions with a priority-preserving PEG-equivalence proof; no maximal-munch substitution. Test `('a' / 'ab') 'c'` on `abc` and `'a'* 'a'` on `a` as anti-regression fixtures.
- **X05 (alternative diagnostics):** a *named* opt-in policy for minimal success-path diagnostics and failed-input replay, explicitly excluding unsafe action-dependent double evaluation. Exact `failEnd` mode remains supported.
- **X06 (16-byte compact nodes):** check `uint` limits or wide fallback; measured memory savings required. No silent truncation, no change to public offsets.

Each X ticket needs an experiment memo (hypothesis, metric, rejected alternatives, proof boundary, stop condition) **before** changing production APIs.

## 8. Operating procedure for a local coding agent

Create `performance/tasks/` and `performance/results/` (or the checkout's current equivalents). For every PR:

1. Take the lowest-numbered unblocked task from this plan. Verify source locations against checkout; don't assume this source-only archive contains the full project.
2. Write `TASK-ID.md` with the hypothesis, precise semantic contract, candidate files, baseline command, targeted workload and rollback plan.
3. Commit a failing **diagnostic/test** first for behavioral changes, then the smallest source patch and adjacent unit tests. Keep a reference fallback; no default policy changes.
4. Run targeted differential + timeout/memory/CTFE/tracing/limits tests, then required DMD/LDC, formatting and no-Phobos checks. GDC compatibility is optional. For promoted source changes, run sanitizer/Valgrind and the project's required >90% line and branch coverage checks per executable `src/` module. The current branch collector still needs GDC 16/gcov as tooling; report missing coverage evidence explicitly rather than treating line coverage as a substitute.
5. Benchmark optimized LDC **without** metrics instrumentation and store source-matched raw samples. If relevant, run an instrumented job separately; never mix the timing cohorts.
6. Append one row to the performance ledger below and either **accept**, **keep as experimental**, or **revert**. No overlapping unreviewed codegen/recursion changes.

**Agent task prompt (copy/paste):**

> Implement milestone **F01** from `PERFORMANCE_PLAN.md` in this checkout. First locate the actual build and test scripts and read the task acceptance criteria. Make only changes in the declared scope. Preserve default behavior, PEG ordered choice, diagnostics, output records, action/tracing effects, CTFE and resource limits. Add tests and run all available targeted checks. Report exact commands/results, source hashes, and any missing tooling. Do not proceed to another milestone, change parser defaults, or claim a performance improvement without source-matched measurements.

| Task | Commit | Checks & coverage | Baseline report | Candidate report | Outcome / regressions | Decision |
|---|---|---|---|---|---|---|
| F01 | ce113d9 | source hashes verified; existing equal-output gate | performance/results/F01-baseline.json | — | 380/387 paired checks; 7 ratio failures | baseline captured |
| F02 | 39906d3 | DMD/LDC differential fixture, exact tree/action/trace comparisons, CTFE and finite limits | performance/tasks/F02.md | — | no semantic delta in runnable corpus | accepted diagnostic |
| F03 | 42a26c6 | 12 complete timing CSVs, 4 diagnostic CSVs; 9408 timed samples; all source hashes verified | performance/results/F03/README.md | — | all sizes through 1024 complete | accepted diagnostic |
| F04 | b1c8a71 | deterministic DMD/LDC metric deltas; differential suite; diagnostic ASan/LSan; compile-out checks | performance/results/F03/README.md | performance/results/F04/README.md | output-dominated recursion; no algorithm change | accepted diagnostic |

| F05 | see git log | 3 runs × 7 samples; full/selective, combinator/direct; stage probes, traces, optimized-code evidence; full checks in verification report | performance/results/F01-baseline.json | performance/results/F05/README.md | four shapes diagnosed; H05 empty-Sp candidate; output-dominated measured recursion | accepted diagnostic; no optimization |
| R01 | 658fb66 | DMD smoke; 3360 timed and 160 counter samples; source hashes verified | performance/results/F04/README.md | performance/results/R01/README.md | no superlinear recognition work through 8192 terms in these chains | accepted diagnostic |
| R02 | 09834c0 | bounded traces; 448 cases; DMD/LDC, differential, -vgc, diagnostic ASan/LSan and Valgrind | performance/results/R01/README.md | performance/results/R02/README.md | cached transitive dependencies required; nested independent-retirement opportunity | accepted diagnostic |
| R03 | see git log | DMD/LDC oracles, F02 matrix, sanitizer/Valgrind; 3150 timed and 150 counter samples | performance/results/R01/README.md | performance/results/R03/README.md | nesting improves; sibling visits become quadratic with 11–12× regressions | rejected/rolled back under stop rule |
| R04 | 29e6791 | 256 source-pinned diagnostic parses; DMD/LDC identical CSV; full coverage and memory checks | performance/results/R01/README.md | performance/results/R04/README.md | snapshot/restore copies quadratic despite linear logical output; root projection removes copies | accepted diagnostic |
| R05 | e29d83d; test-first 48d76ec | DMD/LDC normal + metric oracles; optimized LDC; byte equality, finite budgets, -vgc, coverage and memory checks | performance/results/R04/README.md | performance/results/R05/README.md | immutable fragments freeze 65536 B versus 67141632 B flat at depth 2048; parser wiring unchanged | keep as isolated experimental API |

| R06 | 8bb643f; test-first ae3fa22 | 24 exact DMD/LDC oracle pairs; uninstrumented checks, >90% source line/branch coverage, -vgc, ASan/LSan and Memcheck; 34,272 timing + 1,632 counter samples | performance/results/R04/README.md | performance/results/R06/README.md | 2048-term ratios 0.388–0.436; snapshot freezing/retention reduced; replay remains quadratic; worst small-case median 1.601× | keep explicit experiment only; no default promotion; R07 prerequisite unmet because R03 rejected |

| H01 | ac5f3cc; test-first aefd42d | 72 DMD/LDC + optimized LDC report/source pairs; valid deterministic JSON/text, forced-GC retention; >90% coverage; differential, -vgc, ASan/LSan and Memcheck | tests/eligibility_sources.json (R06 source) | performance/results/H01/README.md | actual scalar/direct/memo/record decisions exposed; all generated-source goldens unchanged; documented sanitizer/GC configuration limits | accepted diagnostic only; global barriers unchanged |

| H02 | see git log; test-first 8e0bfa7 | DMD/LDC + optimized LDC local-effect oracle; 72 unchanged codegen goldens; >90% line/branch coverage; differential, -vgc, ASan/LSan and Memcheck | performance/results/H01/README.md | performance/results/H02/README.md | pure islands reported separately; unknown/action facts propagate through callers and cycles; global parser barriers retained | accepted diagnostic only; no policy change |

Checkpoint F: see [F05 findings](../performance/results/F05/README.md) and [verification](../performance/results/verification/README.md).

## 9. First two implementation sprints and explicit non-goals

**Sprint A (small, mostly risk-free):** F01 → F02 → F03 → F04 → F05. Outcome: trusted reproducibility, semantics and evidence on tiny PEG and recursive scaling. Do not claim speed gains; F/H/R priorities are then data-driven.

**Sprint B (parallel tracks):** R01 → R02 and R04 (scaling diagnostics); H01 → H02 (static eligibility visibility). These provide executable proofs and leave normal codegen and parse behavior untouched. *After* Sprint B, choose exactly one of R03, R05 or H03 to implement; do not bundle.

**Explicitly deferred:** change to public defaults, alternate language semantics, automatic Pratt lowering, replacing `CompactNode` with events, a universal scanner, handwritten lexer/bison comparator, broad per-rule memo table rewrite, new parser IR, or copying code from Mouse. Mouse-informed ideas credit Mouse 2.3 by Roman R. Redziejowski (Apache 2.0); see the source-linked [Mouse review](MOUSE_REVIEW.md) and vendored [license](../third-party/Mouse-2.3/LICENSE.txt). Copied/adapted implementation must identify upstream files in source and project NOTICE, retain applicable notices, mark modifications and distribute the Apache license. Qualify the project NOTICE's blanket Boost statement if Apache-derived material is introduced.

**Why this order:** it preserves the real progress already made, forces attribution before high-risk changes, separates asymptotic costs from small-case fixed costs, and turns each optimization into a reviewable, revertible local-agent assignment with objective completion evidence.
