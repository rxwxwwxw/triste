#!/usr/bin/env bash
# C02 correctness only. ASan needs a physical-memory cgroup, not RLIMIT_AS.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/C02 performance/phase3/C02
mapfile -t library < <(rg --files src -g '*.d' | sort)
common=(-Isrc -defaultlib=druntime-ldc -fno-exceptions -w -de -checkaction=halt
        -d-version=NPeggedSharedOutput -d-version=NPeggedMetrics)
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${common[@]}" -fsanitize=address -g \
    "${library[@]}" tests/bounded_shared_output.d -of=build/C02/asan \
    > performance/phase3/C02/asan-build.log 2>&1
systemd-run --user --scope -q --unit="triste-C02-asan-$RANDOM" -p MemoryMax=4G -p MemorySwapMax=0 \
    env ASAN_OPTIONS=detect_leaks=1 timeout --kill-after=2s 60s build/C02/asan \
    > performance/phase3/C02/asan.csv 2> performance/phase3/C02/asan.log
# Build explicitly, so this entrypoint does not depend on a leftover binary.
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${common[@]}" -g \
    "${library[@]}" tests/bounded_shared_output.d -of=build/C02/memcheck \
    > performance/phase3/C02/memcheck-build.log 2>&1
DEBUGINFOD_URLS=https://debuginfod.cachyos.org \
DEBUGINFOD_CACHE_PATH="$PWD/build/debug-cache-cachy" \
prlimit --as=4294967296 -- timeout --kill-after=2s 60s valgrind --tool=memcheck \
    --leak-check=full --show-leak-kinds=all --track-origins=yes \
    --errors-for-leak-kinds=definite,indirect --error-exitcode=1 build/C02/memcheck \
    > performance/phase3/C02/valgrind.csv 2> performance/phase3/C02/valgrind.log
cmp performance/phase3/C02/asan.csv performance/phase3/C02/valgrind.csv
