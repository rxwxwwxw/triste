#!/usr/bin/env python3
"""List uncovered non-unittest lines of one module from build/cov-ldc (after scripts/coverage_ldc.sh)."""
import re, sys
from pathlib import Path
sys.path.insert(0, 'scripts')
from coverage_model import unittest_lines
name = sys.argv[1]
src = Path(name).read_text().splitlines()
skip = unittest_lines(name)
hits = {}
for report in Path('build/cov-ldc').rglob('*.lst'):
    text = report.read_text().splitlines()
    if text and text[-1].startswith(name + ' '):
        for number, line in enumerate(text[:-1], 1):
            c = re.match(r'^\s*(\d+)\|', line)
            if c: hits[number] = hits.get(number, False) or int(c[1]) > 0
for n in sorted(hits):
    if not hits[n] and n not in skip: print(n, src[n - 1].strip()[:120])
