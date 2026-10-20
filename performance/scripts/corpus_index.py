#!/usr/bin/env python3
"""Q2: write performance/corpora/index.tsv, the flat list the benchmark runner reads (--corpus-index).

Columns: name, family, label, valid, bytes, sha256, path. `label` is the dashboard label: real | synthetic |
learned | adversarial (learned = synthetic output of a model fitted to the real corpus). Paths are relative to the
repository root. Large entries are listed even though their files are not committed; the runner skips a missing
file and the gate records which entries were present.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'performance/corpora/manifest.json'
INDEX = ROOT / 'performance/corpora/index.tsv'
COLUMNS = ['name', 'family', 'label', 'valid', 'bytes', 'sha256', 'path']


def dashboard_label(entry):
    provenance = entry.get('provenance', '')
    if entry.get('label') == 'real':
        return 'real'
    if provenance.startswith('adversarial') or entry.get('label') == 'adversarial':
        return 'adversarial'
    if provenance.startswith('synthetic-learned'):
        return 'learned'
    return 'synthetic'


def rows(manifest):
    result = []
    for entry in manifest.get('generated', []):
        result.append([entry['name'], entry['family'], dashboard_label(entry), int(entry['valid']),
                       entry['bytes'], entry['sha256'], entry['path']])
    for entry in manifest.get('real', []):
        # The per-milestone snapshots are near-duplicates of the baseline ones; the index keeps the distinct ones.
        if (not entry['name'].endswith('.json') or entry['family'] != 'json'
                or entry['name'].startswith('milestones_')):
            continue
        result.append([entry['name'].rsplit('.', 1)[0], entry['family'], 'real', 1, entry['bytes'],
                       entry['sha256'], entry['path']])
    for row in result:
        for cell in row:
            assert '\t' not in str(cell) and '\n' not in str(cell)
    return sorted(result, key=lambda row: (row[1], row[2], row[0]))


def render(manifest):
    return '\n'.join('\t'.join(str(cell) for cell in row) for row in [COLUMNS] + rows(manifest)) + '\n'


def main():
    INDEX.write_text(render(json.loads(MANIFEST.read_text())))
    print(f'wrote {INDEX.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
