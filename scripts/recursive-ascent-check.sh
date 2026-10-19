#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
mkdir -p build/X03
for compiler in "${compilers[@]}"; do
	flags=(-Isrc -unittest -w -de -checkaction=halt)
	case "$compiler" in
	dmd) flags+=(-defaultlib=druntime -nothrow -version=EligibilityGCStress);;
	ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions -O3 -d-version=EligibilityGCStress);;
	*) exit 2;;
	esac
    python3 - "build/X03/$compiler.command.json" "$compiler" "${flags[@]}" "${library[@]}" tests/test_recursive_ascent.d "-of=build/X03/$compiler.runner" <<'COMMAND'
import json,sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps(sys.argv[2:],indent=2)+'\n')
COMMAND
	prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/test_recursive_ascent.d "-of=build/X03/$compiler.runner"
	prlimit --as=4294967296 -- timeout --kill-after=2s 60s "build/X03/$compiler.runner" --DRT-testmode=run-main > "build/X03/$compiler.txt"
	test "$(tail -1 "build/X03/$compiler.txt")" = 'recursive ascent oracle passed'
	python3 - "build/X03/$compiler.txt" <<'PYTHON'
import json, sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text().splitlines()
assert lines[-1] == 'recursive ascent oracle passed'
data = json.loads('\n'.join(lines[:-1]))

assert data['schemaVersion'] == 2 and data['repetitions'] == 7
assert data['generalEquivalent'] is False
assert data['disposition'] == 'SPECIALIZED_MANUAL_ONLY'
assert data['comparisonCount'] == len(data['cases']) == 273
assert data['completeParityFailures'] > 0 and data['ascentCalls'] > 0
assert all(bool(result[1]) == (result[0] == 0)
           for row in data['cases'] for result in (row['reference'], row['candidate']))
assert {r['repeat'] for r in data['cases']} == set(range(1, 8))
assert {r['family'] for r in data['cases']} == {'flat', 'branch', 'step', 'depth', 'memory', 'depth64terms'}
# A complete-field comparison exposes a real limitation hidden by the old
# comparator; it must not be converted into an "equivalent parser" speed gate.
examples = [r for r in data['cases'] if r['family'] == 'flat' and r['inputHex'] == '312b31']
assert len(examples) == 7
assert all(not r['completeEqual'] and r['difference'] == 'tree.failEnd' for r in examples)

PYTHON
	echo "$compiler: recursive ascent limitation audit passed; general equivalence rejected"
done
