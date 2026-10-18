#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/H06/memory
mapfile -t library < <(rg --files src -g '*.d' | sort)
flags=(-Isrc -defaultlib=druntime-ldc -fno-exceptions -w -unittest -checkaction=halt -g -d-version=NPeggedScannerMetrics)
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" -fsanitize=address "${library[@]}" tests/scanner_report.d -of=build/H06/memory/asan.runner
systemd-run --user --scope -q --unit="npegged-H06-asan-$RANDOM" -p MemoryMax=4G -p MemorySwapMax=0 env ASAN_OPTIONS=detect_leaks=1:detect_stack_use_after_return=0 timeout --kill-after=2s 60s build/H06/memory/asan.runner --DRT-testmode=run-main > build/H06/memory/asan.txt 2> build/H06/memory/asan.log
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" -O0 "${library[@]}" tests/scanner_report.d -of=build/H06/memory/debug.runner
systemd-run --user --scope -q --unit="npegged-H06-memcheck-$RANDOM" -p MemoryMax=4G -p MemorySwapMax=0 env DEBUGINFOD_URLS=https://debuginfod.cachyos.org DEBUGINFOD_CACHE_PATH="$PWD/build/debug-cache-cachy" timeout --kill-after=2s 120s valgrind --max-stackframe=8388608 --tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes --errors-for-leak-kinds=definite,indirect --error-exitcode=1 build/H06/memory/debug.runner --DRT-testmode=run-main '--DRT-gcopt=disable:1 parallel:0 cleanup:none' > build/H06/memory/memcheck.txt 2> build/H06/memory/valgrind.log
cmp build/H06/memory/asan.txt build/H06/memory/memcheck.txt
