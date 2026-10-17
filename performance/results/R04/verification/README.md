# Verification commands

- `bash scripts/validate.sh --full`: complete default-build compiler, differential,
  examples, hook, hot-path, DMD line/GDC branch coverage, sanitizer and Memcheck gates.
- DMD/LDC: compile records.d + storage.d with `-unittest -main` and
  `NPeggedMetrics`, then execute under timeout. Both report two modules passing.
- DMD: compile the full record_copying fixture with NPeggedMetrics; its CSV is
  byte-identical to LDC's combinators/selective/all cohort.
- LDC: the metric unit pair with `-fsanitize=address -g`,
  `ASAN_OPTIONS=detect_leaks=1`, 60-second timeout, MemoryMax=4G user scope.
- LDC metric unit pair `-g -O0`, Valgrind `--tool=memcheck --leak-check=full
  --show-leak-kinds=all --track-origins=yes --errors-for-leak-kinds=definite,indirect
  --error-exitcode=1`, 60-second timeout, MemoryMax=4G user scope,
  `--DRT-gcopt=disable:1 parallel:0 cleanup:none`.

Valgrind uses loader debug symbols cached through the CachyOS debuginfod service
(`DEBUGINFOD_URLS=https://debuginfod.cachyos.org`, cache under build/).
Full validation passed. Repository-wide Memcheck reports zero errors and zero
definite/indirect leaks, with 32 bytes possibly lost and 216 bytes reachable in
druntime initialization. Metric Memcheck reports zero errors and zero lost bytes; 120 bytes remain
reachable in druntime initialization. No suppressions are used.
