#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/H06/oracle
mapfile -t library < <(rg --files src -g '*.d' | sort)
for compiler in ${COMPILERS:-dmd ldc2}; do
 for policy in ordinary diagnostic; do
  flags=(-Isrc -w -unittest -checkaction=halt)
  case "$compiler" in
   dmd) flags+=(-defaultlib=druntime -nothrow); [[ "$policy" == ordinary ]] || flags+=(-version=NPeggedScannerMetrics);;
   ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions); [[ "$policy" == ordinary ]] || flags+=(-d-version=NPeggedScannerMetrics);;
   *) exit 2;;
  esac
  prefix="build/H06/oracle/$compiler-$policy"
  prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/scanner_report.d "-of=$prefix.runner"
  prlimit --as=4294967296 -- timeout --kill-after=2s 60s "$prefix.runner" --DRT-testmode=run-main > "$prefix.txt"
 done
 cmp "build/H06/oracle/$compiler-ordinary.txt" "build/H06/oracle/$compiler-diagnostic.txt"
 echo "$compiler: scanner diagnostics preserve transcript"
done
