# B04 — Independent packrat-cost hypothesis: NO_CHANGE

The conditional second optimization is **closed without a parser patch**. The independent hypothesis was that remaining broad cost came from memo lookup, bucket traversal or seed growth, as suggested by B02's PEG/Arithmetic descriptions. The actual default gate emits **zero memoized rules and zero left-recursive rules across all six grammar families**. Eliminating all memo lookup/rehash work therefore has a **0% latency-reduction ceiling and 0/513 observation coverage** for these fixtures. There is no before/after candidate timing to report because no such operation is active. This is a negative applicability experiment, not an optimization win.

## Source evidence and forecast

`python3 scripts/b04_eligibility.py` extracts the exact six grammar strings from the maintained benchmark adapters and calls the production `eligibilityReport!(Memoization.selective)` frontend/emitter under the combinator backend. `B04-eligibility.json` retains definitions, full reports, generated diagnostic source, compiler command and source hashes.

| Grammar | Rules | Memoized | Left recursive | Conservative |
|---|---:|---:|---:|---|
| BenchArithmetic | 7 | 0 | 0 | false |
| BenchCSV | 3 | 0 | 0 | false |
| BenchNumbers | 3 | 0 | 0 | false |
| BenchPEG | 26 | 0 | 0 | false |
| JSON | 12 | 0 | 0 | false |
| Ambiguous | 1 | 0 | 0 | false |

All maintained gate adapters select `Memoization.selective`. `grammar.d` computes `cache` from the memo policy, conservative/left-recursion facts and grammar/rule parameters; record selectors do not alter that decision. The audited definitions have no grammar/rule parameters. This establishes absence of packrat calls for all gate selectors and output modes, rather than merely failing to see a symbol in a profile.

Amdahl forecast: the targeted operation fraction f is zero; even infinite local speedup gives overall speedup 1/(1-f)=1.0. No H04 memo bypass is reintroduced. B03's rejected growth outlining is not retried. B02's claims of iterative packrat ascent in the Arithmetic gate and heavy packrat lookup in PEGGrammar are unsupported for these actual fixtures. The arithmetic definition is iterative precedence parsing, with right recursion for parentheses/unary expressions. Its behavior is not the experimental X03 left-recursive workload.

This correction also establishes that the current default gate cannot activate shared-output snapshots: generated eligibility requires a selected left-recursive subtree. It does not establish that shared output is useless to callers outside this gate. Likewise, the gate has no action-bearing grammars, and runs the combinator backend; the direct/action pure-island feature does not accelerate this default policy. Preserve both opt-in modes and their budget guards.

## Separate diagnostic instruction profiles

`python3 scripts/b04_profile.py` collected 18 Callgrind profiles from the source-matched B03 baseline binary, after verifying every production/parser and benchmark source hash against `B03-before-gate.json`. Five representatives cover all three output modes: PEGGrammar.ManyRules, CSV.Flat, Arithmetic.Flat, JSON.WhitespaceHeavy and Numbers.BinaryLong. Controls are Ambiguous.Retry validation, CSV.SingleLine validation and JSON.InvalidTruncated spans. Complete compressed profiles, annotated self-instruction counts, raw benchmark JSON and Valgrind logs are retained in `B04-profiles/`. The manifest records exact commands, binary/source hashes and compiler flags.

Each invocation uses 100 iterations, one warmup batch, seven recorded batches, a 60-second timeout and 4 GiB address-space ceiling. Both handwritten and generated acceptance/hash/counts are checked. These are **instrumented diagnostic instruction counts**, including parity checks, both engines, runtime and harness work. They are not performance measurements, CPU-cycle fractions or valid causal Amdahl fractions. Full uninstrumented gate evidence remains B03's before gate; no instrumented speed claim is made.

The out-of-line memoizedRule function contributes zero self instructions in all profiles, consistent with the stronger emitted-policy proof. Selected `RecordBuffer.openKind` self-instruction shares of the **whole program** illustrate the difference between B02's fitted node coefficient and an observed site:

| Representative | Spans | Tree |
|---|---:|---:|
| PEGGrammar.ManyRules | 3.93% | 12.20% |
| CSV.Flat | 6.31% | 6.33% |
| Arithmetic.Flat | 8.37% | 17.00% |
| JSON.WhitespaceHeavy | 0.08% | 0.11% |
| Numbers.BinaryLong | 0.05% | 0.05% |

These shares exclude costs in inlined callers and callees and cannot prove that materialization is cheap. They show why a single per-node regression coefficient cannot justify a fixed gate-wide speed forecast. Top profile entries include existing `predictiveChoice` and sequence/repetition wrappers (CSV/PEG), generated Space/Identifier rules (Arithmetic), and the generated JSON spacing scanner. B02's proposed choice-dispatch source site already performs predictive lowering. No new one-module algorithm with proven exact finite-budget/diagnostic semantics follows from these profiles. Broad emitter rewriting remains excluded by the plan; it would require a new independently justified design rather than another H08 variant.

## Disposition and reproducibility

- B04: **NO_CHANGE**, zero coverage for the independent memo-cost hypothesis; no production source changed.
- The complete 1.5× target remains unmet. Do not substitute the 5× ceiling or declare Phase 3 successful.
- C03 is gate-irrelevant under current definitions; X07 is deferred because there is no left-recursive expression-chain output in the actual gate. C01/C02 and D01/D02 remain validation/policy work for opt-in callers.
- Future optimization work should first obtain site-specific native latency evidence for generated control flow/scanning with exact finite-budget/failure semantics. The existing B02 coefficients do not supply that proof.

Commands:

```sh
python3 scripts/b04_eligibility.py
python3 scripts/b04_profile.py
```

The profile script resumes completed, hash-bound diagnostic artifacts; it never treats a lock or partial output as a running process. Fresh reproduction requires the preserved baseline `build/B03/before-runner` or an identically source-matched build, supplied with `--binary`, `--gate` and its explicit `--binary-sha256` when different from the preserved B03 baseline. The first profiling attempt used a substring filter `CSV.Empty` that also selected CSV.EmptyQuoted; the harness rejected the unexpected corpus. It was replaced with the unambiguous CSV.SingleLine control. Completed profiles were retained and verified, not rerun. No candidate code, coverage assertion or hook/commit claim is associated with this measurement-only milestone.
