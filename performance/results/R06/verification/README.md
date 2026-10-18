# R06 verification

All evidence here belongs to the final R06 source hashes in oracle-manifest.json
and coverage-sources.json. The full timing matrix independently pins source,
fixture and measurement-script hashes in every cohort's metadata.

- `bash scripts/shared-output-check.sh`: 24 DMD/LDC × combinator/direct ×
  selective/full × all/root/leaf pairs. Compare complete deterministic transcripts
  between ordinary and experimental builds and policy off/on inside each build.
  Compilation and execution use 4 GiB address-space ceilings and 300/60-second
  timeouts. Every runner also has a 45-second alarm. oracle.log and the transcript
  hashes/line counts record successful pairs.
- `METRICS=0 BACKENDS=combinators MEMOS=selective PROJECTIONS=all bash
  scripts/shared-output-check.sh`: both compilers without counters. Their exact
  transcripts also match the instrumented ordinary reference.
- `SHARED_OUTPUT_COVERAGE=1 bash scripts/coverage.sh`: source-wide DMD line and
  GDC source-branch coverage, including the shared-output integration oracle.
  Every executable src module exceeds 90% in both. Definition-only modules have
  no executable branches. The coverage source manifest rejects source drift.
- DMD/LDC `-c -w -vgc`, druntime only, no exceptions,
  NPeggedSharedOutput, `tests/hotpath.d src/npegged/records.d`: no diagnostics.
- `bash scripts/shared-records-check.sh`: all five R05 compatibility cohorts pass.
- DMD/LDC differential suites with NPeggedSharedOutput: 17 modules pass each.

ASan/LSan uses LDC `-unittest -d-version=NPeggedSharedOutput
-d-version=NPeggedMetrics -fsanitize=address -g -w -checkaction=halt
-defaultlib=druntime-ldc -fno-exceptions -Isrc`, all src modules plus
`tests/shared_output.d`. Run with ASAN_OPTIONS=detect_leaks=1,
`--DRT-testmode=run-main`, a 60-second timeout and a user systemd scope with
MemoryMax=4G/MemorySwapMax=0. Its output transcript equals the ordinary reference.

Memcheck uses the same unit/oracle source and flags with `-g -O0` replacing the
sanitizer option, a 90-second timeout, the same memory scope, and Valgrind
`--tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes
--errors-for-leak-kinds=definite,indirect --error-exitcode=1`.
The runner additionally uses `'--DRT-gcopt=disable:1 parallel:0 cleanup:none'`.
Loader symbols come from the cached CachyOS debuginfod service. No suppressions
are used. The final log reports zero errors and no definite/indirect leaks;
druntime retains 216 reachable bytes and 32 possibly lost bytes. Its complete
output transcript also equals the ordinary reference. Do not describe this as
zero bytes in every Valgrind leak category.

Routine validation now includes the oracle: one LDC configuration in fast mode,
and the full compiler/backend/memo/projection matrix in full mode. The active
pre-commit hook validates the staged checkout rather than unstaged files.
