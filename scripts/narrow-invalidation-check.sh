#!/usr/bin/env bash
# Bounded correctness for the retained reference or an archived R03 prototype.
set -euo pipefail
cd "${1:-$(dirname "$0")/..}"
mode=${2:-reference}
case "$mode" in reference|prototype) ;; *) echo 'Expected reference or prototype' >&2; exit 2;; esac
ulimit -v 4194304
mkdir -p build/R03
mapfile -t library < <(rg --files src -g '*.d' | sort)
for compiler in dmd ldc2; do
  flags=(-Isrc -I. -unittest -w -de -checkaction=halt)
  extra=()
  case "$compiler" in
    dmd)
      flags+=(-defaultlib=druntime -nothrow)
      if [[ $mode == prototype ]]; then extra=(-version=NPeggedNarrowInvalidation -version=NPeggedMetrics); fi;;
    ldc2)
      flags+=(-defaultlib=druntime-ldc -fno-exceptions)
      if [[ $mode == prototype ]]; then extra=(-d-version=NPeggedNarrowInvalidation -d-version=NPeggedMetrics); fi;;
  esac
  "$compiler" "${flags[@]}" "${extra[@]}" "${library[@]}" tests/narrow_invalidation.d -of="build/R03/oracle-$compiler"
  timeout --preserve-status --kill-after=2s 60s "build/R03/oracle-$compiler"
  if [[ $mode == prototype ]]; then DC=$compiler bash scripts/differential.sh "${extra[@]}"; fi
done
