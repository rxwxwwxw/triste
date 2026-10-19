# C03 — Shared-output optimization deployment decision

Disposition: **DEFERRED_GATE_IRRELEVANT; conditional branch closed.** Keep R06 opt-in. No parser optimization or activation change is justified by the current gate. This is the deferral explicitly required by C03 when the measured recursive workload is not represented in the gate.

## Current-state audit

Reproduction:

```sh
python3 scripts/c03_decision.py
```

The decision script checks the current source against B04's actual emitted-policy audit, verifies C01's 72 raw CSV/tuple pairs, verifies C02's compiler transcripts and decision, and records evidence SHA-256 values in `C03-decision.json`. It does not rerun benchmarks or present diagnostic timing as a new gate result.

Base revision is `dcf6b1bbdef83a856d231b0f2a86f3afc9aa33af`. All core parser modules and timed gate adapters remain source-matched to the saved B03 baseline. Four diagnostic benchmark files changed in C01/D01 (shared-output and pure-island fixtures, plus P09/P13); none is compiled by the official `scripts/benchmark.sh` runner. This is a provenance check, not a claim that the whole worktree equals the historical checkout or that E01 has already run.

## Gate relevance

The six actual gate grammar families have zero left-recursive rules under the maintained selective policy: BenchArithmetic (7 rules), BenchCSV (3), BenchNumbers (3), BenchPEG (26), JSON (12), Ambiguous (1). These are production frontend/emitter facts retained in `B04-eligibility.json`, not name-based estimates from B02.

`grammar.d` requires a selected left-recursive subtree for generated shared-output eligibility. With no left-recursive rule, that predicate is false for every selector. Recognition additionally has no compact-record replay obligation. Ordinary finite limits and default opt-in settings are separate barriers to activation; removing those guards would not create a selected recursive subtree in these grammars.

| Saved B03 gate mode | Observations | Above 1.5× | Eligible for shared replay |
|---|---:|---:|---:|
| validation | 171 | 134 | 0 |
| spans | 171 | 144 | 0 |
| tree | 171 | 146 | 0 |
| Total | 513 | 424 | 0 |

There are 171 unique case/output obligations. These numbers describe the explicitly named saved B03 baseline (89/513 within target), not a fresh current-worktree timing run. Zero active shared replay is proved by API/emitted eligibility; there was no new instrumented full-gate counter measurement.

The affected fraction for optimizing the active shared replay algorithm alone is therefore f=0. Amdahl's bound is `1/(1-f)=1.0`: even eliminating all of that algorithm's work changes none of these gate observations. This does not rule out a distinct optimization of ordinary flat record materialization; B03 already evaluated and rejected one such hypothesis.

## C01/C02 implications

C01 established genuine active synthetic benefits with matching output and nonzero snapshot/replay counters. Dense successful 2048-term chains measured approximately 0.39–0.41× flat latency, while snapshot copying shrank and replay materialization bytes stayed unchanged. These left-recursive fixtures are validation workloads outside the default gate. Their attractiveness is not gate coverage.

C02 established a concrete finite-memory incompatibility: at a 4119-byte scratch limit a flat 128-node snapshot succeeds, while the shared first snapshot needs 8215 bytes. The opposite memory effect appears after substantial reuse. Exact existing finite-memory accounting cannot be assumed from node parity. All public finite-budget tests correctly fall back, and general finite/default activation remains NO-GO. Step/depth equality on the tested unlimited fixtures is not a proof that allocator failures or an isolated finite-output proposal preserve all semantics.

Consequently neither a replay-materialization patch for the synthetic niche nor wider activation is part of C03. The production version gate, context opt-in, eligibility checks, trace/step/depth/memory/output guards, ownership behavior and 4096-byte snapshot threshold remain unchanged.

## Conditions for reopening

A subsequent C03 proposal needs an actual maintained workload with selected left-recursive output, a meaningful share of measured 1.5× failures, and observed nonzero shared operations. It must target one demonstrated remaining site, preserve exact outputs/parents, limits, ownership and failure behavior, and provide source-matched native timings and guarded controls. Any finite-policy proposal first needs the C02 proof obligations resolved; otherwise preserve unlimited opt-in operation.

No new correctness, sanitizer, coverage, compile-cost or full-gate pass is claimed for this decision-only milestone. Its input artifacts already contain the applicable C01/C02 tests. The ≤1.5× target remains unmet. D01 is the next validation milestone; E01 remains outstanding.
