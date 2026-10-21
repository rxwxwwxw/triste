#!/usr/bin/env bash
# L5/L6a: LR(1) tables agree with the PEG parsers on certified LL(1) regions.
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
mkdir -p build/L5
for compiler in "${compilers[@]}"; do
 flags=(-Isrc -w -checkaction=halt)
 case "$compiler" in
  dmd) flags+=(-defaultlib=druntime -nothrow);;
  ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions);;
  *) echo "Unsupported compiler: $compiler" >&2; exit 2;;
 esac
 prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/lr_check.d "-of=build/L5/$compiler.runner"
 prlimit --as=4294967296 -- timeout --kill-after=2s 120s "build/L5/$compiler.runner" --DRT-testmode=run-main | tee "build/L5/$compiler.txt"
done
