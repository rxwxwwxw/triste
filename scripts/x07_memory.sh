#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/X07 performance/phase3/X07
mapfile -t library < <(rg --files src -g '*.d' | sort)
flags=(-Isrc -defaultlib=druntime-ldc -fno-exceptions -w -de -checkaction=halt -g -O1)
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" -fsanitize=address \
    "${library[@]}" tests/test_recursive_ascent.d -of=build/X07/asan \
    > performance/phase3/X07/asan-build.log 2>&1
systemd-run --user --scope -q --unit="triste-X07-asan-$RANDOM" -p MemoryMax=4G -p MemorySwapMax=0 \
    env ASAN_OPTIONS=detect_leaks=1 timeout --kill-after=2s 60s build/X07/asan \
    > performance/phase3/X07/asan.txt 2> performance/phase3/X07/asan.log
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" \
    "${library[@]}" tests/test_recursive_ascent.d -of=build/X07/memcheck \
    > performance/phase3/X07/memcheck-build.log 2>&1
DEBUGINFOD_URLS=https://debuginfod.cachyos.org DEBUGINFOD_CACHE_PATH="$PWD/build/debug-cache-cachy" \
prlimit --as=4294967296 -- timeout --kill-after=2s 60s valgrind --tool=memcheck --leak-check=full \
    --show-leak-kinds=all --track-origins=yes --errors-for-leak-kinds=definite,indirect --error-exitcode=1 \
    build/X07/memcheck > performance/phase3/X07/memcheck.txt 2> performance/phase3/X07/memcheck.log
cmp performance/phase3/X07/asan.txt performance/phase3/X07/memcheck.txt
