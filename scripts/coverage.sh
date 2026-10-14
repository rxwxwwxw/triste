#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
timeout 10s python3 scripts/test_coverage_model.py
rm -rf build/coverage
mkdir -p build/coverage/lines build/coverage/branches
# Prevent a source edit during compilation from being mistaken for fresh coverage.
python3 - <<'PY'
import hashlib,json
from pathlib import Path
sources = [*Path('src').rglob('*.d'), *Path('examples').rglob('*.d'), *Path('scripts').glob('*.d'), *Path('tests').glob('*.d')]
Path('build/coverage/sources.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}))
PY
find . -maxdepth 1 -name '*.lst' -delete
DC=dmd scripts/build.sh -cov
scripts/collect_coverage.sh build/coverage build/dmd/tests dmd-unit
COVERAGE_DIR=build/coverage DC=dmd scripts/examples.sh -cov
find build -name '*.gcda' -delete
DC=gdc scripts/build.sh --coverage -fprofile-abs-path -fdump-ipa-profile-details-blocks-lineno
scripts/collect_coverage.sh build/coverage build/gdc/tests gdc-unit
COVERAGE_DIR=build/coverage DC=gdc scripts/examples.sh --coverage -fprofile-abs-path -fdump-ipa-profile-details-blocks-lineno
while IFS= read -r -d '' notes; do
 directory=$(dirname "$notes")
 basename=$(basename "$notes")
 (cd "$directory" && gcov --json-format --branch-probabilities "$basename" >/dev/null)
done < <(find build/coverage/branches -name '*.gcno' -print0)
python3 scripts/verify_coverage.py --threshold 90
