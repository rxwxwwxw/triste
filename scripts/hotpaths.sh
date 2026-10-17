#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/hotpaths
compilers=${COMPILERS:-"dmd ldc2"}
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
