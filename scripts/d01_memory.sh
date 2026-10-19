#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/D01 performance/phase3/D01
mapfile -t library < <(rg --files src -g '*.d' | sort)
sources=("${library[@]}" examples/json.d examples/csv.d examples/PEG.d benchmark/measurement.d
         tests/pure_islands.d benchmark/diagnostics/pure_islands.d)
flags=(-Isrc -I. -Ibuild/D01/imports -defaultlib=druntime-ldc -fno-exceptions -O1 -g -w -de
       -checkaction=halt -d-version=PureIslandsBenchmark -d-version=NPeggedMetrics
       -d-version=NPeggedPureIslands)
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" -fsanitize=address \
    "${sources[@]}" -of=build/D01/asan > performance/phase3/D01/asan-build.log 2>&1
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" \
    "${sources[@]}" -of=build/D01/memcheck > performance/phase3/D01/memcheck-build.log 2>&1
for tracing in 0 1; do
    systemd-run --user --scope -q --unit="triste-D01-asan-$RANDOM" -p MemoryMax=4G -p MemorySwapMax=0 \
        env ASAN_OPTIONS=detect_leaks=1 NPEGGED_TRACE_PURE_ISLANDS="$tracing" \
        timeout --kill-after=2s 120s build/D01/asan \
        > "performance/phase3/D01/asan-trace-$tracing.csv" 2> "performance/phase3/D01/asan-trace-$tracing.log"
    DEBUGINFOD_URLS=https://debuginfod.cachyos.org DEBUGINFOD_CACHE_PATH="$PWD/build/debug-cache-cachy" \
    NPEGGED_TRACE_PURE_ISLANDS="$tracing" prlimit --as=4294967296 -- timeout --kill-after=2s 120s \
        valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes \
        --errors-for-leak-kinds=definite,indirect --error-exitcode=1 build/D01/memcheck \
        > "performance/phase3/D01/memcheck-trace-$tracing.csv" 2> "performance/phase3/D01/memcheck-trace-$tracing.log"
done
