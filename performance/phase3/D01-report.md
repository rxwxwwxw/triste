# D01 — Active pure islands and guarded fallback

Disposition: **COMPLETE — measurement only; retain specialized opt-in policy.** No parser source, default or activation guard changed. This benchmark-only milestone reproduces active entry gains and quantifies where they do not apply.

## Configuration and harness repairs

Base revision: `dcf6b1bbdef83a856d231b0f2a86f3afc9aa33af`. `D01/manifest.json` records exact dirty-worktree source hashes, LDC version/flags, every binary hash, build wall time/peak RSS and raw invocation hashes. Both comparator builds use the same direct action grammar, selective memoization and selected-output obligation; only `NPeggedPureIslands` differs. Metrics and native timing use separate binaries. DMD independently checks the expanded diagnostic fixture.

The maintained P07/H03-style fixture is `benchmark/diagnostics/pure_islands.d`; no separate `p07*.d` benchmark exists in the current tree. Its active cases already requested unlimited budgets. D01 adds traced fallback, uses the **actual ParseContext defaults** for finite controls (10,000,000 steps, depth 1024, memory 256 MiB, records output 256 MiB), expands the action-bearing entry across all output modes, and includes all observable action/trace fields in fingerprints. The historical H03 script's row counts and inactive-path classifier were updated for compatibility; its old saved measurements remain historical.

Active policy explicitly sets all applicable step/depth/memory/output limits to `size_t.max`, with no trace. The action grammar has pure Identifier/Whitespace/Root entries, plus an ActRoot that executes an action per identifier. The action callback records input, position, logical steps/depth and matches; the exact oracle also tests rejection, input replacement and budget mutation. Native ActRoot exercises the ordinary non-mutating action workflow, with one action per word, including failure after the words. This distinguishes pure entry points in an action grammar from entry points that actually execute actions.

Output modes remain separate:

- 0: recognition with borrowed input.
- 1: selected records with borrowed input.
- 2: selected records with an owned input copy.
- 3: owned full trees, including failed-child structure.

Three selections (all, root-only, identifier-leaf-only) expose projection-dependent eligibility. Normal JSON/CSV/PEG recognition controls retain their existing conventional grammar/backend policy and have no active pure-island entry. Full-tree mode and action-bearing ActRoot are controls, not presumed active optimizations.

## Correctness, activation and scope

The exact oracle completed **before native timing**: DMD and LDC × three projections × feature off/on = twelve builds. It compares status, success, end/failEnd, complete trees, every selected tuple/parent, action/trace events and finite-limit behavior. All feature pairs and cross-compiler transcripts match for each selection. The source-pinned command and transcripts are retained in `D01/oracle-manifest.json` and `D01/oracle/`. Generated executables were moved under `build/D01/oracle/`, not retained as performance data.

The main matrix uses twelve LDC binaries, 48 invocations and **42,768 rows**. Across both trace policies there are 972 unique selector/case/output/size/validity/limit configurations. Of these:

| Configuration group | Count | Measured entry condition |
|---|---:|---|
| Unlimited, untraced, eligible output | 132 | entries > 0, including invalid inputs |
| Default finite limits, untraced | 234 | entries = 0 |
| Tracing, finite or unlimited | 486 | entries = 0 |
| Other unlimited untraced controls | 120 | entries = 0 |

Counter builds use one parse, so these are actual operations per parse, not warmup aggregates. Selected pure entries must have nonzero counters; every fallback must have zero. The driver checks native and diagnostic fingerprints, output counts, end/failEnd, action count and trace count across every build/run. Guarded paths also match allocator calls and requested/reserved bytes. The summary independently asserts activation for **all** 132 eligible configurations, including failures.

The expanded all-selection diagnostic fixture also ran under DMD with assertions enabled. All 324 traced/untraced non-timing rows, including allocation and memo/entry counters, match LDC exactly. The oracle supplies exact structural parity rather than treating fingerprints alone as proof.

## Native measurement method

Native measurements use optimized uninstrumented LDC, CPU affinity 0, three independent repetitions and seven recorded batches per invocation. Feature-on/off invocations are paired closely, with pair/policy order shuffled (seed 10101). Each batch has 64 warmup parses then 256 timed parses for sizes ≤64, or 16 warmup and 16 timed parses for larger sizes. All benchmark compilation finished before timing; no verification compilation overlapped native timing. CPU governor was observed as powersave after the run; frequency was not locked or changed.

The clock includes each API call, input copying where required, result destruction, output/event fingerprints, effect-length reset and the observable sink. Caller ParseContext and Effects-buffer initialization occur outside the clock. These are matched API-work measurements, **not isolated parser-body latency**. Mode 3 fingerprints include complete tree input/matches/failed children; action/trace fingerprints include complete observable event fields. Those costs are common obligations in each pair and are not subtracted.

Ratios below one favor the opt-in build. The ratio is the median of three paired run ratios of within-run batch medians. Absolute columns below use the paired run at that median ratio, so the displayed latencies and ratio refer to the same run. Full per-run latency vectors, ratio ranges and sample standard deviations are in `D01/summary.json`. Three-run ranges are not confidence intervals, and seven inner batches do not constitute seven independent machine trials.

| Selection | Case | Mode | Size | Reference ns/parse | Opt-in ns/parse | Opt-in/reference | Entries |
|---|---|---:|---:|---:|---:|---:|---:|
| all | Identifier | 0 | 16 | 78.7 | 52.8 | 0.6709 | 1 |
| all | Identifier | 0 | 1024 | 575.5 | 455.9 | 0.7921 | 1 |
| all | Identifier | 2 | 16 | 149.5 | 110.0 | 0.7361 | 1 |
| all | Identifier | 2 | 1024 | 641.2 | 578.0 | 0.9015 | 1 |
| all | Root | 0 | 128 | 102253.2 | 293.1 | 0.0029 | 1 |
| all | Root | 2 | 128 | 103954.6 | 106121.8 | 1.0208 | 0 |
| root | Root | 2 | 128 | 100027.2 | 323.8 | 0.0032 | 1 |
| leaf | Root | 2 | 128 | 104563.8 | 9516.7 | 0.0910 | 258 |
| all | Root | 3 | 128 | 140911.1 | 137932.9 | 0.9789 | 0 |
| all | ActRoot | 0 | 128 | 170104.8 | 173096.8 | 1.0176 | 0 |
| all | ActRoot | 1 | 128 | 233130.4 | 232703.4 | 0.9982 | 0 |
| all | ActRoot | 2 | 128 | 246224.4 | 250034.8 | 1.0155 | 0 |
| all | ActRoot | 3 | 128 | 238067.8 | 235269.4 | 0.9882 | 0 |

Size denotes bytes for Identifier/Whitespace and words for Root/ActRoot. The enormous Root-recognition ratio is an eligible pure entry with no executed actions; it must not be transferred to full output or actual action-bearing parsing. Root-only records can use the whole-entry fast path; leaf-only records still emit every identifier. Leaf Root's 258 entries are actual hook operations in one parse, not 258 independent API calls.

[Active ratios](D01/active-ratios.svg) show the selected projection/input-size curves. Across the 132 eligible lab configurations the median ratio is 0.663, ranging from 0.00245 to 0.910. This is a deliberately selected synthetic applicability matrix, not a production traffic distribution or a whole-gate score.

Guarded paths do not establish zero overhead:

| Control group | Configurations | Median paired ratio across cases | Range of case median ratios | Cases >3% slower in all 3 runs |
|---|---:|---:|---|---:|
| Default finite, untraced | 234 | 1.002 | [0.895, 1.177] | 26 |
| Tracing | 486 | 1.012 | [0.922, 1.200] | 59 |
| Other unlimited untraced fallback | 120 | 1.000 | [0.927, 1.083] | 3 |

The last column is descriptive repeatability, not a multiple-comparison-adjusted significance test. Layout, extra fallback dispatch and shared-machine variation can affect these results. The data does not justify calling all guarded paths free or promoting the feature by citing only the favorable ~0.0025 Root case. Every individual control and three-run ratio remains in the summary.

A separate clock-plus-sink probe measured median overhead equivalent to 2.5 ns/call at 16 iterations and 0.746 ns/call at 256 iterations. It excludes parsing, fingerprinting and event work. Its source and raw samples are retained as `D01/harness-overhead.*`; nothing is subtracted from native latencies.

## Compiler / CTFE-inclusive cost

Whole timing-build costs (wall seconds include compiler CTFE, code generation and linking):

| Selection | Off seconds | On seconds | Off peak RSS KiB | On peak RSS KiB | Off binary bytes | On binary bytes |
|---|---:|---:|---:|---:|---:|---:|
| all | 46.71 | 48.51 | 895532 | 914252 | 924024 | 960152 |
| root | 47.05 | 47.80 | 899308 | 918548 | 924024 | 955624 |
| leaf | 48.11 | 49.26 | 900408 | 920192 | 924024 | 955776 |

Peak RSS is collected with `wait4` for each compiler process/descendants. There is no dependency on an unavailable GNU time binary. Two benchmark compiles overlap; the separate exact-oracle builds overlapped the early benchmark builds but finished before the timing barrier. These are single whole-benchmark build observations, not isolated/repeated CTFE phase measurements; do not interpret small wall-time deltas as a statistically established compile-time regression. The whole-source fixture includes the conventional examples and oracle grammar definitions, so this is not the marginal compile cost of one production rule. All twelve native/metrics build costs, hashes and logs are retained.

## Default-policy coverage and disposition

**0% of callers using the ordinary default ParseContext limits can enter this feature**, regardless of selected entry: activation requires all relevant limits to be `size_t.max` and no trace. That is a guard-based eligibility statement, not an estimate of how often unknown real callers override defaults. The measured finite-default and tracing controls confirm zero entries. The current default gate also uses ordinary policies and the combinator backend; B04's six-grammar audit does not supply a new population of action/direct eligible callers.

The 132 active cases are 27.2% of the chosen 486 untraced lab configurations (13.6% when traced variants are also counted). These fractions describe only this validation matrix. They must not be advertised as the eligible fraction of real traffic or of the 1.5× gate.

D01 therefore supports a specialized opt-in use case: proven pure entry/projection within a direct action grammar, with deliberate unlimited policies. Actual action-bearing ActRoot, complete trees, incompatible selected projections, finite limits and tracing remain fallback controls. No default/guard change, finite-budget parity claim, handwritten-target pass or performance promotion is part of this milestone. D02 must decide deployment feasibility separately.

## Reproduction and retained artifacts

```sh
python3 scripts/d01_pure_islands.py
python3 scripts/d01_summary.py
COMPILERS='dmd ldc2' MEMOS=selective PROJECTIONS='all root leaf' OUTPUT_DIR=performance/phase3/D01/oracle bash scripts/pure-islands-check.sh
bash scripts/d01_memory.sh
```

For the recorded run the exact oracle was launched while early benchmark compiles ran and completed before native timing. The oracle command can also run first, serially. Generated oracle executables were relocated under `build/D01/oracle`; raw transcripts/logs remain in `D01/oracle/`. Native runner compilation has a 300-second deadline, each invocation 120 seconds, and all children a 4 GiB address-space limit. The canonical oracle has its existing 45-second alarm, 60-second deadline and 4 GiB ceiling.

The independent DMD expanded-fixture command uses the main manifest's source list, `-defaultlib=druntime -nothrow -O -w -de -checkaction=halt -version=PureIslandsBenchmark -version=NPeggedPureIslands -version=NPeggedMetrics`, and trace environment 0/1. Assertions are enabled. Exact commands/hashes and resulting comparison checks are retained in `D01/validation.json`.

All touched D files are formatted with dfmt. Hot benchmark functions retain `@nogc nothrow`; both compilers treat warnings/deprecations as errors. No Phobos or parser ownership policy was introduced. No src coverage refresh, staged hook or whole default-gate rerun is claimed for this measurement-only milestone.

## Memory validation

The expanded all-selection fixture passed ASan/LSan and Valgrind under both trace policies. All 648 sanitizer/Memcheck case rows and 324 DMD rows have identical non-timing output, action/trace, allocation and entry/memo fields to the LDC diagnostics. Valgrind reports zero errors and zero definitely/indirectly/possibly lost bytes; 120 bytes remain reachable in druntime. ASan uses a 4 GiB physical-memory systemd scope with swap disabled; other runs use the 4 GiB address-space cap. Each run has a 120-second deadline. These checks cover this fixture, not the entire repository. Logs and binary/source hashes are retained.
