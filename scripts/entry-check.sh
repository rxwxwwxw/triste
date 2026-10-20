#!/usr/bin/env bash
# S3: exact whole-DFA entry parity, including fallback and resource boundaries.
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
mkdir -p build/S3
for compiler in "${compilers[@]}"; do
 for feature in default lean; do
  flags=(-Isrc -I. -unittest -w -checkaction=halt)
  case "$compiler" in
    dmd) flags+=(-defaultlib=druntime -nothrow);;
    ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions);;
    *) echo "Unsupported compiler: $compiler" >&2; exit 2;;
  esac
  if [[ "$feature" == lean ]]; then
    case "$compiler" in
      dmd) flags+=(-version=NPeggedLeanEntry);;
      ldc2) flags+=(-d-version=NPeggedLeanEntry);;
    esac
  fi
  prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" \
    "${library[@]}" tests/entry.d "-of=build/S3/entry-$compiler-$feature"
  prlimit --as=4294967296 -- timeout --kill-after=2s 60s \
    "build/S3/entry-$compiler-$feature" --DRT-testmode=run-main
 done
done
