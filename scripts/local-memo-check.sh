#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/H04
mapfile -t library < <(rg --files src -g '*.d' | sort)
for compiler in ${COMPILERS:-dmd ldc2}; do
 for policy in reference candidate; do
  flags=(-Isrc -w -unittest -checkaction=halt)
  case "$compiler" in
   dmd) flags+=(-defaultlib=druntime -nothrow -version=NPeggedMetrics); [[ "$policy" == reference ]] || flags+=(-version=NPeggedLocalMemo);;
   ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions -d-version=NPeggedMetrics); [[ "$policy" == reference ]] || flags+=(-d-version=NPeggedLocalMemo);;
   *) exit 2;;
  esac
  prefix="build/H04/$compiler-$policy"
  prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/local_memo.d "-of=$prefix.runner"
  prlimit --as=4294967296 -- timeout --kill-after=2s 60s "$prefix.runner" --DRT-testmode=run-main > "$prefix.txt"
 done
 cmp "build/H04/$compiler-reference.txt" "build/H04/$compiler-candidate.txt"
 echo "$compiler: exact local memo oracle passed"
done
