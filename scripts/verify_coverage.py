#!/usr/bin/env python3
"""Reject missing, stale, or insufficient DMD and gcov coverage for src/ modules."""
import argparse
import gzip
import hashlib
import json
import re
from coverage_model import read_cfg, source_edges, unittest_lines
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--threshold', type=float, default=90)
parser.add_argument('--lines', type=Path, default=Path('build/coverage/lines'))
parser.add_argument('--branches', type=Path, default=Path('build/coverage/branches'))
args = parser.parse_args()
errors = []
sources = sorted(Path('src').rglob('*.d'))
source_names = {str(source) for source in sources}
manifest = args.branches.parent / 'sources.json'
if manifest.exists():
    for name, expected in json.loads(manifest.read_text()).items():
        if name not in source_names: continue
        if not Path(name).is_file() or hashlib.sha256(Path(name).read_bytes()).hexdigest() != expected:
            errors.append(f'{name}: changed during coverage collection')
else: errors.append('Missing source hashes for coverage collection')

line_reports = {}
no_code = set()
line_hits = {}
for report in args.lines.rglob('*.lst'):
    text = report.read_text()
    match = re.search(r'([^\n]+) (?:is [\d.]+% covered|has no code)', text)
    if not match: continue
    name = str(Path(match[1].strip()))
    if Path(name).is_absolute():
        try: name = str(Path(name).relative_to(Path.cwd()))
        except ValueError: continue
    hits = line_hits.setdefault(name, {})
    for number, line in enumerate(text.splitlines(), 1):
        counter = re.match(r'^\s*(\d+)\|', line)
        if counter: hits[number] = hits.get(number, False) or int(counter[1]) > 0
    old_time = line_reports.get(name, (0, report.stat().st_mtime))[1]
    percentage = sum(hits.values()) / len(hits) * 100 if hits else 100.0
    line_reports[name] = (percentage, min(old_time, report.stat().st_mtime))
    if not hits: no_code.add(name)
    else: no_code.discard(name)
cfg_files = list(args.branches.rglob('*.profile'))
if not cfg_files: errors.append('Missing GDC control-flow dump; cannot distinguish invariant checks')
cfg_by_dir = {p.parent: read_cfg([p]) for p in cfg_files}
global_cfg = None
branches = {}
branch_times = {}
for report in args.branches.rglob('*.gcov.json.gz'):
    if report.parent in cfg_by_dir:
        cfg = cfg_by_dir[report.parent]
    else:
        # Most reports have their own CFG. Avoid reparsing gigabytes of dumps
        # merely to construct a fallback that those reports never use.
        if global_cfg is None:
            global_cfg = read_cfg(cfg_files)
        cfg = global_cfg
    with gzip.open(report, 'rt') as stream:
        data = json.load(stream)
    for source in data.get('files', []):
        name = source['file']
        if Path(name).is_absolute():
            try: name = str(Path(name).relative_to(Path.cwd()))
            except ValueError: continue
        virtual = re.search(r'-mixin-(\d+)$', name)
        parent = name[:virtual.start()] if virtual else name
        if not Path(parent).is_file(): continue
        tests = unittest_lines(parent)
        if virtual and int(virtual[1]) in tests: continue
        excluded = set() if virtual else tests
        edges = source_edges(source, cfg, excluded)
        combined = branches.setdefault(parent, {})
        for identity, hit in edges.items():
            key = (name, *identity)
            combined[key] = combined.get(key, False) or hit
        branch_times[parent] = min(branch_times.get(parent, report.stat().st_mtime), report.stat().st_mtime)
summary = {}
for name, edges in branches.items():
    summary[name] = {
        'hit': sum(edges.values()), 'total': len(edges),
        'percent': sum(edges.values()) / len(edges) * 100 if edges else 100,
        'uncovered': [list(identity) for identity, hit in edges.items() if not hit],
    }
(args.branches.parent / 'summary.json').write_text(json.dumps(summary, indent=2))
for source in sorted(sources):
    name = str(source)
    # Definition-only modules have no executable lines or branches to instrument.
    lines = line_reports.get(name)
    if lines is None:
        errors.append(f'{name}: missing line coverage')
    elif lines[1] < source.stat().st_mtime:
        errors.append(f'{name}: stale line coverage')
    elif lines[0] <= args.threshold:
        errors.append(f'{name}: line coverage {lines[0]:.2f}% must exceed {args.threshold}%')
    entry = branches.get(name)
    if name in no_code and entry is None: continue
    if entry is None:
        errors.append(f'{name}: missing branch coverage')
    elif branch_times[name] < source.stat().st_mtime:
        errors.append(f'{name}: stale branch coverage')
    elif entry and sum(entry.values()) / len(entry) * 100 <= args.threshold:
        errors.append(f'{name}: branch coverage {sum(entry.values()) / len(entry) * 100:.2f}% must exceed {args.threshold}%')
if errors:
    raise SystemExit('\n'.join(errors))
print('All executable src/ modules exceed the line and branch coverage threshold.')
