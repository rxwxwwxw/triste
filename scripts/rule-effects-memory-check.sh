#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/H02/memory
if [[ ! -f build/H02/ldc2.txt ]]; then COMPILERS=ldc2 bash scripts/rule-effects-check.sh; fi
mapfile -t library < <(rg --files src -g '*.d' | sort)
flags=(-Isrc -defaultlib=druntime-ldc -fno-exceptions -w -unittest -checkaction=halt -g)
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" -d-version=EligibilityGCStress -fsanitize=address "${library[@]}" tests/rule_effects.d -of=build/H02/memory/asan.runner
systemd-run --user --scope -q --unit="npegged-H02-asan-$RANDOM" -p MemoryMax=4G -p MemorySwapMax=0 env ASAN_OPTIONS=detect_leaks=1:detect_stack_use_after_return=0 timeout --kill-after=2s 60s build/H02/memory/asan.runner --DRT-testmode=run-main > build/H02/memory/asan.txt 2> build/H02/memory/asan.log
cmp build/H02/ldc2.txt build/H02/memory/asan.txt
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" -O0 "${library[@]}" tests/rule_effects.d -of=build/H02/memory/debug.runner
# Conservative GC marking is checked in native/ASan runs, not under Memcheck.
systemd-run --user --scope -q --unit="npegged-H02-memcheck-$RANDOM" -p MemoryMax=4G -p MemorySwapMax=0 env DEBUGINFOD_URLS=https://debuginfod.cachyos.org DEBUGINFOD_CACHE_PATH="$PWD/build/debug-cache-cachy" timeout --kill-after=2s 120s valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes --errors-for-leak-kinds=definite,indirect --error-exitcode=1 build/H02/memory/debug.runner --DRT-testmode=run-main '--DRT-gcopt=disable:1 parallel:0 cleanup:none' > build/H02/memory/memcheck.txt 2> build/H02/memory/valgrind.log
cmp build/H02/ldc2.txt build/H02/memory/memcheck.txt
