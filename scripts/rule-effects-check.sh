#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
mkdir -p build/H02
for compiler in "${compilers[@]}"; do
 flags=(-Isrc -unittest -w -checkaction=halt)
 case "$compiler" in
 dmd) flags+=(-defaultlib=druntime -nothrow -version=EligibilityGCStress);;
 ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions -d-version=EligibilityGCStress);;
 *) exit 2;;
 esac
 prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/rule_effects.d "-of=build/H02/$compiler.runner"
 prlimit --as=4294967296 -- timeout --kill-after=2s 60s "build/H02/$compiler.runner" --DRT-testmode=run-main > "build/H02/$compiler.txt"
 test "$(tail -1 "build/H02/$compiler.txt")" = 'rule effects oracle passed'
 echo "$compiler: rule-local effects passed"
done
if [[ " ${compilers[*]} " == *" dmd "* && " ${compilers[*]} " == *" ldc2 "* ]]; then
 cmp build/H02/dmd.txt build/H02/ldc2.txt
fi
