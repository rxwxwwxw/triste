#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
mkdir -p build/X01
for compiler in "${compilers[@]}"; do
 flags=(-Isrc -unittest -w -checkaction=halt)
 case "$compiler" in
 dmd) flags+=(-defaultlib=druntime -nothrow -version=EligibilityGCStress);;
 ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions -d-version=EligibilityGCStress);;
 *) exit 2;;
 esac
 prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/prefix_discrimination.d "-of=build/X01/$compiler.runner"
 prlimit --as=4294967296 -- timeout --kill-after=2s 60s "build/X01/$compiler.runner" --DRT-testmode=run-main > "build/X01/$compiler.txt"
 test "$(tail -1 "build/X01/$compiler.txt")" = 'prefix discrimination oracle passed'
 python3 - "build/X01/$compiler.txt" <<'PYTHON'
import json, sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text().splitlines()
assert lines[-1] == 'prefix discrimination oracle passed'

# Line 0: "ab" / "ac"
r1 = json.loads(lines[0])
assert r1[0]['hasOverlap'] is True
assert r1[0]['pairs'][0]['kind'] == 'disjointTails'
assert r1[0]['pairs'][0]['commonPrefix'] == 'a'
assert r1[0]['pairs'][0]['commonPrefixLength'] == 1
assert r1[0]['pairs'][0]['discriminatingDepth'] == 2

# Line 1: "a" / "ab"
r2 = json.loads(lines[1])
assert r2[0]['hasOverlap'] is True
assert r2[0]['pairs'][0]['kind'] == 'shadowed'
assert r2[0]['pairs'][0]['commonPrefix'] == 'a'
assert r2[0]['pairs'][0]['discriminatingDepth'] == 1

# Line 2: "a" eoi / "ab"
r3 = json.loads(lines[2])
assert r3[0]['hasOverlap'] is True
assert r3[0]['pairs'][0]['kind'] == 'guarded'
assert r3[0]['pairs'][0]['commonPrefix'] == 'a'

# Line 3: &'ax' 'a' / 'ab'
r4 = json.loads(lines[3])
assert r4[0]['hasOverlap'] is True
assert r4[0]['pairs'][0]['kind'] == 'guarded'

# Line 4: !'b' 'a' / 'ab'
r5 = json.loads(lines[4])
assert r5[0]['hasOverlap'] is True
assert r5[0]['pairs'][0]['kind'] == 'guarded'

# Line 5: "a" / "b"
r6 = json.loads(lines[5])
assert r6[0]['hasOverlap'] is False
assert r6[0]['pairs'][0]['kind'] == 'disjointFirst'

# Line 6: "ab" / "ac" / "ad"
r7 = json.loads(lines[6])
assert r7[0]['hasOverlap'] is True
assert len(r7[0]['pairs']) == 3
assert all(p['kind'] == 'disjointTails' for p in r7[0]['pairs'])
PYTHON
 echo "$compiler: prefix discrimination oracle passed"
done
if [[ " ${compilers[*]} " == *" dmd "* && " ${compilers[*]} " == *" ldc2 "* ]]; then
 cmp build/X01/dmd.txt build/X01/ldc2.txt
fi
