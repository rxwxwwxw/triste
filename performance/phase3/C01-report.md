# C01 — Active shared-output crossover

Disposition: **COMPLETE — measurement only; keep shared output opt-in.** Main matrix and all four legacy compiler/activation checks passed. No parser source, activation guard, limit or threshold changed.

## Configuration and repairs

Base revision: `dcf6b1bbdef83a856d231b0f2a86f3afc9aa33af`. All `src/` hashes remain identical to B03/B04. Exact dirty-worktree benchmark hashes, compiler version/flags, binary hashes, build logs and invocation hashes are in `C01/manifest.json`; the independent DMD and legacy manifests retain their own configurations.

The authoritative crossover harness is `benchmark/diagnostics/shared_output.d`, driven by `scripts/c01_shared_output.py`. The fixture now reports finite-budget policy, generated eligibility and selected activation policy, adds an expression-only projection between dense and root-only output, emits exact diagnostic tuples, and separates a warmup batch. Metrics and timing are separate binaries. The diagnostic tuple output occurs inside instrumented batches; its clock values are never used for speed claims.

P09/P13 required two activation repairs: explicit unlimited ParseContext **and output** budgets, and compilation with the actual record selector so the generator emits shared-output eligibility. P09 now instantiates a projection for each selector. Both legacy harnesses reject builds missing `NPeggedSharedOutput`, compare exact status/end/failEnd/record tuples against flat output, and require nonzero operations on large targeted cases. P09 resource failures abort instead of printing a misleading 1.0 ratio. P13's old mean is labeled as construction-only, not a median or end-to-end measurement. Its instrumented clocks are not used as crossover evidence.

The primary matrix uses combinators, selective memoization, `OwnInput=true`, no trace, the existing 4096-byte snapshot threshold, and no flat-specialization version. Three selector configurations are all rules, expression-only, and root-only. Flat and shared-compiled binaries are compared; shared-compiled binaries run both request-off and request-on policies.

Active runs explicitly set step/depth/memory/output to `size_t.max`. The additional finite matrix uses the unchanged defaults (10,000,000 steps, depth 1024, 256 MiB memory and output), with recursive sizes through 128 so these are successful/rejected parsing controls rather than resource-exhaustion tests. These rows are labeled **inactive**, even though sharing is requested. Boundary/resource-exhaustion semantics remain C02 work.

## Measurements and parity

The main matrix comprises 12 optimized LDC binaries, 72 invocations and 22,968 observations. Each binary was built explicitly; its actual hash and full flags are stored. All builds finish before timing. Native timing uses CPU 0, shuffled invocation order (seed 101), three repetitions, seven recorded batches, four parses per batch, one additional warmup batch, and destruction inside the clock. Comparators have identical selectors, owned-input copies and output/failure obligations. Compilation may overlap two at a time; native timing never overlaps builds.

[Curves](C01/crossover.svg) show success and late failure for direct/indirect left-recursive output chains and sibling groups, at all three selection densities. The matrix also includes nested depth 0–8 and ineligible JSON/CSV/PEG controls. Chain sizes 16–2048 sweep selected left-spine depth; siblings span 16–512 groups.

Every diagnostic tuple sequence (kind, begin, end, parent), status and end/failEnd matches across flat, request-off and request-on builds, for every selection/budget configuration. Native output fingerprints/counts also match. Inactive paths have identical allocator calls, requested bytes and reserved bytes to their matched reference. All finite controls and all root-only/ineligible controls have zero shared snapshots, frozen/reused nodes and replays. DMD with assertions enabled independently matches LDC's 116 dense active/fallback case transcripts and **every non-timing CSV field**; owned-input assertions pass.

The reported `policy_selected` field is derived from the generated eligibility member, compile version, request and exact public budget guards. It is not a new core instrumentation counter. Positive shared-operation counters independently establish actual work above threshold. In builds without the shared version, `grammar_eligible=0` means the version-specific eligibility member is absent, not that the grammar could never be eligible in a shared build.

## Crossover and activation results

Ratios are median paired-run ratios of per-run median batch ns/parse. Lower is faster. Ranges below are the three run ratios, not confidence intervals. Seven within-run samples do not create seven independent machine trials. Small/noisy cases are not relabeled as optimization wins.

| Dense success workload | Size | Request-on / flat | Three-run range | Shared snapshots | Shared replays |
| DirectChain/flat | 16 | 1.054 | [1.009, 1.054] | 0 | 0 |
| DirectChain/flat | 64 | 1.038 | [0.972, 1.077] | 0 | 0 |
| DirectChain/flat | 128 | 0.380 | [0.378, 0.410] | 64 | 65 |
| DirectChain/flat | 512 | 0.350 | [0.295, 0.360] | 448 | 449 |
| DirectChain/flat | 2048 | 0.393 | [0.378, 0.419] | 1984 | 1985 |
| IndirectChain/flat | 64 | 0.448 | [0.435, 0.459] | 42 | 43 |
| IndirectChain/flat | 2048 | 0.405 | [0.393, 0.415] | 4010 | 4011 |
| NestedChain/siblings | 512 | 0.250 | [0.245, 0.252] | 496 | 497 |

For DirectChain dense output, 64 terms select the shared policy but exercise **zero shared snapshots**; the next sampled size, 128, exercises 64 snapshots and 65 replays. Expression-only DirectChain still has zero shared snapshots at 128 terms; at 256 it exercises 128 and has median latency ratio 0.376. Root-only is ineligible at every size. These are sampled crossover intervals, not proof of the exact latency-equality point or a newly tuned threshold. Final output node count is not the memo snapshot length, so a threshold assertion based only on final nodes is invalid.

Across all 68 unbounded case/shapes per projection, median ratios are 1.026 dense, 0.999 expression-only and 1.073 root-only. Thus the large recursive benefit does **not** establish a broadly applicable gain. Across the 48 finite fallback shapes, medians are 1.031 dense, 1.017 expression-only and 1.040 root-only; the individual median ranges are [0.980,1.110], [0.965,1.183] and [0.894,1.246]. These native differences include compiled-version/layout effects and shared-machine noise. They are not claimed to be zero overhead. See all request-off controls and run ratios in `C01/summary.json`.

A separate two-clock/four-consume microprobe measured a median 20 ns per batch (5 ns/parse equivalent; seven samples). It excludes real fingerprinting, arena setup and parsing and is only a harness-overhead estimate. Nothing is subtracted from measured latency. The generated probe source, exact commands and raw samples are retained in `C01/harness-overhead.*`.

## Copying versus replay/materialization

Per-parse metrics for dense, successful 2048-term chains:

| Grammar | Flat snapshot bytes | Active snapshot bytes | Flat restore bytes | Active restore bytes |
|---|---:|---:|---:|---:|
| DirectChain | 134,217,728 | 262,112 | 134,348,768 | 134,348,768 |
| IndirectChain | 402,522,112 | 371,296 | 402,718,656 | 402,718,656 |

DirectChain exercises 1,984 shared snapshots, 1,985 replays and 4,186,113 reused nodes. IndirectChain exercises 4,010 snapshots, 4,011 replays and 12,567,213 reused nodes. Snapshot allocation/copying shrinks dramatically while replay still materializes the same node bytes. `restore_bytes` includes actual shared flattening, and `growth_copy_bytes` is separate. These counters separate work categories; they are not stage latency or causal percentage measurements.

## Historical conclusions and disposition

The historical P09 2.16× DenseChain crossover claim and P13 threshold-tuning claims were measured with inactive configuration and remain invalid as active-path evidence. Do not transfer their numbers to these workloads. The new source-matched, counter-proven matrix supports a narrower conclusion: existing opt-in sharing helps sufficiently large selected left-recursive outputs, but does not eliminate replay materialization, does not prove gains on small/root/flat cases, and remains inactive under ordinary finite policies. The repaired historical density fixtures provide activation/parity checks, not independent uninstrumented speed claims for their original exact case labels.

B04 established that all six default gate grammars emit zero left-recursive rules. These synthetic opt-in gains therefore do not move the current default 1.5× distribution. Keep R06 opt-in and the 4096-byte threshold unchanged. C02 must establish finite-budget proof obligations before any activation change; C03 remains conditional on actual gate relevance.

## Reproduction and limits

```sh
python3 scripts/c01_shared_output.py
python3 scripts/c01_summary.py
python3 scripts/c01_legacy_check.py
```

The full primary run bounds each child to 4 GiB address space, compilation to 300 seconds and each invocation to 120 seconds. Its raw CSVs, exact tuple transcripts, manifests, source/binary/output hashes, build logs, complete combined observations and SVG are retained in `performance/phase3/C01/`. The legacy checks have the same memory ceiling and execution deadline and compare DMD/LDC activation counts. No core parser edit, relaxed budget, default change or performance promotion is part of this measurement-only milestone.

A DMD diagnostic build of the updated primary fixture (same source list as the main manifest) used `-defaultlib=druntime -nothrow -O -w -de -checkaction=halt -version=NPeggedSharedOutput -version=NPeggedMetrics`, with assertions enabled. It was run under both `NPEGGED_FINITE_BUDGETS=0/1` and `NPEGGED_SHARED_OUTPUT=1`, with a 60-second timeout and 4 GiB ceiling. `C01/dmd-validation.json` records those source hashes and comparison results.

All touched D files were formatted with dfmt. Source functions retain `@nogc nothrow`; DMD and LDC compile with warnings/deprecations treated as errors. No Phobos or manual resource ownership was added. No src coverage refresh, sanitizer run or staged hook is claimed for this benchmark-only change.
