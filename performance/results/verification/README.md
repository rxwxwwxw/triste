# Phase F verification

Source algorithms and defaults are unchanged; additions in src/ are diagnostic
counters behind NPeggedMetrics. All emitted D files were formatted with dfmt.

- `bash scripts/validate.sh --full`: DMD/LDC builds, examples, differential tests,
  hooks, no-Phobos, formatting, both hotpath compilers, DMD line coverage and GDC 16
  branch coverage passed. Every executable src module exceeds 90% for both metrics.
  The saved log records this result and the subsequent sandbox-only LSan failure.
- The already-built ASan/LSan integration binary passed outside the sandbox:
  `ASAN_OPTIONS=detect_leaks=1 timeout --kill-after=2s 60s build/ldc2/tests --DRT-testmode=run-main`.
  Recompilation was unnecessary; the sandbox's ptrace restriction prevents LSan
  thread inspection. The standalone metric unit build also passed ASan/LSan there.
- `DC=ldc2 scripts/build.sh -g -O0` passed, followed by a bounded 120-second Valgrind
  integration run: zero errors and zero definite/indirect leaks. Loader symbols
  were fetched with debuginfod-find into build/debug-cache-cachy; DEBUGINFOD_URLS
  and DEBUGINFOD_CACHE_PATH supplied them to Valgrind. No suppressions were used.
- Metric source-unit builds pass under DMD and LDC (14 modules). Diagnostic
  Valgrind also passes with the repository's GC test configuration
  `--DRT-gcopt=disable:1 parallel:0 cleanup:none`; conservative GC root scanning
  produces expected uninitialized-root reports with its default configuration.
- Both compilers emit zero -vgc diagnostics for tests/hotpath.d with metrics enabled.
  Separate static assertions verify the metric types/pointer fields are absent
  without NPeggedMetrics. Default hotpath checks pass via validate.sh.
- `python3 scripts/benchmark_checks.py` passes DMD/LDC benchmark unit and runner
  integration checks. Its root source list now excludes standalone diagnostic
  programs with their own main (recursion_scaling and dfa_scanning). Benchmark
  branch coverage is optional and was not collected; src branch coverage passed.
- Focused PEG probe compiles/runs with DMD's direct/full variant and all four
  optimized LDC variants. New summary tests reject missing/duplicate samples and
  validate assembly call/branch accounting. Differential diagnostics now report
  the exact mismatched field and full fixture identity, and include adjacent tests
  that detect nested successful/failed-child differences. Both compilers pass.

Raw F01/F03/F04/F05 performance evidence is stored separately from verification.
F01 remains a failing performance gate (380/387), as expected for diagnosis work.
No optimization or global acceptance improvement is claimed.

`historical-source-audit.json` verifies every F01/F03/F04 source hash against the
actual committed blob at ce113d9 / 42a26c6 / b1c8a71 (23 manifests). F01-medians.csv
summarizes all baseline raw samples as median ns/parse and byte throughput; gate
ratios retain their existing paired-mean definition. Reserved arena bytes describe
retained allocator storage per parse, not process RSS. F05's final source manifests
are checked against the final commit as well.
