#!/usr/bin/env python3
"""Validate focused PEG probe cohorts and retain optimized-code evidence."""
import csv
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys

CASES = ('Permissive', 'Truncated', 'Trailing', 'Deep')


def measurements(paths):
    groups = {}
    for path in paths:
        with path.open() as stream:
            rows = list(csv.DictReader(stream))
        expected = {(case, cohort, str(sample)) for case in CASES
                    for cohort in ('end-to-end', 'stages') for sample in range(7)}
        identities = [(r['case'], r['cohort'], r['sample']) for r in rows]
        if len(rows) != len(expected) or set(identities) != expected:
            raise ValueError(f'incomplete or duplicate samples: {path}')
        for row in rows:
            if int(row['iterations']) != 2000 or int(row['total_ns']) <= 0:
                raise ValueError(f'invalid sample: {path}')
            groups.setdefault((row['case'], row['cohort']), []).append(row)
    if len(paths) != 3:
        raise ValueError('require three independent runs')
    return groups


def assembly_evidence(path):
    functions = {}
    name = None
    for line in path.read_text().splitlines():
        match = re.match(r'^[0-9a-f]+ <(.+)>:$', line)
        if match:
            candidate = match[1]
            name = candidate if ('benchmark.diagnostics.peg_probe.BenchPEG.' in candidate
                    and 'State!(false, 1)' in candidate
                    and re.search(r'\.(?:_cursor_|_)(?:TopBoundary|SequenceBoundary|Prefix|Primary|Definition|Sp)[!(]', candidate)) else None
            if name:
                functions[name] = dict(calls=0, conditionalBranches=0, instructions=0, callExamples=[])
        elif name and (instruction := re.match(r'^\s*[0-9a-f]+:\s+(?:[0-9a-f]{2}\s+)+\s*([a-z][a-z0-9]*)\s*(.*)', line)):
            item = functions[name]
            mnemonic = instruction[1]
            item['instructions'] += 1
            item['conditionalBranches'] += mnemonic.startswith('j') and mnemonic not in ('jmp', 'jmpq')
            if mnemonic.startswith('call'):
                item['calls'] += 1
                if len(item['callExamples']) < 12:
                    item['callExamples'].append(line.strip())
    if not functions:
        raise ValueError(f'no focused recognition symbols: {path}')
    return dict(assemblySha256=hashlib.sha256(path.read_bytes()).hexdigest(), functions=functions)


def main():
    source, destination = map(Path, sys.argv[1:])
    destination.mkdir(parents=True, exist_ok=True)
    lines = ['| Backend / memo | Input | Median ns/parse | Setup % | Body % | Teardown % |',
             '|---|---|---:|---:|---:|---:|']
    evidence = {}
    for backend in ('combinators', 'direct'):
        for memo in ('selective', 'full'):
            prefix = f'{backend}-{memo}'
            paths = [source / f'{prefix}-run{run}.csv' for run in (1, 2, 3)]
            groups = measurements(paths)
            for path in [*paths, *(source / f'{prefix}-run{run}.trace.csv' for run in (1, 2, 3)), source / f'{prefix}.metadata.json']:
                (destination / path.name).write_bytes(path.read_bytes())
            metadata = json.loads((source / f'{prefix}.metadata.json').read_text())
            if any(hashlib.sha256(Path(p).read_bytes()).hexdigest() != digest
                   for p, digest in metadata['sources'].items()):
                raise ValueError('probe sources changed during collection')
            evidence[prefix] = assembly_evidence(source / f'{prefix}.assembly.txt')
            for case in CASES:
                elapsed = statistics.median(int(r['total_ns']) / 2000 for r in groups[case, 'end-to-end'])
                stages = groups[case, 'stages']
                totals = [sum(int(r[field]) for r in stages)
                          for field in ('setup_ns', 'body_ns', 'teardown_ns')]
                percentages = [100 * value / sum(totals) for value in totals]
                lines.append(f'| {backend}/{memo} | {case} | {elapsed:.1f} | ' + ' | '.join(f'{v:.2f}' for v in percentages) + ' |')
    (destination / 'timing-summary.md').write_text('\n'.join(lines) + '\n')
    (destination / 'assembly-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
