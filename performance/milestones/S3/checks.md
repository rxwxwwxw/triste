# S3 verification log (work in progress)

- `bash scripts/entry-check.sh`: DMD and LDC passed, zero warnings. 4,320
  dense step/depth reference/candidate comparisons, plus opCall agreement,
  45 records and tree pairs, and 48 trace/step-boundary comparisons.
- New colocated `tryDFAEntry` unittest: 224 budget/input combinations across
  anchored/unanchored tables plus invalid table, trace and depth guards.
- New Frontend unittest: eligible, combinator, memoized, literal, referenced,
  left-recursive and parameterized generation cases.
- `DC=ldc2 bash scripts/differential.sh`: 25 modules passed, including A4's
  existing full observable/mode and resource-limit sweeps.
- DMD and LDC `-c -Isrc -I. -vgc benchmark/entry_pair.d`: zero diagnostics.
- `dfmt -i` applied to all touched D files.
- LDC ASan/LSan passed:
  `ASAN_OPTIONS=detect_leaks=1:detect_stack_use_after_return=0:hard_rss_limit_mb=4096 timeout --kill-after=2s 60s build/S3/entry-asan --DRT-testmode=run-main`.
  LSan required execution outside sandbox tracing. An initial attempt omitted
  the repository's `detect_stack_use_after_return=0` setting (see validate.sh)
  and hit an introspection unit assertion; gdb identified the location. Using
  the established druntime-compatible setting passed without a source fix.
- Valgrind passed with zero errors and zero definite/indirect leaks, using
  cached debuginfod symbols, a 60s/4GiB bound and
  `--DRT-gcopt=disable:1 parallel:0 cleanup:finalize`. This avoids conservative
  GC stack scanning at termination. 32 bytes possibly lost and 216 reachable
  belong to druntime initialization, as in the Q1 supplemental run.
- Fresh full coverage: running; see `build/S3/coverage.log`.
- Full post-change release performance: running; expected `build/S3-after.json`.
- Full pre-commit hook: pending; S3 is not yet complete.

Baseline: `performance/baselines/20261020T010433Z-2d501e854/`, Linux/Ryzen,
87/171 within 1.5x, p90 2.47, geometric mean 1.51. The earlier M1 runs are
not comparable. Native baseline build+export took 619.9 seconds on this host.
A CLI `--build-timeout` preserves the standard 300-second default and makes
longer build allowances reproducible; runtime timeouts remain unchanged.

The paired diagnostic run under `entry-20261020T010514Z-2d501e8540/` retains
21 samples per implementation and fixture with a checksum check per batch.
It compares the same generated grammar through the entry and exact-wrapper
paths, including empty, valid, early/late rejection and invalid-byte inputs.
There is no handwritten twin: handwritten ratios are N/A, never fabricated.

## Fresh continuation verification (2026-10-20)

- Added eight colocated LL report/export unit blocks, covering terminal
  preconditions, all class names, numeric and byte escaping, empty and multi-rule
  rendering, and EBNF node/grouping cases. DMD/LDC `scripts/entry-check.sh` passed.
- S3(c) now explicitly returns after end/failEnd normalization when there is no
  remembered failure. Its adjacent State unittest checks normalization, nearer
  and farther remembered failures, accepted nodes, failed nodes, and tree children.
- `bash scripts/entry-check.sh` passed on DMD and LDC after both changes.
- `DC=ldc2 bash scripts/differential.sh`: 25 modules passed.
- Fresh ASan/LSan binary `build/S3/entry-finish-asan` passed outside sandbox
  tracing using the established options from the earlier run. The sandboxed
  attempt passed entry tests but LSan could not inspect threads under ptrace.
- Fresh Valgrind run (`build/S3/valgrind-finish.log`) exited zero: no errors,
  zero definite/indirect leaks. Same documented runtime cleanup configuration;
  32 bytes possibly lost and 216 bytes reachable remain in druntime.
- Full gate is collecting `build/S3-finish.json` with 3 x 7 samples, 5000
  iterations, direct backend and a 900-second build timeout. This tests the
  current guarded DFA candidate plus the finish change; it is not yet evidence
  of an improvement. A controlled paired comparison is still needed afterward.
- Current full coverage collection began before the LL and finish source edits.
  Its source freshness check must reject changed modules; it cannot be used as
  final coverage evidence without recollecting against the final sources.

- `DC=dmd bash scripts/differential.sh`: 25 modules passed as well.
- Both `dmd` and `ldc2 -c -Isrc -I. -vgc benchmark/entry_pair.d`
  passed without diagnostics after the finish change.
- Canonical formatting over src/tests, the maintained Phobos-import scan, and
  `git diff --check` passed.
- New paired diagnostic: `entry-20261020T143914Z-2d501e8540/`, 21 samples
  per fixture/implementation, same grammar and inputs. Entry/exact ratios range
  from 0.496 to 0.903. Handwritten ratios remain N/A. This does not supersede the
  pending full workload/regression comparison.
- Last live checks: coverage session 8458 and full-performance session 87368
  both remained running after a 30-second observation. Re-poll these handles;
  neither observation timeout is a terminal result.

## Retention decision and fresh frozen-source runs

- S3(b) pointer prototype: focused unit/entry tests passed. The local
  ParseContext snapshot preserved context isolation, but the exact-wrapper
  fixture timings showed no valid-input gain and roughly 10% rejection costs.
  Rejected; patch/raw data/metadata are in `context-20261020T145420Z/`.
- S3(c) explicit finish fast return: no empty/one-byte gain and roughly 11%
  rejection costs in the isolated run. Reverted the implementation; kept the
  useful normalization/frontier tests. See `finish-20261020T144745Z/`.
- S3(a,d) whole-DFA entry is now opt-in behind `NPeggedLeanEntry` because of
  retained full-suite regression evidence. It avoids State/context setup and
  checks trace/limits once on its certified path; unsupported cases replay the
  exact entry. The existing general State retains lazy memo allocation.
- `scripts/entry-check.sh` now verifies feature on/off on DMD and LDC: all four
  combinations passed. Default `scripts/eligibility-check.sh` passed all 72
  cases with unchanged generated bytes; the prior candidate snapshots were
  restored because default emission is again unchanged.
- The full finish-candidate gate rejected its run on a source-hash mismatch.
  Its timings are not usable evidence. Snapshot tracking now records input
  hashes before compilation and preserves invalid measurements and exact
  changed-file names if a future run detects drift. Six performance-gate
  Python tests pass, including the drift and unchanged-snapshot cases.
- New BITES tests are integrated: 12 seeded acyclic PEG graphs, four state
  budgets (0, 1, 4, 16), both regular-SUCC settings, independent PEG interpreter
  checks; plus recursion, unresolved/invalid nodes, fixed-pattern bounds and
  explicit overflow fallbacks. LDC and GDC scratch integration runs passed.
- A fresh coverage run is active as session 29182, log
  `build/S3/coverage-optin.log`. Source is now frozen; no formatter/edit during
  collection. The verifier's redundant fallback CFG parse is now lazy;
  threshold, decisions and exclusions are unchanged. Its scope/model tests pass.
- A fresh full gate is active as session 37939, log
  `build/S3/performance-optin.log`, expected `build/S3-optin.json` and persisted
  initial snapshot `build/S3-optin.sources.json`. Direct backend plus explicit
  lean-entry flag; 3 x 7 samples and all output modes.
- Fast full-worktree validation is active, log `build/S3/validate-optin-fast.log`.
  No commit or S3 completion mark has been made.

- Current opt-in ASan/LSan run passed (`build/S3/asan-optin.log`).
- Current opt-in Valgrind run passed: zero errors, zero definite/indirect leaks
  (`build/S3/valgrind-optin.log`), same documented druntime cleanup settings.
- Current opt-in DMD/LDC `-c -vgc benchmark/entry_pair.d` builds passed with
  zero diagnostics.
- Mid-run persisted snapshot comparison against `build/S3-optin.sources.json`
  showed zero changed files. Keep src/benchmark/scripts/tests frozen until both
  sessions 29182 (coverage) and 37939 (performance) are terminal.
- The helper's current adjacent budget sweep covers 288 input/budget pairs
  (9 fixtures x 16 limits x anchored/unanchored), plus explicit invalid-table,
  trace and depth guards; the earlier 224 count predates added guard fixtures.

- Fast full-worktree validation passed, including hooks, examples, hot paths,
  source formatting and zero Phobos (`build/S3/validate-optin-fast.log`).
- The six diagnostic fixtures are now registered in `performance/workloads.json`
  with literal byte inputs, checksums, exact comparison contract and explicit
  N/A handwritten reference. This registry update does not alter timed inputs.

## Full comparison and final coverage work

- Frozen-source full performance run completed with valid provenance:
  `20261020T151149Z-861675744-2d501e854/`. Its 271/513 passing paired
  checks reflect remaining above-target workloads, not output mismatches.
- Controlled alternating prebuilt comparison retained as baseline
  `performance/baselines/20261020T151538Z-302680467-2d501e854/` and candidate
  `20261020T151538Z-427156981-2d501e854/`: 87 -> 89 of 171 within target;
  geometric mean 1.499 -> 1.516. Fourteen workloads regress >5% in all three
  blocks (`final-controlled-deltas.csv`), so default enablement is rejected.
- Fixed S2b cluster membership is recorded in `cluster-comparison.json`; no
  cross-host timings are compared. Of its 40 tiny workload IDs, 9 -> 12 are
  within target on this host, only 3 new crossings. The >=15 hypothesis is
  refuted. CSV record and larger PEG clusters do not gain target crossings.
- Fresh final-source entry diagnostic: `entry-20261020T150327Z-2d501e8540/`,
  entry/exact ratios 0.60-0.88 across six fixtures; handwritten ratios N/A.
- Fresh full coverage failed branches in bites (83.26), grammar (89.22), ll
  (87.09), peg (88.13); every other required module passed. Targeted tests now
  cover runtime FIRST-2 plan construction against the ordered PEG oracle over
  all 65,792 two-byte/EOF prefixes; nullable conversion and closed-region proof
  metadata; report/parser boundaries; BITES/NEXTBITES fallback and escaping.
- DMD/LDC feature-on/off entry tests pass after these additions. A test that
  deleted the graph facts array violated followSets' solved-graph precondition;
  corrected it to an unknown fact within the structurally valid array.
- `audit-test-only.py` reproduces whole-file hash equality after removing only
  the added test blocks, proving production source matches the timing snapshot.
  Its JSON evidence is `test-only-source-audit.json`.
- Targeted GDC coverage suggests bites 91.34%, ll 90.93%, peg 91.06%; grammar
  was just short at 89.93% before the final FIRST-2 boundary tests. These are
  planning estimates, not a passing gate. Full recollection is now active as
  session 20854, log `build/S3/coverage-final.log`. Keep source frozen.
- Final ASan/LSan and Valgrind logs are `build/S3/{asan,valgrind}-final.log`;
  both print successful test/memory-check results; collect terminal handles.
- Full A4 differential verification with the lean feature enabled is active,
  DMD then LDC, logs `build/S3/differential-final-{dmd,ldc}.log`.
