#!/usr/bin/env python3
"""Reproduce Unicode 17 tables from vendored UCD files, without Python-version dependencies."""
import argparse
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
source = root / 'third-party/unicode'
folds = {}
for line in (source / 'CaseFolding.txt').read_text().splitlines():
    line = line.split('#', 1)[0].strip()
    if not line: continue
    scalar, status, mapping, _ = line.split(';')
    if status.strip() in ('C', 'F'):
        folds[int(scalar, 16)] = [int(value, 16) for value in mapping.split()]
alpha = set()
start = None
for line in (source / 'UnicodeData.txt').read_text().splitlines():
    fields = line.split(';')
    scalar, name, category = int(fields[0], 16), fields[1], fields[2]
    if name.endswith(', First>'): start = scalar; continue
    if category.startswith('L') or category == 'Nl':
        alpha.update(range(start if start is not None else scalar, scalar + 1))
    start = None
for line in (source / 'PropList.txt').read_text().splitlines():
    line = line.split('#', 1)[0].strip()
    if not line: continue
    points, prop = line.split(';')
    if prop.strip() != 'Other_Alphabetic': continue
    bounds = [int(value, 16) for value in points.strip().split('..')]
    alpha.update(range(bounds[0], bounds[-1] + 1))
ranges = []
for scalar in sorted(alpha):
    if ranges and ranges[-1][1] + 1 == scalar: ranges[-1][1] = scalar
    else: ranges.append([scalar, scalar])
rows = []
for scalar, mapping in sorted(folds.items()):
    escaped = ''.join(f'\\U{value:08x}' for value in mapping)
    rows.append(f'    Fold(0x{scalar:x}, "{escaped}"),')
updated = """/** Unicode 17.0.0 data. Copyright 2025 Unicode, Inc. Unicode-3.0 license.
    Code: Boost 1.0. See third-party/unicode/LICENSE and scripts/generate_unicode.py. */
module npegged.unicode;
private struct Fold { dchar scalar; string text; }
private immutable Fold[] folds = [
""" + '\n'.join(rows) + '\n];\n'
updated += 'private struct LetterRange { dchar first, last; }\nprivate immutable LetterRange[] letters = [\n'
updated += '\n'.join(f'    LetterRange(0x{a:x}, 0x{b:x}),' for a, b in ranges) + '\n];\n'
updated += """
/// Full case-fold expansion, or null for an unchanged scalar.
string folded(dchar scalar) @nogc nothrow pure {
    size_t lo, hi = folds.length;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (folds[mid].scalar < scalar) lo = mid + 1;
        else hi = mid;
    }
    return lo < folds.length && folds[lo].scalar == scalar ? folds[lo].text : null;
}
@nogc nothrow unittest {
    assert(folded('A') == "a"); assert(folded('Σ') == "σ");
    assert(folded('ß') == "ss"); assert(folded('a') is null);
    assert(folded(dchar.max) is null);
}
/// Unicode Alphabetic property, independent of the process locale.
bool isAlphabetic(dchar scalar) @nogc nothrow pure {
    size_t lo, hi = letters.length;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (letters[mid].last < scalar) lo = mid + 1;
        else hi = mid;
    }
    return lo < letters.length && letters[lo].first <= scalar;
}
@nogc nothrow unittest {
    assert(isAlphabetic('a')); assert(isAlphabetic('Σ')); assert(isAlphabetic('漢'));
    assert(isAlphabetic(cast(dchar)0x345)); assert(!isAlphabetic('1'));
    assert(!isAlphabetic(' ')); assert(!isAlphabetic(dchar.max));
}
"""
with tempfile.NamedTemporaryFile(suffix='.d', mode='w', encoding='utf8') as temporary:
    temporary.write(updated); temporary.flush()
    updated = subprocess.check_output(['dfmt', '--config', str(root), temporary.name], text=True)
path = root / 'src/npegged/unicode.d'
if args.check:
    if updated != path.read_text(): raise SystemExit('Unicode tables differ from reproducible generator output')
else: path.write_text(updated)
