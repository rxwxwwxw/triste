#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/R05
# Both the oracle and every direct runner invocation are bounded.
run_bounded() {
    (ulimit -v 4194304; timeout --kill-after=2s 60s "$@")
}
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
configurations=()
for compiler in "${compilers[@]}"; do
    case "$compiler" in
        dmd) configurations+=(dmd dmd-normal);;
        ldc2) configurations+=(ldc2 ldc2-optimized ldc2-normal);;
        *) echo "Unsupported compiler: $compiler" >&2; exit 2;;
    esac
done
if ((${#configurations[@]} == 0)); then exit 2; fi
for configuration in "${configurations[@]}"; do
    compiler=${configuration%%-*}
    common=(-Isrc -w -vgc -unittest -checkaction=halt)
    case "$compiler" in
        dmd) common+=(-defaultlib=druntime -nothrow);;
        ldc2) common+=(-defaultlib=druntime-ldc -fno-exceptions);;
    esac
    if [[ "$configuration" != *-normal ]]; then
        case "$compiler" in
            dmd) common+=(-version=NPeggedMetrics);;
            ldc2) common+=(-d-version=NPeggedMetrics);;
        esac
    fi
    if [[ "$configuration" == ldc2-optimized ]]; then common+=(-O3); fi
    "$compiler" "${common[@]}" src/npegged/records.d src/npegged/storage.d tests/shared_records.d "-of=build/R05/oracle-$configuration" > "build/R05/$configuration-compiler.log" 2>&1
    if [[ -s "build/R05/$configuration-compiler.log" ]]; then cat "build/R05/$configuration-compiler.log"; exit 1; fi
    run_bounded "build/R05/oracle-$configuration" --DRT-testmode=run-main > "build/R05/$configuration.csv"
    if [[ "$configuration" == *-normal && -s "build/R05/$configuration.csv" ]]; then exit 1; fi
    echo "$configuration: shared record oracle passed" >&2
done
if [[ " ${compilers[*]} " == *" dmd "* && " ${compilers[*]} " == *" ldc2 "* ]]; then
    cmp build/R05/dmd.csv build/R05/ldc2.csv
fi
if [[ " ${compilers[*]} " == *" ldc2 "* ]]; then
    cmp build/R05/ldc2.csv build/R05/ldc2-optimized.csv
fi
