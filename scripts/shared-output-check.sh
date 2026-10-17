#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/R06
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
for compiler in "${compilers[@]}"; do
    flags=(-Isrc -w -vgc -unittest -checkaction=halt)
    case "$compiler" in
        dmd) flags+=(-defaultlib=druntime -nothrow -version=NPeggedSharedOutput);;
        ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions -d-version=NPeggedSharedOutput);;
        *) exit 2;;
    esac
    mapfile -t library < <(rg --files src -g '*.d' | sort)
    "$compiler" "${flags[@]}" "${library[@]}" tests/shared_output.d "-of=build/R06/oracle-$compiler"
    (ulimit -v 4194304; timeout --kill-after=2s 60s "build/R06/oracle-$compiler" --DRT-testmode=run-main)
done
