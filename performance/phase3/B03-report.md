# B03 — Outline record-buffer growth

Disposition: **NO_CHANGE**. The growth-outlining experiment failed the performance acceptance criteria. Production `src/npegged/records.d` is restored byte-for-byte; the rejected candidate is preserved in `B03-rejected.patch`. B03 is closed with negative evidence. The overall Phase 3 goal remains incomplete; B04 is next after review of this decision.

## Hypothesis and forecast

Test one change in `src/npegged/records.d`: move the existing allocation/copy branch of `RecordBuffer.put` into an explicitly non-inlined private helper. Keep status, overflow and parent validation, growth capacity, arena accounting, metrics and write ordering identical. The hypothesis is reduced code size/register pressure in the ordinary append path, rather than faster allocation or fewer allocations. Existing optimized assembly already inlines `put` into `openKind`; simply recommending inlining does not establish missing compiler optimization.

A03 has 420/513 observations above 1.5×, including 284 output-mode observations (143 spans, 141 tree). These 284 observations represent 67.2% of summed candidate ns/parse and 78.6% of summed positive target deficit. These are coverage ceilings, not attainable gains: full-tree parsing may use different emission paths and output cases also spend time elsewhere. If append work takes fraction f of candidate latency and is accelerated s-fold, total speedup is 1 / (1 - f + f/s). No measured f is yet available; B02 does not establish a 19.6% attainable reduction.

B02 provenance limitation: `scripts/two_dimensional_attribution.py` assigns failed probes heuristically from input names/lengths, fits existing end-to-end gate measurements, and hard-codes site-level deficit shares and improvement claims. It does not measure failed probes, DFA attempts, memo hits, output allocation/copy time, or parser-only latency. Its regression is a descriptive association and does not prove which source site causes cost. This experiment must stand on source-matched before/after results.

## Acceptance policy

Preserve the exact reference implementation for differential comparison. Test ordinary appends, growth, rollback/reuse, invalid parents, sticky failure and budget exhaustion. Run compiler compliance and semantic oracle before timing the candidate. Retain only with repeatable improvement across a substantial fraction of failing cases and no clear guarded-control regression. Otherwise restore production source and retain the rejected patch and raw evidence.

The official gate keeps its existing contracts and 1.5× threshold. B01 documents unmatched failure diagnostics and input ownership for some handwritten pairs; those ratios remain compatibility evidence, not proof of equivalent diagnostic/ownership work. Candidate versus baseline comparisons must use identical APIs and obligations.

## Execution

Base revision: `dcf6b1bbdef83a856d231b0f2a86f3afc9aa33af`.

Started baseline command:

```sh
python3 scripts/performance_gate.py --output performance/phase3/B03-before-gate.json
```

The gate uses optimized uninstrumented LDC, 2,000 iterations, one warmup batch and seven samples, three repetitions, all output modes and both suites. Its raw artifact records source hashes, build flags, compiler version, input lengths, selected output hashes/counts and absolute times. Initial gate is unpinned and engine order follows the existing runner; supplemental source-matched interleaving is needed for an acceptance decision.

## Results and decision

| Complete gate | ≤1.5× observations | Median ratio | Worst ratio | Text bytes | Build/export seconds |
|---|---:|---:|---:|---:|---:|
| Baseline | 89/513 | 2.226× | 5.611× | 3,146,449 | 109.17 |
| Rejected candidate | 112/513 | 2.101× | 5.566× | 3,156,369 | 105.87 |

These sequential unpinned gate results are insufficient for promotion. The candidate remains far from the actual target. The build times are single observations without isolated compiler-cost controls.

The supplemental experiment ran both exact preserved binaries on CPU 0, with shuffled suite/mode order and shuffled before/after invocation order (seed 303), five independent paired rounds, one warmup batch and seven recorded samples per invocation. The existing engine order *within* an invocation remains fixed; this is a limitation. Binary SHA-256 values are recorded. All cross-build acceptance, output hash/count, and allocation payload/call/reservation comparisons passed.

| NPegged output mode | Unique cases | Median candidate/baseline latency | Improvements | Regressions |
|---|---:|---:|---:|---:|
| validation control | 57 | 0.9998 | 2 | 3 |
| spans | 57 | 0.9952 | 9 | 5 |
| tree | 57 | 0.9801 | 16 | 3 |

Improvement/regression labels require a median change exceeding 3% and a paired-run bootstrap 95% interval entirely below/above one. Intervals exhaustively resample the five run ratios (3,125 draws); they are exploratory, unadjusted for multiple comparisons, and do not treat the 35 within-run timing samples as independent experiments. Of 144 unique cases with any baseline observation above target, only 21 meet this improvement rule. Handwritten controls also show variability and layout effects: see all 342 engine/case rows in `B03-summary.json`. Harness overhead has not been independently isolated, so tiny cases should not support causal claims.

Representative candidate/baseline median ratios and paired-run intervals (below one favors candidate):

| Workload | Mode | Median | 95% interval |
|---|---|---:|---|
| CSV.Flat | spans | 0.985 | [0.968, 0.990] |
| CSV.Flat | tree | 0.980 | [0.968, 0.990] |
| CSV.MultiLine | tree | 0.986 | [0.973, 0.990] |
| PEGGrammar.ManyRules | tree | 0.950 | [0.862, 0.992] |
| PEGGrammar.Deep | tree | 0.968 | [0.955, 0.979] |
| Ambiguous.Retry | spans | 0.933 | [0.904, 0.965] |
| Numbers.BinaryLong | spans | 1.162 | [1.141, 1.180] |
| Numbers.BinaryLong | tree | 1.164 | [1.159, 1.172] |
| Arithmetic.Deep | spans | 1.104 | [1.045, 1.116] |
| JSON.DeepNesting | spans | 1.088 | [1.071, 1.097] |
| PEGGrammar.Permissive | validation control | 1.051 | [1.020, 1.080] |

`Numbers.BinaryLong` regressed in every paired round, while its handwritten controls stayed close to one (median 1.001 spans and 1.003 tree). Broad median gains were small, including only ~1.5–2% on the forecast high-density CSV.Flat cases. Rejecting the patch avoids accepting scattered improvements with unresolved clear regressions. This rejects this exact growth-outlining experiment; it does not establish that all record-emission optimizations are impossible.

Assembly inspection: baseline `openKind` was 339 bytes with inline growth code and six saved registers. In the candidate, `openKind` disappeared as a separate symbol (inlined into callers) and `grow` was 106 bytes. Executable text increased by 9,920 bytes. The intended compiler transformation occurred, but did not satisfy gate-wide promotion criteria. No selector, ownership, budget, default mode or compile-version policy changed.

## Correctness and memory evidence

- DMD and LDC records/storage unit suites passed, including new growth, parent preservation, rollback/reuse, limit failure and sticky failure assertions in the archived patch.
- `tests/shared_output.d` compiled twice with identical LDC flags and all source modules, replacing only records.d with the preserved baseline for the reference build. Both 3,464-line transcripts were identical (the authoritative count and SHA are in `B03-validation.json`; `B03-oracle.txt.gz` stores the complete common transcript). This checks status, success, end/failEnd, selected tuples/parent indices, owned/borrowed input, actions/traces and finite resource limits. Both builds exercised shared output: frozen=147424, reused=60929, snapshots=192, restore=2113504.
- ASan/LSan passed for the records/storage unit suites outside the sandbox. Initial sandbox execution could not initialize LSan under ptrace; it was rerun with permission. This is module-scope memory evidence, not a whole-repository sanitizer claim.
- Valgrind passed for those suites: zero errors, zero definitely/indirectly/possibly lost bytes; 120 runtime-owned bytes remained reachable. The first run lacked loader symbols; cached debuginfod data resolved it.
- Candidate was formatted with dfmt and its modified code/new unit test compiled as `@nogc nothrow` without warnings on both compilers. No Phobos imports were introduced. No coverage or full staged hook run was performed for the rejected patch; no production code or unit test from it remains in the worktree.

## Reproduction

Gate build/compiler logs and hashes are embedded in both gate artifacts. Full default corpus uses existing finite limits and fixture-specific obligations documented in A01/B01. Oracle metrics builds are separate from uninstrumented timing builds. Timing runs keep combinator backend and existing compile versions unchanged.

From the base revision, preserve records.d and the baseline binary after the first gate, apply the archived patch, then run the second gate:

```sh
python3 scripts/performance_gate.py --output performance/phase3/B03-before-gate.json
mkdir -p build/B03
cp src/npegged/records.d build/B03/before-records.d
cp build/ldc2/benchmark_runner build/B03/before-runner
git apply performance/phase3/B03-rejected.patch
dfmt -i src/npegged/records.d
python3 scripts/performance_gate.py --output performance/phase3/B03-after-gate.json
cp build/ldc2/benchmark_runner build/B03/after-runner
python3 scripts/b03_interleave.py build/B03/before-runner build/B03/after-runner performance/phase3/B03-interleaved.json
python3 scripts/b03_summary.py
```

Gate commands exit 1 because the 1.5× gate fails; retain the reports and continue the experiment explicitly. Each benchmark invocation in the supplemental script has a 120-second timeout and 4 GiB address-space limit. The official runner uses its existing execution timeouts. The oracle was run as follows:

```bash
mapfile -t library < <(rg --files src -g '*.d' | sort)
for policy in before after; do
  sources=()
  for source in "${library[@]}"; do
    if [[ "$policy" == before && "$source" == src/npegged/records.d ]]; then
      sources+=(build/B03/before-records.d)
    else
      sources+=("$source")
    fi
  done
  prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 -Isrc -w -unittest -checkaction=halt -defaultlib=druntime-ldc -fno-exceptions -d-version=NPeggedMetrics -d-version=NPeggedSharedOutput "${sources[@]}" tests/shared_output.d -of=build/B03/$policy-oracle
  prlimit --as=4294967296 -- timeout --kill-after=2s 60s build/B03/$policy-oracle --DRT-testmode=run-main > build/B03/$policy-oracle.txt
done
cmp build/B03/before-oracle.txt build/B03/after-oracle.txt
```

Module checks (run while candidate source was installed):

```sh
ldc2 -Isrc -defaultlib=druntime-ldc -fno-exceptions -checkaction=halt -w -unittest -main src/npegged/records.d src/npegged/storage.d -of=build/B03/records-ldc
prlimit --as=4294967296 -- timeout --kill-after=2s 60s build/B03/records-ldc
dmd -Isrc -defaultlib=druntime -nothrow -checkaction=halt -w -unittest -main src/npegged/records.d src/npegged/storage.d -of=build/B03/records-dmd
prlimit --as=4294967296 -- timeout --kill-after=2s 60s build/B03/records-dmd
ldc2 -Isrc -defaultlib=druntime-ldc -fno-exceptions -checkaction=halt -w -unittest -main -fsanitize=address -g src/npegged/records.d src/npegged/storage.d -of=build/B03/records-asan
ASAN_OPTIONS=detect_leaks=1 timeout --kill-after=2s 60s build/B03/records-asan
DEBUGINFOD_URLS=https://debuginfod.cachyos.org DEBUGINFOD_CACHE_PATH="$PWD/build/debug-cache-cachy" prlimit --as=4294967296 -- timeout --kill-after=2s 60s valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=definite,indirect --error-exitcode=1 build/B03/records-ldc
```

After rejecting the experiment, restore the preserved source:

```sh
cp build/B03/before-records.d src/npegged/records.d
git diff --exit-code -- src/npegged/records.d
```

## Next milestone evidence

B04 must target a distinct demonstrated cost. B02's heuristic failed-probe model is insufficient to justify a choice-dispatch optimization, and the plan excludes replaying H04/H05/H08 variants. Gather actual operation counts/site profiles before choosing that experiment; do not turn this rejected outlining hypothesis into successive tuning variants. No global ≤1.5× success is claimed.
