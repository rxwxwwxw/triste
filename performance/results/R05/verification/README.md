# R05 verification

`bash scripts/shared-records-check.sh` runs five bounded builds: DMD/LDC
normal, DMD/LDC NPeggedMetrics, and optimized LDC NPeggedMetrics (-O3 with
assertions enabled). Compiler warnings or any -vgc output fail the script.
Metric CSVs must agree byte-for-byte; normal builds execute the same equality
oracle with the diagnostic fields statically absent. Each binary has a 60-second
runner timeout, 45-second internal alarm, and 4 GiB address-space ceiling.
`correctness.log` records each successful cohort. Final source and raw CSV hashes
are in ../metadata.json.

`bash scripts/coverage.sh` repeats repository-wide DMD line and GDC source-branch
coverage for the final source, including all source-adjacent experimental units.
The collected manifest and branch summary pin that evidence. Existing flat APIs
are byte-unchanged from R04, whose complete repository validation log is retained
at ../../R04/verification/full-validation.log.

ASan/LSan: LDC -unittest -d-version=NPeggedMetrics -fsanitize=address -g,
records.d + storage.d + tests/shared_records.d, druntime only, no exceptions,
ASAN_OPTIONS=detect_leaks=1. Run with --DRT-testmode=run-main under a 60-second
timeout and MemoryMax=4G/MemorySwapMax=0 user scope.

Memcheck: the same metric unit/oracle source with LDC -g -O0; Valgrind
--tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes
--errors-for-leak-kinds=definite,indirect --error-exitcode=1, the same timeout
and memory scope, and '--DRT-gcopt=disable:1 parallel:0 cleanup:none'.
Loader debug symbols use the cached CachyOS debuginfod service. The final log
reports zero errors and zero lost bytes, with 120 reachable druntime bytes;
no suppressions are used.

The new oracle is also wired into routine validation: LDC normal/metric/optimized
in fast mode, and both compilers in full mode.
