#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
compiler=${DC:-dmd}
build_dir=build/$(basename "$compiler")
mkdir -p "$build_dir"
mapfile -d '' library < <(find src -name '*.d' -print0 | sort -z)
mapfile -d '' samples < <(find examples -maxdepth 1 -name '*.d' -print0 | sort -z)
common=(-Isrc)
case "$(basename "$compiler")" in
  dmd) common+=(-defaultlib=druntime -nothrow -checkaction=halt -w); unit=(-unittest); output=(-of="$build_dir/tests");;
  ldc2) common+=(-defaultlib=druntime-ldc -fno-exceptions -checkaction=halt -w); unit=(-unittest); output=(-of="$build_dir/tests");;
  gdc) common+=(-nophoboslib -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fcheckaction=halt -Wall -Werror); unit=(-funittest); output=(-o "$build_dir/tests");;
  *) echo "Unsupported compiler: $compiler" >&2; exit 2;;
esac
link=()
if [[ $(basename "$compiler") == gdc ]]; then link=(-lgdruntime); fi
extra=()
# Flags are passed as separate script arguments; no shell evaluation.
if (($#)); then extra=("$@"); fi
"$compiler" "${common[@]}" "${unit[@]}" "${extra[@]}" "${library[@]}" "${samples[@]}" tests/runner.d "${output[@]}" "${link[@]}"
timeout --preserve-status --kill-after=2s 60s "$build_dir/tests" --DRT-testmode=run-main
