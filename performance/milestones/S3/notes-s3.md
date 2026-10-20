# S3 — Lean entry path — complete, experimental

The exact whole-DFA entry is retained behind `NPeggedLeanEntry`. Default
**enablement is NO-GO**: the controlled opt-in comparison has 14 workloads
slower by more than 5% in all three blocks. The final default executable is
byte-identical to the pre-S3 exact baseline. The default backend is unchanged.

## Milestone report

Milestone: S3 — Lean entry path
Commit: the enclosing S3 Git commit; the final agent response records its hash
Dirty working tree: pending the milestone commit at report preparation
Files changed: src/npegged/{peg,dfa,grammar}.d; colocated coverage tests in
bites/coverage/fuzz/generator/learning/ll/policy; tests/{entry,dfa_edges}.d;
coverage, differential, validation and performance scripts; performance registry,
dashboard, trends and retained S3 artifacts; docs/ROADMAP.md
Correctness rationale: a nonmemoized, reference-free whole-DFA rule has exactly
one rule tick plus the existing scanner charge. Known scanner outcomes require
no State or allocation. Other outcomes replay the primitive body with one tick
and one depth entry already charged. End, failEnd, status and arena counters are
preserved. Trace/instrumentation guards take the exact path.
Fallback/unsupported: non-direct backends, references, memoization, parameters,
unknown/non-DFA regions, trace/metrics/dependency tracing, depth zero, step limits
below two, and inputs longer than eight bytes; records/tree use existing paths
New unit tests: 56 net colocated source blocks across 10 modules, plus diagnostic
and integration-file blocks; DMD/LDC pass. Runtime FIRST-2 table oracle checks
all 65,792 two-byte/EOF prefixes; BITES tests compare against an independent PEG
interpreter and test conservative budget/recursion fallback.
New integration tests: tests/entry.d covers dense limits, feature on/off,
validation/records/tree, tracing and unsupported roots; tests/dfa_edges.d compares
scanner implementations over every reachable state and byte under coverage.
Cross-backend differential tests: full tests/differential.d main, including
finite input enumeration and dense step/depth/memory/output-limit sweeps, passed
on DMD and LDC with the feature enabled. G6/corpus workflows pass under coverage.
DMD: pass — scripts/entry-check.sh (feature off/on), full A4 main, scoped
accounting-tool and Q1-adapter units; zero compiler warnings
LDC: pass — same entry/A4 checks, full 171-workload release builds with feature
off/on, accounting and diagnostic builds; zero compiler warnings on these builds
Coverage / dfmt / -vgc / ASan / LSan / Valgrind: pass — all 25 executable source
modules exceed 90% lines and branches; touched D files formatted; DMD/LDC -vgc
clean on the entry benchmark; current entry, DFA-edge and accounting/adapter
sanitizer checks pass; Memcheck has zero errors and zero definite/indirect leaks
Performance results: this directory, especially 20261020T151538Z-427156981-2d501e854/
(opt-in), 20261020T162737Z-073837506-2d501e854/ (default), entry-* and ladder-*
Comparability: Linux/Ryzen, same LDC, corpus/mode/output obligations; 21 samples
per implementation/case, fixed CPU and alternating prebuilt blocks for the full
comparisons. Opt-in changes the feature version intentionally. M1 timings are
not compared with Linux timings.
Affected workloads: all 171 maintained equal-output workloads; six entry
fixtures and the original Q1 ladder with an exact-table entry adapter
Median slowdown before -> after: opt-in geomean 1.499 -> 1.516; default
1.503 -> 1.504 (identical executable, ordinary measurement variation)
Workloads <=1.5x before -> after: opt-in 87/171 (50.9%) -> 89/171 (52.0%);
default 88/171 (51.5%) -> 88/171 (51.5%)
90th percentile slowdown before -> after: opt-in 2.3789 -> 2.4379;
default 2.4280 -> 2.4332
Largest regression: opt-in Ambiguous.Retry/validation, pooled generated median
+60.66%, with +55.43/+65.00/+66.12% block changes. Fourteen repeatable >5%
regressions are retained in final-controlled-deltas.csv; default enablement is
rejected. Default comparison has no >5% regression in every block.
Parser generation / compile time / binary size / RSS: size/default.csv and
size/lean.csv retain real measurements. Full binary 6,883,448 -> 6,892,104 bytes
for opt-in (+0.126%); default remains 6,883,448 bytes, identical SHA-256.
Full build/export 619.9 -> 716.3 seconds for opt-in and 609.2 seconds for the
final default build; these single build times are not reproducible speed claims.
Known blockers / next milestone: no S3 implementation blocker; default remains
exact. The optional 200-rule native-compilation stress case exhausts even the
bounded 16 GiB compiler budget in BOTH variants; source generation succeeds and
is deterministic. Native object/RSS success deltas for that case are unavailable.
S8 rejection-path ceiling experiment is next. D1-D3 remain maintainer decisions.

## Requirement disposition

- **(a) Whole-DFA roots:** implemented, exact and opt-in. At the public entry,
  rule/defined/scanner setup is skipped only under the certified premises.
- **(b) Lean State:** the certified shortcut constructs no State/context at all.
  General memo buckets/entries already allocate lazily. The context-pointer
  prototype preserved a local configuration snapshot but had no valid-fixture
  gain and about 10% rejection regressions; closed NO-GO, original storage kept.
- **(c) Finish:** explicit no-failure return had no empty/one-byte gain and about
  11% rejection regressions; closed NO-GO, original finish kept with added tests.
- **(d) Invariant checks:** trace/depth/step guards run once on the shortcut;
  fresh status is known. Unsupported paths retain their exact checks.

The Q1 ladder extension uses the ORIGINAL grammar, DFA and rule chain. Its
exact adapter and lean adapter isolate entry dispatch without changing the
body. Empty/one-byte exact costs are about 17.6 ns, lean about 6.9 ns. Generator
eligibility is validated separately by actual generated-parser tests and runs.
The six generated-entry fixtures take 0.60-0.88x the corresponding exact wrapper.
Neither diagnostic substitutes for the full-workload results.

The fixed 40 tiny workload IDs from Phase 2 have 9 -> 12 within target on this
host, only THREE new crossings. The >=15-crossing hypothesis is refuted. Larger
JSON loses two crossings; CSV record and larger PEG clusters gain none. See
cluster-comparison.json; historical S2b values are used only to define membership.

## Verification and provenance

- `coverage-final.json` retains current source hashes and all per-module line/
  branch results. Minimum branch coverage is grammar.d at 90.04%; bites 91.34%,
  ll 90.93%, peg 91.06%. The threshold and exclusions were not relaxed.
- `default-binary-identity.json`: both default executables have SHA-256
  `578cf6da204478c6f55bfe961d1d7beec222d2a066c1e8ce623e90bcf441881c`.
- `audit-test-only.py` reconstructs the timing input hashes after removing only
  subsequent test additions and the standalone A4 runner correction. Production
  source matches the timing snapshot exactly.
- The A4 wrapper previously omitted `--DRT-testmode=run-main`, which let druntime
  exit after units. It now runs the actual integration main under a 240-second,
  4 GiB bound. The old 60-second explicit-main attempt timed out; full DMD/LDC
  runs pass at the correct bound. Coverage workflows already invoked that main.
- ASan uses the repository's druntime-compatible
  `detect_stack_use_after_return=0` and LeakSanitizer. Memcheck uses cached loader
  symbols and `--DRT-gcopt=disable:1 parallel:0 cleanup:finalize`, avoiding
  conservative GC scanning. 32 bytes possibly lost and 216 reachable originate
  in druntime initialization; zero definite/indirect leaks or detected errors.
- Coverage tests exposed and fix malformed literal suffix acceptance, empty
  regression-input parsing, decimal overflow, and compiler-dependent PRNG operand
  evaluation order. These are covered by adjacent tests and bounded workflows.
- `size/` records all successful and failed attempts. Missing GNU time was
  replaced with per-child wait4 accounting and scoped File/Buffer ownership.
  The 200-rule compiler stress failure is not a parser runtime or memory-test
  pass. Compiler-only budgets were documented separately; runtime/test limits
  remain 4 GiB. No handwritten baseline implementation was changed.
- DMD timing ratios and successful 200-rule native costs are not measured. No
  speedup is claimed for the default parser or for an unmeasured configuration.

`checks.md` preserves the chronological verification log, including failures and
superseded experiments. The commit hook's final result is recorded in Git/the
final agent response; commit creation is conditional on that hook passing.
