#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Source-branch coverage still requires GDC 16/gcov; DMD line coverage alone
# cannot establish the required branch threshold. Do not silently skip this gate.
for tool in dmd gdc gcov; do
  command -v "$tool" >/dev/null || {
    echo "Coverage collector requires $tool (GDC is not a compiler compliance target)." >&2
    exit 2
  }
done
timeout 10s python3 scripts/test_coverage_model.py
timeout 10s python3 scripts/test_verify_coverage.py
rm -rf build/coverage
mkdir -p build/coverage/lines build/coverage/branches
# Prevent a source edit during compilation from being mistaken for fresh coverage.
python3 - <<'PY'
import hashlib,json
from pathlib import Path
sources = list(Path('src').rglob('*.d'))
Path('build/coverage/sources.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}))
PY
find . -maxdepth 1 -name '*.lst' -delete
dmd_extra=()
gdc_extra=()
if [[ "${SHARED_OUTPUT_COVERAGE:-0}" == 1 ]]; then
 dmd_extra=(-version=NPeggedSharedOutput -version=NPeggedMetrics)
 gdc_extra=(-fversion=NPeggedSharedOutput -fversion=NPeggedMetrics)
fi
if [[ "${PURE_ISLANDS_COVERAGE:-0}" == 1 ]]; then
 dmd_extra+=(-version=NPeggedPureIslands -version=NPeggedMetrics)
 gdc_extra+=(-fversion=NPeggedPureIslands -fversion=NPeggedMetrics)
fi
if [[ "${SCANNER_METRICS_COVERAGE:-0}" == 1 ]]; then
 dmd_extra+=(-version=NPeggedScannerMetrics)
 gdc_extra+=(-fversion=NPeggedScannerMetrics)
fi
DC=dmd scripts/build.sh -cov "${dmd_extra[@]}"
scripts/collect_coverage.sh build/coverage build/dmd/tests dmd-unit
COVERAGE_DIR=build/coverage DC=dmd scripts/examples.sh -cov
find build \( -name '*.gcda' -o -name '*.gcno' -o -name '*.profile' \) -delete
DC=gdc scripts/build.sh --coverage -fprofile-abs-path -fdump-ipa-profile-details-blocks-lineno "${gdc_extra[@]}"
scripts/collect_coverage.sh build/coverage build/gdc/tests gdc-unit
COVERAGE_DIR=build/coverage DC=gdc scripts/examples.sh --coverage -fprofile-abs-path -fdump-ipa-profile-details-blocks-lineno
if [[ "${SHARED_OUTPUT_COVERAGE:-0}" == 1 ]]; then
 mapfile -t library < <(rg --files src -g '*.d' | sort)
 mkdir -p build/coverage-oracle
 dmd -Isrc -defaultlib=druntime -nothrow -w -unittest -cov "${dmd_extra[@]}" "${library[@]}" tests/shared_output.d -of=build/coverage-oracle/dmd-oracle
 prlimit --as=4294967296 -- timeout --kill-after=2s 60s build/coverage-oracle/dmd-oracle --DRT-testmode=run-main > build/coverage-oracle/dmd.txt
 scripts/collect_coverage.sh build/coverage build/coverage-oracle/dmd-oracle dmd-shared-output
 gdc -Isrc -nophoboslib -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fcheckaction=halt -Wall -Werror -funittest --coverage -fprofile-abs-path -fdump-ipa-profile-details-blocks-lineno "${gdc_extra[@]}" "${library[@]}" tests/shared_output.d -o build/coverage-oracle/gdc-oracle -lgdruntime
 prlimit --as=4294967296 -- timeout --kill-after=2s 60s build/coverage-oracle/gdc-oracle --DRT-testmode=run-main > build/coverage-oracle/gdc.txt
 scripts/collect_coverage.sh build/coverage build/coverage-oracle/gdc-oracle gdc-shared-output
fi
if [[ "${SCANNER_METRICS_COVERAGE:-0}" == 1 ]]; then
 mapfile -t library < <(rg --files src -g '*.d' | sort)
 mkdir -p build/coverage-scanner
 dmd -Isrc -J. -defaultlib=druntime -nothrow -w -unittest -cov -version=NPeggedScannerMetrics "${library[@]}" tests/scanner_report.d -of=build/coverage-scanner/dmd-scanner
 prlimit --as=4294967296 -- timeout --kill-after=2s 60s build/coverage-scanner/dmd-scanner --DRT-testmode=run-main > build/coverage-scanner/dmd.txt
 scripts/collect_coverage.sh build/coverage build/coverage-scanner/dmd-scanner dmd-scanner-report
 gdc -Isrc -J. -nophoboslib -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fcheckaction=halt -Wall -Werror -funittest --coverage -fprofile-abs-path -fdump-ipa-profile-details-blocks-lineno -fversion=NPeggedScannerMetrics "${library[@]}" tests/scanner_report.d -o build/coverage-scanner/gdc-scanner -lgdruntime
 prlimit --as=4294967296 -- timeout --kill-after=2s 60s build/coverage-scanner/gdc-scanner --DRT-testmode=run-main > build/coverage-scanner/gdc.txt
 scripts/collect_coverage.sh build/coverage build/coverage-scanner/gdc-scanner gdc-scanner-report
fi
while IFS= read -r -d '' notes; do
 directory=$(dirname "$notes")
 basename=$(basename "$notes")
 (cd "$directory" && gcov --json-format --branch-probabilities "$basename" >/dev/null)
done < <(find build/coverage/branches -name '*.gcno' -print0)
python3 scripts/verify_coverage.py --threshold 90
