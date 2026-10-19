#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
mkdir -p build/X03
for compiler in "${compilers[@]}"; do
	flags=(-Isrc -unittest -w -checkaction=halt)
	case "$compiler" in
	dmd) flags+=(-defaultlib=druntime -nothrow -version=EligibilityGCStress);;
	ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions -O3 -d-version=EligibilityGCStress);;
	*) exit 2;;
	esac
	prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/test_recursive_ascent.d "-of=build/X03/$compiler.runner"
	prlimit --as=4294967296 -- timeout --kill-after=2s 60s "build/X03/$compiler.runner" --DRT-testmode=run-main > "build/X03/$compiler.txt"
	test "$(tail -1 "build/X03/$compiler.txt")" = 'recursive ascent oracle passed'
	python3 - "build/X03/$compiler.txt" <<'PYTHON'
import json, sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text().splitlines()
assert lines[-1] == 'recursive ascent oracle passed'
data = json.loads('\n'.join(lines[:-1]))

scaling = {r['terms']: r for r in data['scaling']}
assert len(scaling) == 7, f'expected 7 scaling data points, got {len(scaling)}'
for terms in (16, 32, 64, 128, 256, 512, 1024):
    assert terms in scaling
    # Recursive ascent must allocate less or equal memory compared to packrat seed growth
    assert scaling[terms]['ascentBytes'] <= scaling[terms]['packratBytes']

# At 64+ terms, recursive ascent achieves speedup >= 1.5x by avoiding quadratic seed-growth re-evaluations
assert scaling[1024]['speedup'] >= 1.5, f"expected speedup >= 1.5 at 1024 terms, got {scaling[1024]['speedup']}"
PYTHON
	echo "$compiler: recursive ascent oracle passed"
done
