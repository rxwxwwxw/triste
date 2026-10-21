#!/usr/bin/env bash
# W1: the static work bounds dominate the units actually charged (enumeration over short inputs; extra evidence only).
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
mkdir -p build/W1
for compiler in "${compilers[@]}"; do
 flags=(-Isrc -w -checkaction=halt)
 case "$compiler" in
  dmd) flags+=(-defaultlib=druntime -nothrow);;
  ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions);;
  *) echo "Unsupported compiler: $compiler" >&2; exit 2;;
 esac
 prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/work_bounds.d "-of=build/W1/$compiler.runner"
 prlimit --as=4294967296 -- timeout --kill-after=2s 120s "build/W1/$compiler.runner" --DRT-testmode=run-main | tee "build/W1/$compiler.txt"
done
