#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/H05/oracle
mapfile -t library < <(rg --files src -g '*.d' | sort)
for compiler in ${COMPILERS:-dmd ldc2}; do
 flags=(-Isrc -w -unittest -checkaction=halt)
 case "$compiler" in dmd) flags+=(-defaultlib=druntime -nothrow);; ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions);; *) exit 2;; esac
 prefix="build/H05/oracle/$compiler"
 prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/empty_scanner.d "-of=$prefix.runner"
 prlimit --as=4294967296 -- timeout --kill-after=2s 60s "$prefix.runner" --DRT-testmode=run-main > "$prefix.txt"
 test "$(tail -1 "$prefix.txt")" = 'empty scanner oracle passed'
 echo "$compiler: empty scanner oracle passed"
done
