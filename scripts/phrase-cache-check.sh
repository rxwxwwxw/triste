#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
mkdir -p build/X02
for compiler in "${compilers[@]}"; do
 flags=(-Isrc -unittest -w -checkaction=halt)
 case "$compiler" in
 dmd) flags+=(-defaultlib=druntime -nothrow -version=EligibilityGCStress);;
 ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions -d-version=EligibilityGCStress);;
 *) exit 2;;
 esac
 prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/test_phrase_cache.d "-of=build/X02/$compiler.runner"
 prlimit --as=4294967296 -- timeout --kill-after=2s 60s "build/X02/$compiler.runner" --DRT-testmode=run-main > "build/X02/$compiler.txt"
 test "$(tail -1 "build/X02/$compiler.txt")" = 'phrase cache oracle passed'
 python3 - "build/X02/$compiler.txt" <<'PYTHON'
import json, sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text().splitlines()
assert lines[-1] == 'phrase cache oracle passed'
data = json.loads('\n'.join(lines[:-1]))

# Verify adversarial shared-prefix contracts
adv = {r['capacity']: r for r in data['adversarial']}
assert adv[0]['hits'] == 0
assert adv[1]['hits'] > 0
assert adv[1]['rawEvaluations'] < adv[0]['rawEvaluations']

# Verify ping-pong thrashing contracts
pp = {r['capacity']: r for r in data['pingpong']}
assert pp[1]['hits'] == 0 and pp[1]['evictions'] > 0, '1-entry cache must thrash on 2-position ping-pong'
assert pp[2]['hits'] > 0 and pp[2]['evictions'] == 0, '2-entry cache must avoid 2-position thrashing'
PYTHON
 echo "$compiler: phrase cache oracle passed"
done
