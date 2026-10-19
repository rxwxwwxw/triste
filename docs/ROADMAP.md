# NPegged Development Roadmap — Agent Execution Plan

**Status:** Proposed work queue; no milestone is marked complete by this document.  
**Audience:** A locally running coding agent with access to the full repository, DMD, LDC, test/build scripts, and benchmark machines.  
**Objective:** Preserve the exact observable behavior of NPegged while moving generated parsers toward handwritten D lexer/parser performance. Target **≤1.5× handwritten execution time per equal-output benchmark workload**.  
**Priority order:** Make it work → make it correct → make it fast.  
**Primary artifacts:** Code and tests in the repository; **all performance evidence under `performance/`**.

> **Agent: read `AGENTS.md` before doing anything.** Its druntime-only, no-Phobos, `@nogc`, `nothrow`, RAII, testing/coverage, `dfmt`, DMD/LDC, sanitizer, and performance requirements are binding. If this roadmap conflicts with `AGENTS.md`, obey `AGENTS.md` and record the discrepancy. Do not invent successful test runs, timings, tools, files, or proofs.

## 0. Scope, observed code, and guiding principles

### What already exists — do not reimplement it

Inspection of the supplied NPegged source archive shows:

- `npegged/analysis.d`: `GrammarAnalysis`, `Expression`, conservative byte-oriented `FirstFacts`/nullability, `ruleEffects`, recursion facts, `analyzePrefixDiscrimination`, and classifications `disjointFirst`, `disjointTails`, `shadowed`, `guarded`, `unbounded`.
- `npegged/grammar.d`: `Frontend`, `computeFirstSet`, `prefixDiscriminationReport`, `eligibilityReport`, `emitExpression`, `emitTokens`, `emitDirect`, rule emission, direct cursor functions, prefix factoring, predictive choice, and scanner fusion.
- `npegged/peg.d`: parser state, cursor/scalar recognition, `predictiveChoice`, selective/full memoization, left-recursive seed growth, and parse modes.
- `npegged/dfa.d`: regular-region DFA compilation/scanning.
- `npegged/records.d`: compact record/capture storage and rollback.
- `npegged/introspection.d` and tester modules: introspection and existing grammar testing machinery.
- Conditional instrumentation/specializations include `NPeggedMetrics`, `NPeggedScannerMetrics`, `NPeggedPureIslands`, and `NPeggedSharedOutput`.

Do not assume unobserved tooling exists. First inspect the actual local checkout, record what is present, and add missing benchmarking infrastructure incrementally. Do not assume the local project uses a particular `src/` layout merely because `AGENTS.md` gives generic examples; adapt its coverage and path rules to the real checkout while preserving their intent.

### Non-negotiable behavioral invariants

An optimization must preserve all outputs relevant to the parser's chosen mode:

1. Accepted/rejected input, whole-input acceptance where requested, cursor `end`, `failEnd`, and applicable status/error category.
2. Prioritized choice, possessive/greedy repetition, semantic and syntactic predicates, EOF handling, UTF-8/byte boundaries, and non-progress termination behavior.
3. Trace/action behavior, observable action order/side effects, and error diagnostics whenever the public API promises them.
4. Tree shape, named captures, child/parent ordering, compact record spans/tags, rollbacks, resource limits, and memoized left-recursion results when applicable.
5. No undefined behavior, invalid memory use, or hidden GC allocations in annotated hot paths.

A recognizer that merely accepts the same language is **not equivalent** to a tree/record parser that emits a different output. Treat recognition equivalence, diagnostic equivalence, and full output equivalence as separate proof obligations. Use an explicit conservative fallback when facts are unknown.

### Work discipline: one small milestone per agent task

- Work from the ordered milestones below; do not batch unrelated milestones into a broad refactor.
- Before coding: state affected files, dependency milestones, the existing path, the proposed invariant, and at least three adversarial test categories.
- Make a small, reviewable change; prefer a report-only analysis before transforming generated code.
- Add **multiple** focused unit/integration tests, not just one happy-path test. Put unit tests beside the implementation per `AGENTS.md`; place end-to-end tests in the repository's tests directory with timeouts and memory caps.
- Any optimization that changes generated runtime code must include a before/after benchmark in `performance/`; analysis-only changes must still measure analysis/generation overhead when relevant.
- Never weaken or silently edit a handwritten baseline to improve ratios. If a baseline is incorrect, fix it in a separate reviewed task and retain the old results.
- Run `dfmt`, DMD/LDC builds/tests, applicable `-vgc`, coverage, sanitizer/leak checks, and integration timeouts according to `AGENTS.md`. Record commands and results, including unavailable tools as **not run** rather than **passed**.
- Finish with a milestone report, artifacts, and a commit. Do not claim a speedup unless actually measured and repeatable.

## 1. Mandatory `performance/` contract

### Directory layout

Create the following in milestone **A1**, adjusting scripts to the actual build system. Keep small source/config/results files in version control; keep large generated inputs/binaries outside Git or behind an explicit size policy.

```text
performance/
  README.md                       # How to run benchmarks and interpret output
  workloads.json                  # Stable workload registry, modes, inputs, reference baselines
  corpora/
    manifest.json                 # Inputs: origin, seed, checksum, length, license if applicable
  baselines/
    <run-id>/
      metadata.json               # Machine/compiler/config/git commit/measurement parameters
      raw.csv                     # Every measured repetition (no cherry-picking)
      summary.csv                 # Per-workload aggregated metrics and handwritten ratios
      correctness.json            # Whether compared outputs matched, mismatch details
      notes.md                    # Assumptions and limitations
  milestones/
    <milestone-id>/
      <run-id>/
        metadata.json
        raw.csv
        summary.csv
        correctness.json
        notes.md
  trends.csv                      # Append-only comparable baseline/milestone aggregates
  latest.md                       # Human-readable dashboard, regenerated from result data
```

`<run-id>` should be stable and collision-resistant (e.g., UTC timestamp plus shortened commit hash). Generated scripts, if needed, can go in existing `scripts/` or `performance/scripts/`; document how to run them. Do not import `std.*` into D-based benchmark tools.

### Required workload fields (`workloads.json`)

For each workload record: stable `workload_id`, grammar/start rule, input fixture or generator+seed, byte length, validity (valid/invalid/mixed), corpus family, output mode (recognition/compact/tree), parser backend/config, compiler and flags, handwritten reference identifier, and output-equivalence policy. Different output modes are **different workloads**. A handwritten recognizer is not a fair performance baseline for a parser building a full tree.

### Required run metadata (`metadata.json`)

Record: timestamp, git commit and dirty state, OS/kernel, CPU model, architecture and core count, RAM, DMD and LDC versions, build commands, release/optimization flags, sanitizer/instrumentation state, benchmark harness version, workload registry revision, corpus checksums, repetitions, warmups, timeouts, CPU pinning if used, frequency/governor or equivalent if known, and the exact comparison commit/run.

### Required measurements (`raw.csv` and `summary.csv`)

- Raw columns (at minimum): `run_id,workload_id,implementation,compiler,mode,iteration,input_bytes,elapsed_ns,successful,output_digest,status`.
- Summaries (at minimum): `run_id,workload_id,implementation,compiler,mode,n_samples,median_ns,p95_ns,bytes_per_second,handwritten_median_ns,slowdown_ratio,correctness_ok`.
- Record executable size, generated source size, parser generation time, native compilation time, and peak memory where measurable. Track allocations and backtrack/memo metrics in **separate instrumented runs**, not inside clean timing runs.
- Compute `slowdown_ratio = generated_median_ns / handwritten_median_ns` on **identical hardware, compiler family, input, output obligations, and valid build configurations**. Mark absent fair baselines `N/A`, not `1.0`.
- Dashboard: count and percentage at ≤1.5×, p50/p90/p95 slowdown across workloads, geometric mean slowdown, worst workload, relevant memory/code-size changes, per-compiler results, and previous-run deltas.

### Measurement rules

1. Verify output parity **before** timing. For failure workloads, verify failure behavior and diagnostics required by the comparison contract.
2. Use optimized non-sanitized release binaries for timings, with trace and metric versions disabled; ensure equal-output configuration.
3. Warm up first, then collect **at least 15 timing samples** per implementation per affected workload (more for noisy/short workloads). Alternate or randomized-block implementation order; measure harness overhead; retain all samples. Run more samples when variance is high.
4. Use sufficiently large/repeated inputs to dominate timer resolution; report throughput for meaningful byte counts. Report parser construction, generation, and compile costs separately from parse time.
5. Pinning, thermal conditions, background load, and compiler flags must be documented; compare only compatible runs. Report confidence/dispersion, not just the best iteration.
6. Set integration/test timeouts and memory limits per `AGENTS.md` (usually ≤4 GB); larger data benchmarks must have a separately documented resource budget.
7. A performance regression is not hidden by an improvement in the mean. Flag any **>5% reproducible slowdown** on an unchanged affected workload and any change in peak memory/code size large enough to matter; investigate or guard the optimization before enabling by default.
8. If a benchmark family lacks a legitimate handwritten equal-output baseline, add one as a **separate, tested milestone** or report generated-vs-generated comparisons without asserting the 1.5× goal for it.
9. New grammar features and new optimization paths **must add new workload cases**, including an adverse/negative case where their proof does not apply. Do not tune only on synthetic easy inputs.

### Minimum benchmark families

Maintain at least these categories, with valid and invalid inputs where meaningful:

| Family | What it isolates | Equal-output reference requirement |
|---|---|---|
| `lex_ascii` | whitespace, digits, identifiers, delimiters, escapes, comments | handwritten lexer |
| `lex_utf8` | ASCII/multibyte UTF-8, truncated bytes, terminal boundary behavior | byte/Unicode-matched lexer |
| `choices` | disjoint FIRST, common-prefix, lookahead-guarded, nullable, shadowed | corresponding handwritten deterministic/backtracking logic |
| `nested_expr` | precedence, deep expressions, left recursion | same expression value or same AST/records |
| `structured` | JSON-like, INI/config-like, CSV-like or existing production grammar | same recognition or output representation |
| `output_modes` | recognition vs compact records vs full tree | separate references **per mode** |
| `failure` | early/late failure, truncation, farthest-failure diagnostics | identical failure contract |
| `pathological` | long common prefixes, branch fallback, repeated failed lookahead, memo pressure | safe correct reference; no invented speed target |

Use *existing* repository workloads first. Add missing families with separate test cases and checksums; do not throw away earlier data.

## 2. Milestone overview and dependency order

**Sequence:** Foundations (**A**) → FIRST/FOLLOW (**F**) → **BITES and NEXTBITES (**B**, after F is complete)** → compile-time specialization (**P**, some independent) → grammar extraction (**L**) → generation/fuzzing (**G**) → advanced backends (**X**). Performance/safety tasks apply throughout.

| ID | Priority | Prerequisite | Work product | Relative size |
|---|---|---|---|---|
| A1 | P0 | — | Performance harness, baseline and dashboard | M |
| A2 | P0 | A1 | Per-rule metrics + profiler reports | S |
| A3 | P0 | A1 | Machine-readable optimization/eligibility report | S |
| A4 | P0 | A1 | Cross-backend differential correctness harness | M |
| A5 | P1 | A1 | Generated code/build/memory accounting | S |
| F1 | P0 | A4 | Audit/strengthen nullable, FIRST, can-fail/advance facts | M |
| F2 | P0 | F1 | FOLLOW analysis, with PEG-specific limitations documented | M |
| F3 | P0 | F1 | FIRST-set conflict and shadowing diagnostics | S |
| F4 | P1 | F1,F3 | Sound bounded FIRST-2 dispatch and tests | M |
| **B1** | **P0** | **F1–F3** | **BITES design, abstract input-language representation, proof contract** | **S** |
| **B2** | **P0** | **B1** | **SUCC and NULL analysis for supported pure expressions** | **M** |
| **B3** | **P0** | **B2** | **BITES calculation with lookahead-sensitive intersections** | **M** |
| **B4** | **P0** | **B3** | **Disjoint-choice / hiding diagnostics (report-only)** | **S** |
| **B5** | **P1** | **B3,F2** | **Last/Next relations and NEXTBITES(success/failure)** | **M** |
| **B6** | **P1** | **B4,B5,A4** | **Conservative cut/commit candidates (report-only → guarded optimization)** | **M** |
| **B7** | **P1** | **B3,B5** | **Extended regular SUCC, precision/complexity study** | **M** |
| **B8** | **P1** | **B4,B5** | **BITES reports integrated into eligibility and grammar lints** | **S** |
| P1 | P0 | A2,A3,A4 | Rule-local pure direct/scalar lowering | M |
| P2 | P1 | P1 | Broader direct lowering for wrappers/terminals | S |
| P3 | P1 | F4,A4 | Multi-byte dispatch emitted for certified cases | M |
| P4 | P1 | A2,A4,F1 | Redundant checkpoint/rollback elimination | M |
| P5 | P1 | A2,A4 | Scalar calling convention in capture-free paths | M |
| P6 | P1 | A2,A4 | Specialized scanner loops + DFA layout study | M |
| P7 | P2 | A2,A4 | Selective memoization/left-recursion profiling | S |
| P8 | P2 | P7,A4 | Iterative expression specialization | M |
| L1 | P1 | F2,B4 | Equivalence certificate model + negative tests | M |
| L2 | P1 | L1 | Export certified CFG/EBNF subset | S |
| L3 | P1 | L2,A4 | LL(1) generated backend | M |
| L4 | P2 | L3,F4,B5 | Bounded LL(k) / regular-lookahead experiments | M |
| L5 | P2 | L2 | LR(1) grammar conflict analysis (report-only) | M |
| L6 | P3 | L5,A4 | Optional experimental LR backend / hybrid calls | L |
| G1 | P1 | A4 | Seeded, bounded candidate generator | S |
| G2 | P1 | G1 | Full-acceptance oracle, retries, generation failures | S |
| G3 | P1 | G2,A2 | Coverage-guided generation and reporting | M |
| G4 | P1 | G2 | Weighted production/repetition generator | S |
| G5 | P2 | G3,G4 | Empirical weight learning from parsed inputs | M |
| G6 | P1 | G2,A4 | Valid/invalid mutation, shrinking, regression seeds | M |
| G7 | P2 | G4,G5,A1 | Reproducible representative benchmark corpora | M |
| X1 | P3 | P6,A5 | Vectorized scanners (only if justified by profiles) | M |
| X2 | P3 | L4,P6 | Integrated lexer/predictive parser fusion | L |
| X3 | P3 | A2,A4 | Offline autotuned specialization preferences | M |

S = one narrow change; M = a few narrowly staged PRs if necessary; L = **must be split further before implementation**. If a supposedly small milestone takes more than a focused PR, split it and preserve dependency tracking.

## 3. Foundations — A milestones

### A1 — Baseline and fair benchmark automation

**Files:** actual build/benchmark files (discover), `performance/`, scripts if missing.  
**Tasks:** inventory every existing workload and handwritten reference; explicitly record output mode; automate timed release builds/runs for both DMD and LDC when available; create `performance/README.md`, registry, raw/summary data and dashboard.  
**Tests (minimum):** known-correct equal-output pair; intentionally unequal-output pair rejected before timing; missing baseline produces `N/A` rather than a fabricated ratio; repeat run preserves schema and corpus checksum.  
**Exit:** an initial reproducible baseline under `performance/baselines/<run-id>/` and `performance/latest.md` generated from it. If the environment cannot run a compiler, stop claiming measured performance and record that as an explicit blocker.

### A2 — Per-rule counters, without timing contamination

**Files:** `npegged/peg.d`, `grammar.d`, reporting/test helpers.  
**Tasks:** count calls, success/failure, retries/backtracks, bytes examined, memo hits/misses, output materializations/rollbacks, and optional per-rule exclusive/inclusive time in a **separate instrumentation build**. Reuse existing metric versions instead of duplicating counters.  
**Tests:** one-branch success, choice rollback, repeated memoized invocation, failed lookahead, capture output.  
**Exit:** per-rule machine-readable metrics, zero overhead when disabled (or measured negligible overhead if genuinely unavoidable); instrumented workloads added under `performance/milestones/A2/`.

### A3 — Eligibility and missed-opportunity report

**Files:** `analysis.d`, `grammar.d`.  
**Tasks:** extend existing `eligibilityReport` with rule-local reasons for direct/scalar fallback, recognizer/record mode, DFA eligibility/fusion, FIRST dispatch, memo policy, action effects, unknown facts, and code-generation strategy. Keep backward-compatible report fields.  
**Tests:** grammar-wide action mixed with pure rules; left-recursive rule; parameterized rule; unsupported/unknown construct.  
**Exit:** deterministic JSON and readable text reports that correspond to actual emitted strategies.

### A4 — Differential semantics gate

**Files:** test harness and colocated tests.  
**Tasks:** run the same grammar/input through reference combinators and applicable direct/DFA/memo variants, comparing all observable fields for each mode. For mismatches save smallest available seed/input, compiler flags, and backend versions.  
**Tests:** valid, invalid, EOF/truncated, nullable, lookahead, shadowed alternatives, left recursion, actions, UTF-8, limit exhaustion, compact records, tree. Include timeout/memory checks.  
**Exit:** automated gate invoked for every subsequent optimization; generated-parser equivalence checked before benchmark timing.

### A5 — Generated code and compilation overhead

**Files:** benchmark scripts, `performance/`.  
**Tasks:** measure generated D source bytes/lines, binary bytes, DMD/LDC compilation time, parser-generation time, peak RSS.  
**Tests:** small and large grammar, DFA-heavy and non-DFA paths, repeated deterministic generation.  
**Exit:** size/compiler regressions visible alongside parse throughput in all later milestone reports.

## 4. FIRST and FOLLOW foundations — F milestones

**Ordering gate:** Finish **F1–F3** before beginning any BITES implementation. FIRST and BITES answer related but different questions; **keep both**. F4 (bounded FIRST-2) is an independent optimization and can happen before or alongside later BITES tasks, but not instead of F1–F3.

### F1 — Correct conservative grammar facts

**Files:** `npegged/analysis.d` and tests, minimal `grammar.d` integration.  
**Tasks:** audit fixed-point nullability, may-advance, may-fail, terminal byte sets, well-formedness/progress, effects, and unknown propagation. Separate “provably yes/no” from “possibly yes/no”; avoid interpreting `unknown` as `false`. Handle terminal encoding, zero-width `eps`/`eoi`, positive/negative predicates, recursion/left recursion, and parameterized/dynamic nodes. Preserve existing fast FIRST-bitset analysis.  
**Tests:** empty and nonempty literals; nullable choice/sequence; negative/positive lookahead; EOF in both positions; Unicode and invalid UTF-8; recursion and repetition of potentially nullable expressions.  
**Exit:** documented abstract facts, termination conditions, and a validation matrix. Report unsupported constructs rather than assuming soundness.

### F2 — Contextual FOLLOW, not CFG semantics smuggled into PEG

**Files:** `analysis.d`.  
**Tasks:** compute a classical CFG-style FOLLOW relation for **eligible, action-free CFG-like subsets** to support future LL diagnostics. Also preserve the PEG-specific need for outcome-sensitive continuation analysis; ordinary FOLLOW does not handle backtracking/ordered-choice context faithfully. Use separate names/representations so FOLLOW is **not** reused as NEXTBITES without proof.  
**Tests:** nested choices, nullable suffixes, grammar entry and EOF, recursive rules, sequences behind ordered choices, lookahead.  
**Exit:** conservative report-only FOLLOW sets with a scope/limitations section; zero generated-code changes.

### F3 — FIRST conflicts and prefix diagnostics

**Files:** `analysis.d`, `grammar.d`.  
**Tasks:** enrich existing `analyzePrefixDiscrimination` and `prefixDiscriminationReport` with source location/rule name, potential LL(1) FIRST/FIRST and FIRST/FOLLOW conflicts, and separate definite literal-prefix shadowing from uncertain overlaps. Do **not** classify every FIRST overlap as actual PEG hiding.  
**Tests:** `'a' / 'b'`, `'ab' / 'ac'`, `'a' / 'ab'`, `'ab' / 'a'`, EOF-guarded prefix, nullable trailing branch.  
**Exit:** stable JSON/text diagnostics, no parser code changes.

### F4 — Conservative FIRST-2 decision trees

**Files:** `analysis.d`, `grammar.d`, and/or `peg.d`.  
**Tasks:** for provably pure, nonnullable alternatives with a bounded disjoint two-byte prefix (including distinct end-of-input outcomes), generate a small dispatch plan. Require a sound proof that dispatch does not bypass a potentially successful earlier alternative; otherwise fall back to ordered choice.  
**Tests:** `==`/`=`, `<=`/`<`, shared-prefix distinct tails, truncated 1-byte input, invalid alternative, lookahead/parameterized exclusions.  
**Benchmark:** `choices`: short tokens, longer inputs, adversarial overlapping prefixes; report generated code size too.  
**Exit:** off-by-default trial, then enable only when A4 parity and measured per-workload value justify it.

## 5. BITES and NEXTBITES analysis — B milestones (after FIRST)

### Research basis and correct meaning

Primary reference: Roman R. Redziejowski, **“BITES Instead of FIRST for Parsing Expression Grammar,”** *Fundamenta Informaticae* 109(3), 323–337 (2011), DOI [10.3233/FI-2011-514](https://doi.org/10.3233/FI-2011-514), author-hosted [PDF](https://www.romanredz.se/papers/FI2011.pdf). Read the definitions and proofs in §§4–10 and the limitations in §§11–12 before implementing a rule. The paper's results are formulated for **well-formed conventional PEGs**, not automatically for NPegged's actionful, parameterized, or left-recursion extensions.

BITES is **not** a FIRST-character mask. It is a conservative **language of input strings** on which an expression may *bite* (have a terminal consume nonempty input outside lookahead), retaining constraints from preceding lookahead. The paper uses:

- `SUCC(e)`: a computable **lower approximation** of inputs on which `e` succeeds;
- `NULL(e)`: an **upper approximation** of inputs on which `e` may succeed while consuming nothing;
- `BITES(e)`: an **upper approximation** of inputs on which `e` may bite;
- `NEXTBITES(e, succ/fail)`: an **upper approximation** of the input strings that a subsequent expression could bite after `e` returns with that outcome.

With input alphabet `Σ`, nonempty terminal `t`, and set operations over `Σ*`, the paper defines (notation abridged):

```text
SUCC(t)        = L(t) Σ*                  // terminal, provably succeeds on prefix
SUCC(e1 / e2)  = SUCC(e1) ∪ SUCC(e2)
SUCC(other)    = ∅                       // original conservative approximation

NULL(t)        = ∅                       // consuming terminal
NULL(!e)       = Σ* \ SUCC(e)
NULL(e*)       = Σ*
NULL(e?)       = Σ*
NULL(sequence) = ∅ if proven nonnullable; otherwise ∩ NULL(children)
NULL(choice)   = ∪ NULL(children)

BITES(t)       = L(t) Σ*                  // consuming terminal
BITES(!e)      = ∅                       // probe does not bite
BITES(e*)      = BITES(e)
BITES(e?)      = BITES(e)
BITES(e1...en) = BITES(e1) ∪
                  ⋃_{i=2..n} (NULL(e1...e[i-1]) ∩ BITES(ei))
BITES(e1/.../en) = ⋃ BITES(ei)
```

These equations apply directly only to the supported paper-style constructs. `&e` can be treated as syntactic predicate `!!e` where that desugaring preserves its specific semantics; zero-width `eps`/`eoi`, Unicode/code-point terminals, optimized DFA terminals, and dynamic constructs require explicit classification. **Never apply `BITES(t)=L(t)Σ*` to a zero-width terminal.** Approximate unknown/unsupported constructs by a larger language (`Σ*`) when needed, never by a smaller one that could create a false disjointness proof. Use complement only for a proven lower approximation such as `SUCC`, not for an arbitrary overapproximation.

For example, with an ASCII-letter terminal `letter`:

```text
BITES("abc" letter*)         = "abc" Σ*
BITES((!"abc") letter*)      = (Σ* \ "abc" Σ*) ∩ (letter Σ*)
```

The two alternatives have overlapping FIRST-byte sets but **disjoint BITES**. By contrast, BITES with an incompletely understood predicate may be too broad to establish disjointness; that is `unknown`, not permission to optimize.

The paper's critical conditions include:

1. **Disjoint choice:** `BITES(ei) ∩ BITES(ej) = ∅` for every distinct alternative pair.
2. **No hiding for nonnullable disjoint choice:** Proposition 5. This is a warning-elimination criterion, not permission to reorder actions.
3. **Cut opportunity after a failed alternative bites:** Proposition 6 for nonnullable disjoint choice; broader conditions use NEXTBITES.
4. **Nullable-choice qualification:** Propositions 10–11 additionally constrain nullable alternative positions and intersections with `NEXTBITES(E, succ)` and (for the stronger failure result) `NEXTBITES(E, fail)`.
5. **Greedy repetition qualification:** Propositions 12–13 require `BITES(body) ∩ NEXTBITES(star, succ) = ∅` for the stated hiding/cut reasoning.

**Do not confuse** a proof of *absence of language hiding* with equivalence of a transformed grammar, nor a BITES conflict warning with proof of actual hiding. The paper explicitly notes precision limits, for example keyword/identifier rules guarded by nontrivial negative lookahead, and proposes richer regular `SUCC` approximations.

### B1 — Specify representation and proof outcomes (report-only)

**Files:** `analysis.d` + design comments/tests; no parser changes.  
**Tasks:** design `InputLanguage` or equivalent to represent prefix languages with Boolean union/intersection/complement and EOF semantics. Initial components should include empty/universal, exact terminal-prefix cylinders, byte-class prefixes, and symbolic Boolean combinations; choose an implementation that supports a **sound emptiness query**, not just random sampling. Specify budgets for automaton states, expression nodes, and processing time. Explicit answers: `provenEmpty`, `provenNonempty`, `unknown`; `unknown` is never treated as empty. Define trusted facts and effect/left-recursion exclusions.  
**Tests:** empty vs universal; disjoint prefixes; overlapping prefixes; `"a"Σ* ∩ (Σ* \ "a"Σ*)`; EOF/empty; symbolically complex case exceeds budget → `unknown`.  
**Exit:** documented proof contract and standalone set-operation tests. No optimization consuming BITES yet.

### B2 — Implement conservative SUCC and NULL

**Files:** `analysis.d`.  
**Tasks:** construct `SUCC` as a sound subset of matching inputs and `NULL` as a sound superset of zero-width successful inputs. Base both on F1 facts, but keep `SUCC`/`NULL` as **input languages**, not booleans. Implement proper handling of predicates and zero-width terminals, preserving the soundness directions. For recursion, dynamic predicates, left recursion, actions, or unsupported wrappers, use conservative unknown/top/bottom as appropriate.  
**Tests:** terminal prefix, ordered choice union, `!"abc"`, `&"abc"`, `eps`, `eoi`, optional/star, unknown recursive reference, nullable sequence and choice.  
**Exit:** reportable sets; property tests that sampling never finds a success outside `SUCC`-soundness/`NULL`-soundness directions (sampling supplements, not substitutes for proof).

### B3 — Calculate BITES on the expression graph

**Files:** `analysis.d`, minimal `grammar.d` report interface.  
**Tasks:** compute `BITES` for supported nonrecursive expression operators using the paper's rules; analyze well-formed recursive grammars by sound fixed-point/graph methods or degrade unknown. Record the exact proof scope and budgets. Ensure lookahead itself has no bite, but its `NULL` restriction constrains subsequent byte consumption. Do not replace existing FIRST sets.  
**Tests:** both `"abc"[a-z]*` and `(!"abc")[a-z]*`; pure lookahead only; nested negative lookahead; nullable prefix then consuming suffix; union of choices; optional/repetition; recursive and parameterized fallback; EOF and malformed UTF-8.  
**Exit:** `BITES(expr)` query and stable report-only serialization; A4 verifies no parser behavior changed.

### B4 — BITES disjointness and language-hiding diagnostics

**Files:** `analysis.d`, `grammar.d`.  
**Tasks:** add pairwise disjointness analysis to the existing prefix-report structure, preserving the older FIRST-based details. Classification must distinguish `proven-disjoint`, `possible-overlap`, and `unknown`; a constructive overlap witness is helpful but optional. Apply the *nonnullable* Proposition 5 only when its premises are proven, otherwise report potential hiding without asserting its existence.  
**Tests:** disjoint-FIRST choice; FIRST-overlap/BITES-disjoint guarded choice; prefix capture `('a' / 'aa') 'b'`; completely shadowed branch; nullable alternative unsupported at this stage; unknown dynamic predicate.  
**Exit:** diagnostics identify where BITES improved on FIRST and where its limits prevent a conclusion. Still no runtime changes.

### B5 — Outcome-sensitive NEXTBITES and nullable/repetition analysis

**Files:** `analysis.d`.  
**Tasks:** construct conservative `Last` and `Next` graph relations for **success and failure separately**, including propagation through nested expressions; calculate `NEXTBITES(e, succ)` and `NEXTBITES(e, fail)` as defined in §8 and Appendix A.5–A.6 of the reference. Include parent/caller continuation edges and outcome-sensitive traversal. Check Proposition 10/11 prerequisites for nullable choices and Proposition 12/13 for repetitions. Avoid substituting CFG FOLLOW for NEXTBITES.  
**Tests:** `('a' / 'c'?) 'a'`, safe and unsafe nullable alternatives, `(!'a' .)* 'a'` as a safe stopping-delimiter pattern, `'a'* ('ab' / 'c')` as a possible hiding case, nested rule calls, failure continuation, recursion/unknown fallback.  
**Exit:** sound report of success/failure continuation possibilities, with proof-status/unknown fields. This is a second distinct analysis deliverable, not silently folded into B3.

### B6 — BITES-driven early cut, only after correctness proof

**Files:** `grammar.d`, `peg.d`, A4 harness.  
**Tasks:** first report `candidateCommitSites` and exact theorem/premises per site. Enable an experimental guarded cut **only** for well-formed, pure, nonnullable disjoint choices satisfying Proposition 6, and only if stopping retries also preserves required diagnostics, failure positions, records, and resource limits. Extend to nullable choices/repetitions only when B5's stronger premises and effect invariants are proven. A successful BITES-disjointness check alone is **not** a general license to cut or transform parsing.  
**Tests:** earlier branch bites then fails; later branch must never be skipped unsafely; predicate-only “progress”; lookahead+capture; nested rollback; `failEnd` parity; actionful/left-recursive case must fall back. Differential fuzz at fixed seeds and bounded lengths.  
**Benchmarks:** `choices`, `failure`, `pathological`, `output_modes`; before/after raw/summary under `performance/milestones/B6/`.  
**Exit:** off-by-default fast path proven correct; make default only if reproducible improvement and no output regression.

### B7 — Increase precision with regular SUCC

**Files:** `analysis.d`, optionally reuse proven-correct helpers from `dfa.d`.  
**Tasks:** study extending `SUCC` for regular sequences and bounded lookahead so guarded keyword/identifier patterns can be distinguished. Prefer reusable lazy regular-language operations or a small Boolean prefix-automaton representation; cap determinization and state blowups. Use this **only** as a sound **under**approximation of match success.  
**Tests:** keyword `'down' ![a-z]` versus names guarded by `!Keyword`; different suffixes after keyword; nested lookahead; exact and wildcard prefixes; budget exceeded → unknown.  
**Benchmarks:** compiler analysis time, peak memory, number of newly certified disjoint choices, and any B6 runtime effect in separately instrumented/release runs.  
**Exit:** documented gain in certificate precision against analysis cost; keep narrower original if not worthwhile.

### B8 — Unified FIRST/BITES diagnostic report

**Files:** `analysis.d`, `grammar.d`.  
**Tasks:** report for each choice/repetition: FIRST status, BITES status, `NEXTBITES` status, proof theorem, reason/blocker, source location, and recommended backend candidate. Differentiate grammar *lint* from safe *optimization*. Integrate with `eligibilityReport` or a dedicated documented API without breaking existing consumers.  
**Tests:** JSON stability; direct and combinator backends; terminal/lookahead cases; unknown/effects; report explains why a cut was not emitted.  
**Exit:** human-readable and machine-readable proofs an agent can audit before trying P/L optimizations.

## 6. Runtime specialization — P milestones

### P1 — Localize action/effect barriers

**Files:** `analysis.d`, `grammar.d`, `peg.d` if needed.  
**Observation:** Current `scalarRules` and `directRule` checks can be blocked by grammar-wide `actionGrammar`; `RuleEffect` and optional pure-island support already exist.  
**Tasks:** use sound per-rule effects to enable direct/scalar pure regions inside mixed grammars; preserve tree fallback when actions/tracing require it. Reuse pure-island machinery where possible.  
**Tests:** pure header/actionful body/pure footer; action indirectly reachable through a reference; action behind predicate; trace enabled; parameterized, left-recursive, and unknown cases.  
**Benchmarks:** mixed grammars with tiny pure rules plus actionful parent, modes separated; report eligibility gain and code-size costs.  
**Exit:** no semantics change, measurable reduction in execution cost where pure subrules dominate.

### P2 — Expand direct lowering one operator at a time

**Files:** `grammar.d`.  
**Tasks:** identify most frequent `directFallback=root-combinator` reasons from A3, select **one** wrapper/terminal shape per PR, emit direct cursor code with correct failure/capture contract.  
**Tests:** successful, failed, nested/backtracked, output and diagnostic modes for each new shape.  
**Exit:** fallback count decreases with parity; report cost/gain after each subtask.

### P3 — Emit certified two-byte (later bounded-k) dispatch

**Files:** `grammar.d`, `peg.d`.  
**Tasks:** consume F4 plans to generate nested switch/table code, correctly handling EOF and earlier successful alternatives. Never infer a safe dispatch from FIRST overlap alone; consult proven guards when available.  
**Tests:** truncated prefixes, shared two-byte prefixes, lookahead, nullable branches, rollback and capture output.  
**Benchmarks:** lexer-like short operators and long repeated decisions against handwritten references.  
**Exit:** positive speed and limited code-size growth; retain fallback.

### P4 — Remove proven-unnecessary checkpoints

**Files:** `grammar.d`, `records.d`.  
**Tasks:** detect deterministic regions with no speculative retained output; avoid redundant checkpoint/restore while preserving compact record and failure contracts.  
**Tests:** nested choices, repeated optional captures, rollback at EOF, branch failure after partial output, resource exhaustion.  
**Benchmarks:** `output_modes` and repeated-branch grammar; compare allocations/rollbacks separately from release timing.  
**Exit:** equal records/failure data and measurable decrease in checkpoint work.

### P5 — Scalar internal calling convention

**Files:** `grammar.d`, `peg.d`.  
**Tasks:** extend existing `_cursor_*` and scalar recognition mechanisms for proven capture-free call chains to reduce `Node` construction/conversion. Keep ABI/public entry points and tracing output unchanged.  
**Tests:** deep call chains, recursive non-left-recursive calls, failure and EOF, trace enabled, capture boundary.  
**Benchmarks:** deeply nested short tokens; code-size/compiler-time accounting.  
**Exit:** lower overhead on call-heavy workloads without losing diagnostics.

### P6 — Scanner specialization and DFA representation

**Files:** `dfa.d`, `grammar.d`.  
**Tasks:** profile existing DFA loops; experiment separately with literal scanning, contiguous ASCII character classes, delimiter scans, compressed byte classes, and sparse vs dense transitions. Do not assume vectorization is inherently faster.  
**Tests:** empty input, long runs, escapes, Unicode/malformed UTF-8, boundary lengths, backtracking after successful scanner.  
**Benchmarks:** `lex_ascii`, `lex_utf8`, comments, strings; throughput, binary size and compile time.  
**Exit:** choose by measured gain and maintain a generic DFA fallback.

### P7 — Explain/select memoization

**Files:** `analysis.d`, `grammar.d`, `peg.d` reports.  
**Tasks:** profile repeated `(rule,position)` calls and memory pressure; produce recommendations for memoized, selective, nonmemoized and left-recursion-required rules. Keep behavior unchanged; avoid disabling memo in rules needed for correctness or complexity guarantees.  
**Tests:** repeated failures at same offset, nested lookahead, indirect left recursion, no-backtrack deterministic rule, output snapshots.  
**Exit:** credible profiling report and explicitly opt-in settings for trials.

### P8 — Recognize iterative expression patterns

**Files:** `analysis.d`, `grammar.d`, tests.  
**Tasks:** identify a small class of left-associative arithmetic-expression forms that can be lowered to loops/precedence climbing. **Recognition only first**; tree/record associativity and semantic action order require separate proof and implementation.  
**Tests:** subtraction associativity, precedence, parentheses, malformed trailing operator, deep nesting, recursion-limit behavior, output parity when enabled.  
**Benchmarks:** deeply nested and operator-dense `nested_expr` inputs against equal-output handwritten Pratt/recursive-descent parser.  
**Exit:** proof-scoped opt-in; no generic left-recursion rewrite.

## 7. Extracting LL/LR-compatible grammars — L milestones

**Important:** PEG ordered choice `/` and greedy repetition are **not** CFG alternation and repetition. A mere parse table built after rewriting operators does **not** certify language equivalence. For instance, `('a' / 'ab') 'c'` and `'a'* 'a' eoi` behave differently under naive PEG/CFG readings. BITES disjointness proves specific non-hiding/commit properties; it does not alone prove arbitrary CFG extraction. Reference: Mascarenhas, Medeiros, Ierusalimschy, [*On the Relation between Context-Free Grammars and Parsing Expression Grammars*](https://arxiv.org/abs/1304.3177) (2014 journal version; LL(1) and related sufficient translation classes).

### L1 — A proof-carrying conversion contract

**Files:** `analysis.d` and new cold analysis module only if code size warrants.  
**Tasks:** define region classification `{certifiedLL1, boundedLookaheadCandidate, CFGCandidateUnproven, PEGOnly, unknown}` and precise assumptions: no unaccounted lookahead behavior, no observable actions/side effects, safe greedy repetition, ordered-choice disambiguation, and full-input language contract. Incorporate F2 and B4/B5 certificates where relevant; separately document how the published **CFG→PEG** equivalence results can and cannot justify **PEG→CFG** extraction.  
**Tests:** known LL(1), predicate-aware lookahead safe/unsafe, prefix capture, greediness, nullable alternatives, left recursion, actionful and unsupported nodes.  
**Exit:** report-only proof checker with explicit witnesses/blockers and no false claimed equivalence.

### L2 — Export conservative certified CFG/EBNF

**Files:** cold grammar emitter.  
**Tasks:** emit a human-readable CFG/EBNF only for certified regions, retaining the original source rule IDs and proof metadata. For general PEG regions emit a separate `not-convertible/unknown` entry rather than pretending to translate them.  
**Tests:** roundtrip of eligible grammars, rejected unsafe prefixes/greedy repetition, correct nullable rules and EOF constraints.  
**Exit:** inspectable text/JSON output plus differential acceptance checks on finite test corpora (empirical checking is *additional* evidence, not a proof).

### L3 — Dedicated LL(1) backend

**Files:** `grammar.d`, optionally new small backend module.  
**Tasks:** compile only certified regions to table-free or small-table recursive descent, preserve output-mode contracts, and allow ordinary PEG fallback for uncertified rules.  
**Tests:** nested certified regions, rule-to-PEG fallback, output captures, failure recovery/diagnostics, mixed grammar with actions.  
**Benchmarks:** `choices`, `structured`, `output_modes`, alongside existing direct backend and handwritten baseline.  
**Exit:** a separately selectable LL backend before any default rollout.

### L4 — LL(k)/LL-regular experiment

**Files:** analysis/compiler.  
**Tasks:** use F4 bounded-prefix proof and, where applicable, a small DFA that classifies lookahead languages without consuming input. Include overlap and prefix-end handling. Investigate strong-LL(k)/LL-regular sufficient transformations as research tasks, not assumed results for arbitrary PEG rules.  
**Tests:** common-prefix operators, keyword boundaries, ambiguous prefixes, EOF, lookahead effects and hidden alternatives.  
**Benchmarks:** explicit multiple-prefix families, predictive DFA size/build time.  
**Exit:** only enable for certified rules with demonstrable advantage over existing `predictiveChoice` and DFA paths.

### L5 — LR(1) conflict analysis on certified CFG subset

**Files:** separate cold analysis module.  
**Tasks:** construct canonical LR(1) items and ACTION/GOTO/conflict reports for **L2-certified CFG only**; optionally investigate LALR(1) compression once correct. LR conflict freedom by itself does not establish PEG equivalence.  
**Tests:** no-conflict grammar, shift/reduce conflict, reduce/reduce conflict, nullable productions, precedence expression grammar, unsupported PEG predicate.  
**Exit:** report-only LR(1) analyzer with bounded state count.

### L6 — Optional LR or hybrid runtime backend

**Prerequisite:** L5 plus demonstrated workloads where LL/direct cannot compete. Split into scanner, parse table, stack/value construction, and hybrid-call bridge milestones before coding.  
**Tests:** all A4 parity modes, long inputs, failure offsets, left recursion, no cross-boundary action side-effect differences.  
**Benchmarks:** apples-to-apples handwritten LR/Pratt vs generated LR vs existing PEG; account for table/build/code size.  
**Exit:** keep experimental unless convincingly faster and fully equivalent.

## 8. Weighted grammar generation, fuzzing, and benchmark corpora — G milestones

**Fundamental rule:** Walking a PEG's syntax tree does **not** guarantee acceptance because of prioritized choice, greediness, lookahead, and semantic conditions. The **actual parser is the acceptance oracle**, and a generated “valid” sample must be checked for **full-input** acceptance. A generator may legitimately fail to produce a candidate under its budget; it must report failure, not emit an invalid candidate as valid.

### G1 — Seeded bounded candidate generator

**Files:** new cold generation module; tests alongside source.  
**Tasks:** deterministic documented PRNG, string/character-class terminals, sequence, ordered-choice proposals, optional/repeat proposals, recursion/output/attempt budgets. Start with action-free grammars. Repeat distribution should explicitly allow empty and skewed lengths. Reject unknown/unsupported constructs or use controlled oracle-based fallback.  
**Tests:** same seed yields same candidates, differing seeds explore branches, recursion hard stop, nullable loop prevents non-progress, EOF handling, UTF-8 roundtrip.  
**Exit:** reproducible candidate stream; no assertion that candidates are necessarily accepted yet.

### G2 — Full PEG acceptance oracle

**Files:** generator and existing parsing APIs.  
**Tasks:** parse each candidate with the actual grammar from the designated start rule, require full-input success, retry on rejection, and return explicit exhausted-budget/unsupported status. Avoid evaluating user-defined actions with side effects in testing unless user explicitly opts in and effects can be isolated.  
**Tests:** `('a'/'ab') 'c'` candidate trap, `'a'* 'a' eoi` impossible branch, lookahead, a valid disjoint grammar, budget exhaustion.  
**Exit:** every sample reported as valid is independently accepted by the reference parser.

### G3 — Coverage-guided grammar generation

**Files:** generator, A2 metrics adapters.  
**Tasks:** collect coverage from **actual successful parses**, not merely branches selected by the generator; bias toward undercovered alternatives and rare repeat depths. Track unreachable/unknown coverage separately.  
**Tests:** exercised-vs-proposed branches differ, rare alternative under weighted choices, timeout under unreachable branch, fixed-seed reproducibility.  
**Exit:** coverage report and reproducible corpus.

### G4 — Weighted choice and repetition policies

**Files:** generator + external policy config.  
**Tasks:** per-alternative weights, optional probability, repeat-length histograms/distributions, token length policies, recursion attenuation and explicit output budgets. Keep weights **outside** grammar syntax initially. Normalize and validate policy; zero weights should mean disabled only when permitted.  
**Tests:** deterministic samples, malformed negative/NaN weights rejected, zero-weight branches, long-tail repetitions, output-length budget.  
**Exit:** configurable generation with observable policy metadata.

### G5 — Learn approximate weights from representative corpora

**Files:** tracer/statistics helper.  
**Tasks:** parse real inputs and count actual successful alternatives, rule/context frequencies, token lengths, repetition counts, depth distributions. Optionally collect conditional context (parent rule, previous token class); do not claim independent marginal statistics perfectly reproduce real distributions. Keep provenance and sampling bias notes.  
**Tests:** synthetic corpus with known weights, escaped/invalid input ignored with correct status, replay reproducibility, no action-side effects in measurement.  
**Exit:** exported model that G4 can load; holdout comparison of generated vs real length/depth/branch histograms.

### G6 — Invalid mutation, differential fuzzing, and shrinking

**Files:** tests/generator and corpus utilities.  
**Tasks:** mutate valid samples near delimiters, keywords, lookahead boundaries, UTF-8 sequences, and EOF; retain **oracle-verified invalid** samples. For any backend mismatch, shrink while maintaining the mismatch and save input, grammar, seed and build modes. Combine with uniformly random bytes to explore malformed cases.  
**Tests:** intentionally seeded backend mismatch minimized; valid mutation still valid must not be mislabeled; invalid UTF-8 and truncated EOF; iteration/time budget; deterministic replay.  
**Exit:** versioned regression seeds and A4 CI integration.

### G7 — Representative benchmark corpus generator

**Files:** `performance/corpora/`, generators, workload registry.  
**Tasks:** materialize seeded small/medium/large inputs with checksum and weight-model provenance, valid/invalid mix, recursion/length distributions and occasional adversarial outliers. Include at least one real corpus family where licensing and privacy permit. Ensure grammar-generated benchmarks are **not the only** benchmark input; avoid tuning to the generator alone.  
**Tests:** full-acceptance validity check, checksum/reproducibility, size budget, synthetic vs holdout histograms, output parity across backends.  
**Exit:** reproducible benchmarks with truthful “synthetic learned from corpus” vs “real” labels in the performance dashboard.

## 9. Advanced experiments — X milestones (not first-line tasks)

### X1 — Vectorized delimiter and character-class scanning

Only start if P6 profiling shows scanning, not capture or dispatch, dominates. Add scalar reference tests for lengths around vector width, alignment, EOF and malformed UTF-8. Compile with documented CPU feature requirements; runtime fallback must remain safe on other CPUs. Record throughput, build size, and portability costs under `performance/milestones/X1/`.

### X2 — Joint lexer/predictive-parser specialization

Combine certified token patterns and deterministic region dispatch while preserving PEG lexical boundaries, choice semantics, actions, and output modes. Divide into at least: (a) analysis-only token-boundary certification, (b) generated recognizer, (c) compact-record/tree support. Benchmark against both current DFA fusion and handwritten lexer+parser.

### X3 — Offline cost-model/autotuning

Use results in `performance/` to choose between direct, DFA, predictive, memoized, LL, and specialized scanner implementations per rule. Never gather microbenchmarks during production parsing. Freeze decisions by profile/target architecture; fall back conservatively when the profile does not match. Guard against compilation time/code-size blowup and overfitting to synthetic inputs.

## 10. Standard acceptance checklist for every milestone

A milestone is **complete** only when all applicable checks are true:

- [ ] Scope and dependencies were respected; no unrelated refactor.
- [ ] Existing API behavior and old tests remain correct.
- [ ] Multiple new focused tests cover at least success, failure, edge/unknown and (for transformations) rollback/output behavior.
- [ ] Colocated unit tests and timed/memory-bounded integration tests satisfy `AGENTS.md`.
- [ ] DMD/LDC, `dfmt`, `@nogc`/`-vgc`, coverage (>90% for required modules), sanitizer and leak checks were run, or every unavailable check is explicitly recorded as **not run**.
- [ ] A4 differential tests pass in each applicable recognition/compact/tree mode, including diagnostics where required.
- [ ] The static correctness justification names exact assumptions and fallbacks; reports never turn `unknown` into `proved`.
- [ ] Relevant new benchmarks and corresponding fair handwritten baselines exist; new features add positive and adversarial workloads.
- [ ] Raw and summary results, machine metadata and correctness status are written in `performance/milestones/<ID>/<run-id>/` (or baseline area for A1). **Never replace previous raw runs.**
- [ ] `performance/latest.md` and `performance/trends.csv` are updated using real measured data; if no run occurred they say so.
- [ ] No reproducible unacceptable regression is hidden by a faster mean; compile time and code/memory changes are reported.
- [ ] Final agent report lists files changed, commands used, pass/fail/not-run results, benchmark links, ratios, open issues and commit ID.

### Exact final milestone report template

```text
Milestone: <ID — title>
Commit: <hash>              Dirty working tree: <yes/no>
Files changed: <paths>
Correctness rationale: <invariant and proven preconditions>
Fallback/unsupported: <conditions>
New unit tests: <names; count; result>
New integration tests: <names; count; result>
Cross-backend differential tests: <count; seeds; result>
DMD: <pass/fail/not-run + command>
LDC: <pass/fail/not-run + command>
Coverage / dfmt / -vgc / ASan / LSan / Valgrind: <statuses>
Performance results: performance/milestones/<ID>/<run-id>/
Comparability: <same input/mode/compiler/host? details>
Affected workloads: <IDs>
Median slowdown before -> after: <each affected workload or summary>
Workloads <=1.5x before -> after: <n/total; percentage>
90th percentile slowdown before -> after: <values>
Largest regression: <workload; delta; disposition>
Parser generation / compile time / binary size / RSS: <deltas or N/A>
Known blockers / next milestone: <items>
```

## 11. Agent startup instructions

1. **Read `AGENTS.md` and inspect the actual repository.** Locate compiler commands, test runners, benchmarks, handwritten parsers, existing output modes and generated-code entry points. Do not assume unseen files exist.
2. Begin **A1** unless an equivalent, reproducible `performance/` system already exists. If one exists, adapt it to the output contract rather than duplicating it.
3. Establish **A4** before any proof-driven optimization. A2/A3 can proceed in parallel only if the local agent's work isolation and merge testing are reliable.
4. Finish **F1–F3** before starting **B1–B8**. Read Redziejowski's paper directly; prioritize **B1 → B2 → B3 → B4 → B5** before a BITES-based cut. Do **not** treat the user's request as permission to substitute BITES for the fast existing FIRST-byte machinery.
5. After foundations, prefer **P1** and the best profile-supported P milestone. Evaluate BITES-enabled fast paths only after the corresponding theorem conditions, A4 parity, and `performance/` measurements are in place.
6. Track changes in the ≤1.5× workload count, p90 slowdown and worst regressions. If progress stalls, add an isolating benchmark **before** broadening the optimization.
7. Pursue certified LL extraction and generation/fuzzing on isolated branches after the critical correctness/measurement work. Split larger milestones before implementation.
8. At the end of every session, leave the repo in a reproducible state and update a small progress section in `performance/latest.md` or the repository's existing task tracker. Never mark the next milestone complete merely because its design is written.

## 12. Research references

1. Roman R. Redziejowski (2011). **BITES Instead of FIRST for Parsing Expression Grammar.** *Fundamenta Informaticae* 109(3), 323–337. DOI: [10.3233/FI-2011-514](https://doi.org/10.3233/FI-2011-514). Full text: <https://www.romanredz.se/papers/FI2011.pdf>. **Primary technical source for B1–B8; use its proofs and stated restrictions.**
2. Fabio Mascarenhas, Sérgio Medeiros, Roberto Ierusalimschy (2014). **On the Relation between Context-Free Grammars and Parsing Expression Grammars.** *Science of Computer Programming* 89, 235–250. <https://arxiv.org/abs/1304.3177>. Relevant to qualified CFG/PEG equivalence and LL-family transformations.
3. Bryan Ford (2004). **Parsing Expression Grammars: A Recognition-Based Syntactic Foundation.** POPL. <https://bford.info/pub/lang/peg/>. Foundational operational semantics.
4. Bryan Ford, PEG/packrat bibliography: <https://pdos.csail.mit.edu/~baford/packrat/>. Reference index for selective packrat and left-recursion work.
5. Sérgio Medeiros, Fabio Mascarenhas, Roberto Ierusalimschy (2014). **Left recursion in Parsing Expression Grammars.** *Science of Computer Programming* 96, 177–190. <https://doi.org/10.1016/j.scico.2014.01.013>. Background for distinguishing classical PEG proofs from implementations supporting left recursion.

---

**Success is not “all optimizations implemented.”** Success is a demonstrably correct, reproducible improvement in equal-output workloads, with the count at ≤1.5× increasing, worst cases becoming tractable, and conservative PEG semantics preserved for everything that cannot be safely specialized.
