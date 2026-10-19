#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build/A02
mapfile -t library < <(find src -name '*.d' | sort)

compiler=${DC:-ldc2}
flags=(-Isrc -I. -w -de -checkaction=halt)

case "$(basename "$compiler")" in
    dmd)
        flags+=(-defaultlib=druntime -nothrow -O -release
                -version=NPeggedSharedOutput
                -version=NPeggedPureIslands
                -version=NPeggedMetrics
                -version=NPeggedFlatSpecialization)
        ;;
    ldc2)
        flags+=(-defaultlib=druntime-ldc -fno-exceptions -O3 -release
                -d-version=NPeggedSharedOutput
                -d-version=NPeggedPureIslands
                -d-version=NPeggedMetrics
                -d-version=NPeggedFlatSpecialization)
        ;;
    *)
        echo "Unsupported compiler: $compiler" >&2
        exit 2
        ;;
esac

binary="build/A02/active_smoke_runner"
echo "Compiling A02 active-path smoke fixtures with $compiler..." >&2
prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/active_smoke_fixtures.d "-of=$binary"

echo "Executing A02 active-path smoke fixtures..." >&2
output=$(prlimit --as=4294967296 -- timeout --kill-after=2s 60s "$binary")
echo "$output"

if [[ "$output" != *"A02 active-path smoke fixtures passed"* ]]; then
    echo "ERROR: A02 active smoke fixtures did not produce expected pass marker" >&2
    exit 1
fi

echo "A02 verification clean."
