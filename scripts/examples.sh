#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v timeout >/dev/null 2>&1 && [[ -d /opt/homebrew/opt/coreutils/libexec/gnubin ]]; then
  export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
fi
compiler=${DC:-dmd}
library=()
while IFS= read -r -d '' f; do
  library+=("$f")
done < <(find src -name '*.d' -print0 | sort -z)
flags=(-Isrc)
extra=("$@")
coverage_run=0
case "$(basename "$compiler")" in
 dmd) flags+=(-defaultlib=druntime -nothrow -checkaction=halt -w);;
 ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions -checkaction=halt -w);;
 gdc) flags+=(-nophoboslib -fno-exceptions -fcheckaction=halt -Wall -Werror);;
 *) exit 2;;
esac
compile() {
 local destination=$1; shift
 if [[ $(basename "$compiler") == gdc ]]; then
   "$compiler" "${flags[@]}" ${extra[@]+"${extra[@]}"} "${library[@]}" "$@" -o "$destination" -lgdruntime
 else
   "$compiler" "${flags[@]}" ${extra[@]+"${extra[@]}"} "${library[@]}" "$@" "-of=$destination"
 fi
}
run_case() {
 local expected=$1; shift
 local binary=$1
 local status=0
 timeout --preserve-status --kill-after=2s 30s "$@" || status=$?
 if [[ $status != "$expected" ]]; then echo "$binary exited $status, expected $expected" >&2; return 1; fi
 if [[ -n ${COVERAGE_DIR:-} ]]; then
  coverage_run=$((coverage_run + 1))
  scripts/collect_coverage.sh "$COVERAGE_DIR" "$binary" "examples-$coverage_run"
 fi
}
mkdir -p build
compile build/hotpath-cov tests/hotpath.d
run_case 0 build/hotpath-cov
compile build/generate-parser scripts/generate_parser.d
mkdir -p build/default-generator/src/npegged
(cd build/default-generator && timeout --preserve-status --kill-after=2s 30s ../generate-parser)
if [[ -n ${COVERAGE_DIR:-} ]]; then scripts/collect_coverage.sh "$COVERAGE_DIR" build/generate-parser examples-default; fi
run_case 0 build/generate-parser build/regenerated-parser
run_case 1 build/generate-parser /nonexistent/npegged/parser
# Compare generator output, independently of formatting the checked-in artifact.
if command -v dfmt >/dev/null; then
 dfmt build/regenerated-parser.d > build/regenerated-parser.formatted.d
 cmp src/npegged/parser.d build/regenerated-parser.formatted.d
else
 echo 'dfmt unavailable: bootstrap formatting comparison cannot run' >&2
fi
compile build/generate-pascal -Iexamples/extended_pascal examples/extended_pascal/epgrammar.d examples/extended_pascal/make.d
run_case 0 build/generate-pascal
run_case 1 build/generate-pascal /nonexistent/npegged/epparser
compile build/parse_ep -Ibuild build/epparser.d examples/extended_pascal/app.d
run_case 0 build/parse_ep --text examples/extended_pascal/example.pas > build/example.txt
run_case 0 build/parse_ep --html examples/extended_pascal/example.pas > build/example.html
run_case 0 build/parse_ep --trace --text examples/extended_pascal/example.pas > build/example-trace.txt 2> build/TraceLog.txt
[[ -s build/example.txt && -s build/example.html && -s build/TraceLog.txt ]]
run_case 2 build/parse_ep
run_case 2 build/parse_ep first.pas second.pas
run_case 2 build/parse_ep /nonexistent/npegged/input.pas
printf 'not a pascal program' > build/invalid.pas
run_case 1 build/parse_ep --text build/invalid.pas > build/invalid-output.txt 2> build/invalid-diagnostic.txt
if [[ -c /dev/full ]]; then
  run_case 2 build/parse_ep --text build/invalid.pas > build/invalid-output.txt 2> /dev/full
  run_case 2 build/parse_ep --trace examples/extended_pascal/example.pas > build/trace-error.txt 2> /dev/full
  run_case 2 build/parse_ep --text examples/extended_pascal/example.pas > /dev/full
else
  run_case 2 build/parse_ep --text build/invalid.pas > build/invalid-output.txt 2>&-
  run_case 2 build/parse_ep --trace examples/extended_pascal/example.pas > build/trace-error.txt 2>&-
  run_case 2 build/parse_ep --text examples/extended_pascal/example.pas >&-
fi
for demo in examples/DConf2017/*.d; do
 destination=build/demo-$(basename "$demo" .d)
 compile "$destination" "$demo"
 run_case 0 "$destination"
 if [[ $demo != *naive* ]]; then
   if [[ -c /dev/full ]]; then
     run_case 2 "$destination" > /dev/full
   else
     run_case 2 "$destination" >&-
   fi
 fi
done
