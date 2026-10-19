#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/hotpaths
if [[ -z "${COMPILERS:-}" ]]; then
  compilers=""
  for c in dmd ldc2; do
    if command -v "$c" >/dev/null 2>&1 && ("$c" --version) >/dev/null 2>&1; then
      compilers="${compilers:+$compilers }$c"
    fi
  done
  if [[ -z "$compilers" ]]; then compilers="ldc2"; fi
else
  compilers="$COMPILERS"
fi
for compiler in $compilers; do
 case $compiler in
   dmd|ldc2) args=(-Isrc -c -vgc tests/hotpath.d "-of=build/hotpaths/$compiler.o");;
   gdc) args=(-Isrc -c -ftransition=nogc tests/hotpath.d -o "build/hotpaths/$compiler.o");;
 esac
 "$compiler" "${args[@]}" > "build/hotpaths/$compiler.log" 2>&1
 if [[ -s "build/hotpaths/$compiler.log" ]]; then
   cat "build/hotpaths/$compiler.log" >&2
   exit 1
 fi
done
