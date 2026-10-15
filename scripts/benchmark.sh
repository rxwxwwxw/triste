#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

compiler=${DC:-ldc2}
build_dir=build/$(basename "$compiler")
mkdir -p "$build_dir"

mapfile -d '' library < <(find src -name '*.d' -print0 | sort -z)
mapfile -d '' pegged_sources < <(find third-party/Pegged/pegged -maxdepth 2 -name '*.d' ! -name 'tester*' ! -name 'tohtml*' -print0 | sort -z)
mapfile -d '' handwritten_sources < <(find benchmark/handwritten -name '*.d' -print0 | sort -z)

common=(
  -I.
  -Isrc
  -Iexamples
  -Ibenchmark
  -Ithird-party/Pegged
  -Ithird-party/Pegged/examples/arithmetic/src
  -Ithird-party/Pegged/examples/json/src
  -Ithird-party/Pegged/examples/csv/src
  -Ithird-party/Pegged/examples/numbers/src
)

flags=()
output=()
case "$(basename "$compiler")" in
  dmd)
    flags=(-O -inline -release -w -de -checkaction=halt)
    output=(-of="$build_dir/benchmark_runner")
    ;;
  ldc2)
    flags=(-O3 -release -boundscheck=off -w -de -checkaction=halt)
    output=(-of="$build_dir/benchmark_runner")
    ;;
  gdc)
    flags=(-O3 -frelease -fno-bounds-check -Wall -Werror -fcheckaction=halt)
    output=(-o "$build_dir/benchmark_runner")
    ;;
  *)
    echo "Unsupported compiler: $compiler" >&2
    exit 2
    ;;
esac

echo "Building benchmark runner with $compiler..." >&2
"$compiler" --version >&2
printf 'Build flags: %s\n' "${flags[*]}" >&2
if [[ -r /proc/cpuinfo ]]; then
  rg -m 1 'model name|Hardware' /proc/cpuinfo >&2 || true
fi
"$compiler" "${common[@]}" "${flags[@]}" \
  "${library[@]}" \
  "${pegged_sources[@]}" \
  "${handwritten_sources[@]}" \
  examples/arithmetic.d third-party/Pegged/examples/arithmetic/src/pegged/examples/arithmetic.d \
  examples/json.d third-party/Pegged/examples/json/src/pegged/examples/json.d \
  examples/csv.d third-party/Pegged/examples/csv/src/pegged/examples/csv.d \
  examples/numbers.d third-party/Pegged/examples/numbers/src/pegged/examples/numbers.d \
  benchmark/json_grammar.d benchmark/json_npegged.d benchmark/json_pegged.d \
  benchmark/ambiguous_npegged.d benchmark/ambiguous_pegged.d \
  benchmark/options.d benchmark/measurement.d \
  benchmark/json_output.d benchmark/json_comparison.d benchmark/workload_grammars.d \
  benchmark/runner.d \
  "${output[@]}"

echo "Running benchmarks against vendored Pegged..." >&2
timeout --preserve-status --kill-after=5s 120s "$build_dir/benchmark_runner" "$@"
