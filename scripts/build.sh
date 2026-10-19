#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v timeout >/dev/null 2>&1 && [[ -d /opt/homebrew/opt/coreutils/libexec/gnubin ]]; then
  export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
fi
compiler=${DC:-dmd}
compiler_name=$(basename "$compiler")
build_dir=build/$compiler_name
mkdir -p "$build_dir/imports/npegged"
ln -sfn "$(pwd)/examples" "$build_dir/imports/npegged/examples"
rm -f "$build_dir"/tests-*.o "$build_dir"/tests-*.gcno "$build_dir"/tests-*.gcda "$build_dir"/tests-*.profile
library=()
while IFS= read -r -d '' f; do
  library+=("$f")
done < <(find src -name '*.d' -print0 | sort -z)
heavy_samples=(
  examples/c.d
  examples/dgrammar.d
  examples/markdown.d
  examples/oberon2.d
  examples/python.d
  examples/xml2.d
)
light_samples=()
while IFS= read -r -d '' sample; do
  skip=0
  for heavy in "${heavy_samples[@]}"; do
    if [[ "$sample" == "$heavy" ]]; then
      skip=1
      break
    fi
  done
  if (( !skip )); then
    light_samples+=("$sample")
  fi
done < <(find examples -maxdepth 1 -name '*.d' -print0 | sort -z)

common=(-Isrc -I"$build_dir/imports")
case "$compiler_name" in
  dmd) common+=(-defaultlib=druntime -nothrow -checkaction=halt -w); unit=(-unittest);;
  ldc2) common+=(-defaultlib=druntime-ldc -fno-exceptions -checkaction=halt -w); unit=(-unittest);;
  gdc) common+=(-nophoboslib -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fcheckaction=halt -Wall -Werror --param asan-globals=0); unit=(-funittest);;
  *) echo "Unsupported compiler: $compiler" >&2; exit 2;;
esac
link=()
if [[ "$compiler_name" == gdc ]]; then link=(-lgdruntime); fi
extra=()
# Flags are passed as separate script arguments; no shell evaluation.
if (($#)); then extra=("$@"); fi
sample_extra=()
link_extra=()
if ((${#extra[@]} > 0)); then
  for flag in "${extra[@]}"; do
    case "$flag" in
      -cov|--coverage|-fprofile*|-fdump*|-g) ;;
      *) sample_extra+=("$flag") ;;
    esac
    case "$flag" in
      -fprofile-abs-path|-fdump*) ;;
      *) link_extra+=("$flag") ;;
    esac
  done
fi

memory_limit=${MEMORY_LIMIT:-4G}
use_systemd_scope=0
if command -v systemd-run >/dev/null 2>&1 && systemd-run --user --scope -q --unit="npegged-probe-$$-$RANDOM" true >/dev/null 2>&1; then
  use_systemd_scope=1
fi
run_bounded() {
  if ((use_systemd_scope)); then
    systemd-run --user --scope -q --unit="npegged-$$-$RANDOM" -p "MemoryMax=$memory_limit" -p MemorySwapMax=0 "$@"
  else
    "$@"
  fi
}

objects=()
compile_obj() {
  local obj=$1; shift
  objects+=("$obj")
  if [[ "$compiler_name" == gdc ]]; then
    run_bounded "$compiler" -c "${common[@]}" "${unit[@]}" "$@" -o "$obj"
  else
    run_bounded "$compiler" -c "${common[@]}" "${unit[@]}" "$@" "-of=$obj"
  fi
}

if [[ "$compiler_name" == ldc2 ]]; then
  compile_obj "$build_dir/tests-lib.o" ${extra[@]+"${extra[@]}"} "${library[@]}"
  compile_obj "$build_dir/tests-runner.o" ${extra[@]+"${extra[@]}"} tests/runner.d
else
  compile_obj "$build_dir/tests-core.o" ${extra[@]+"${extra[@]}"} "${library[@]}" tests/runner.d
fi

compile_obj "$build_dir/tests-ex-light.o" ${sample_extra[@]+"${sample_extra[@]}"} "${light_samples[@]}"
for heavy in "${heavy_samples[@]}"; do
  name=$(basename "$heavy" .d)
  compile_obj "$build_dir/tests-ex-$name.o" ${sample_extra[@]+"${sample_extra[@]}"} "$heavy"
done

if [[ "$compiler_name" == gdc ]]; then
  run_bounded "$compiler" "${common[@]}" "${unit[@]}" ${link_extra[@]+"${link_extra[@]}"} "${objects[@]}" -o "$build_dir/tests" ${link[@]+"${link[@]}"}
else
  run_bounded "$compiler" "${common[@]}" "${unit[@]}" ${link_extra[@]+"${link_extra[@]}"} "${objects[@]}" "-of=$build_dir/tests" ${link[@]+"${link[@]}"}
fi

run_bounded timeout --preserve-status --kill-after=2s 60s "$build_dir/tests" --DRT-testmode=run-main
