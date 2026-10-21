#!/usr/bin/env bash
# Line coverage with LDC's -cov: unit tests plus the example programs, unioned, unittest bodies excluded.
# Branch coverage needs GDC/gcov and is not measured here.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v timeout >/dev/null 2>&1 && [[ -d /opt/homebrew/opt/coreutils/libexec/gnubin ]]; then export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"; fi
root=$PWD
out=build/cov-ldc
rm -rf "$out"; mkdir -p "$out"
library=()
while IFS= read -r -d '' f; do library+=("$f"); done < <(find src -name '*.d' -print0 | sort -z)
run() { # name expected-exit sources... ; extra flags in FLAGS
  local name=$1 expected=$2; shift 2
  mkdir -p "$out/$name"
  ldc2 -Isrc -I. -w -cov -checkaction=C ${FLAGS:-} "${library[@]}" "$@" "-of=$out/$name/bin" >/dev/null
  local status=0
  (cd "$out/$name" && timeout 900 "$root/$out/$name/bin" ${ARGS:-} >/dev/null 2>&1) || status=$?
  [[ $status == "$expected" ]] || { echo "$name exited $status, expected $expected" >&2; exit 1; }
}
mkdir -p "$out/unit"
ldc2 -Isrc -I. -w -cov -checkaction=C -unittest -main "${library[@]}" "-of=$out/unit/bin" >/dev/null
timeout 1500 "$out/unit/bin" >/dev/null 2>&1 # the unit tests use paths relative to the repository root
mv -f ./*.lst "$out/unit/"
FLAGS="" run hotpath 0 tests/hotpath.d
FLAGS="" run tagged 0 tests/tagged_regions.d
mkdir -p "$out/generator"
ldc2 -Isrc -w -cov -checkaction=C "${library[@]}" scripts/generate_parser.d "-of=$out/generator/bin" >/dev/null
mkdir -p "$out/generator/run/src/npegged"
(cd "$out/generator/run" && timeout 120 "$root/$out/generator/bin" >/dev/null 2>&1) || true
python3 - <<'PY'
import re, sys
from pathlib import Path
sys.path.insert(0, 'scripts')
from coverage_model import unittest_lines
hits = {}
for report in Path('build/cov-ldc').rglob('*.lst'):
    text = report.read_text().splitlines()
    if not text: continue
    m = re.match(r'(.+?) (?:is [\d.]+% covered|has no code)$', text[-1])
    if not m: continue
    name = m[1].strip()
    if not name.startswith('src/'): continue
    h = hits.setdefault(name, {})
    for number, line in enumerate(text[:-1], 1):
        c = re.match(r'^\s*(\d+)\|', line)
        if c: h[number] = h.get(number, False) or int(c[1]) > 0
bad = 0
for name in sorted(hits):
    skip = unittest_lines(name)
    lines = {n: v for n, v in hits[name].items() if n not in skip}
    pct = 100.0 * sum(lines.values()) / len(lines) if lines else 100.0
    flag = '' if pct > 90 else '  <-- below 90%'
    bad += bool(flag)
    print(f'{pct:6.1f}%  {name}{flag}')
print('modules at or below 90%:', bad)
PY
rm -f ./*.lst
