#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output_dir=${OUTPUT_DIR:-build/H04/oracle}
mkdir -p "$output_dir"
mapfile -t library < <(rg --files src -g '*.d' | sort)
for compiler in ${COMPILERS:-dmd ldc2}; do
 for backend in ${BACKENDS:-direct combinators}; do
 for policy in reference candidate; do
  flags=(-Isrc -w -unittest -checkaction=halt)
  if [[ "${PURE_ISLANDS:-0}" == 1 ]]; then
   case "$compiler" in dmd) flags+=(-version=NPeggedPureIslands);; ldc2) flags+=(-d-version=NPeggedPureIslands);; esac
  fi
  case "$compiler" in
   dmd) flags+=(-defaultlib=druntime -nothrow -version=NPeggedMetrics); [[ "$policy" == reference ]] || flags+=(-version=NPeggedLocalMemo);;
   ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions -d-version=NPeggedMetrics); [[ "$policy" == reference ]] || flags+=(-d-version=NPeggedLocalMemo);;
   *) exit 2;;
  esac
  if [[ "$backend" == combinators ]]; then
   case "$compiler" in dmd) flags+=(-version=Combinators);; ldc2) flags+=(-d-version=Combinators);; esac
  elif [[ "$backend" != direct ]]; then exit 2; fi
  prefix="$output_dir/$compiler-$backend-$policy"
  prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/local_memo.d "-of=$prefix.runner"
  prlimit --as=4294967296 -- timeout --kill-after=2s 60s "$prefix.runner" --DRT-testmode=run-main > "$prefix.txt"
 done
 cmp "$output_dir/$compiler-$backend-reference.txt" "$output_dir/$compiler-$backend-candidate.txt"
 echo "$compiler-$backend: exact local memo oracle passed"
 done
done
