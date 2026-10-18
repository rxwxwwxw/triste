#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
for compiler in "${compilers[@]}"; do
 directory="build/H01/$compiler"
 mkdir -p "$directory/sources"
 flags=(-Isrc -w -unittest -checkaction=halt)
 case "$compiler" in
  dmd) flags+=(-defaultlib=druntime -nothrow -version=EligibilityGCStress); if [[ "${BASELINE:-0}" == 1 ]]; then flags+=(-version=EligibilityBaseline); fi;;
  ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions -d-version=EligibilityGCStress); if [[ "${BASELINE:-0}" == 1 ]]; then flags+=(-d-version=EligibilityBaseline); fi;;
  *) exit 2;;
 esac
 prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/eligibility_report.d "-of=$directory/runner"
 H01_OUTPUT_DIR="$directory/sources" prlimit --as=4294967296 -- timeout --kill-after=2s 60s "$directory/runner" --DRT-testmode=run-main > "$directory/report.jsonl"
 if [[ "${BASELINE:-0}" != 1 ]]; then
  python3 scripts/verify_eligibility.py "$directory"
 fi
 echo "$compiler: eligibility fixture passed"
done
if [[ "${BASELINE:-0}" != 1 && " ${compilers[*]} " == *" dmd "* && " ${compilers[*]} " == *" ldc2 "* ]]; then
 cmp build/H01/dmd/report.jsonl build/H01/ldc2/report.jsonl
fi
