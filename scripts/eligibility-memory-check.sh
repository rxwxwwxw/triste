#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep conservative GC roots on the native stack; see performance/results/H01/README.md.
mkdir -p build/H01/sanitizer/sources
if [[ ! -f build/H01/ldc2/report.jsonl ]]; then
 COMPILERS=ldc2 bash scripts/eligibility-check.sh
fi
mapfile -t library < <(rg --files src -g '*.d' | sort)
flags=(-Isrc -defaultlib=druntime-ldc -fno-exceptions -w -unittest -checkaction=halt -g)
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" -d-version=EligibilityGCStress -fsanitize=address "${library[@]}" tests/eligibility_report.d -of=build/H01/sanitizer/asan.runner
for attempt in 1 2 3; do
 systemd-run --user --scope -q --unit="npegged-H01-asan-$RANDOM" -p MemoryMax=4G -p MemorySwapMax=0 env ASAN_OPTIONS=detect_leaks=1:detect_stack_use_after_return=0 H01_OUTPUT_DIR=build/H01/sanitizer/sources timeout --kill-after=2s 60s build/H01/sanitizer/asan.runner --DRT-testmode=run-main > "build/H01/sanitizer/asan-$attempt.jsonl" 2> "build/H01/sanitizer/asan-$attempt.log"
 cmp "build/H01/sanitizer/asan-$attempt.jsonl" build/H01/ldc2/report.jsonl
done
cp build/H01/sanitizer/asan-1.jsonl build/H01/sanitizer/report.jsonl
python3 scripts/verify_eligibility.py build/H01/sanitizer
# Memcheck cannot inspect conservative stack marking without false undefined-value reports.
# Run all report operations with automatic GC disabled; native/ASan cover explicit collection.
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" -O0 "${library[@]}" tests/eligibility_report.d -of=build/H01/sanitizer/debug.runner
systemd-run --user --scope -q --unit="npegged-H01-memcheck-$RANDOM" -p MemoryMax=4G -p MemorySwapMax=0 env DEBUGINFOD_URLS=https://debuginfod.cachyos.org DEBUGINFOD_CACHE_PATH="$PWD/build/debug-cache-cachy" H01_OUTPUT_DIR=build/H01/sanitizer/sources timeout --kill-after=2s 120s valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes --errors-for-leak-kinds=definite,indirect --error-exitcode=1 build/H01/sanitizer/debug.runner --DRT-testmode=run-main '--DRT-gcopt=disable:1 parallel:0 cleanup:none' > build/H01/sanitizer/memcheck.jsonl 2> build/H01/sanitizer/valgrind.log
cmp build/H01/sanitizer/report.jsonl build/H01/sanitizer/memcheck.jsonl
