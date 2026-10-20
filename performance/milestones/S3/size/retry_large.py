#!/usr/bin/env python3
"""Retry only A5's two 200-rule native compilations under an explicit 16 GiB budget."""
import csv
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
recipe = HERE / 'account.py'
namespace = {'__file__': str(recipe)}
exec(recipe.read_text().split('try:\n    for feature')[0], namespace)
previous = json.loads((HERE / 'metadata.json').read_text())
archive = HERE / 'failed-eight-gib'
archive.mkdir(exist_ok=False)
for name in ('default.csv', 'lean.csv', 'metadata.json'):
    (archive / name).write_bytes((HERE / name).read_bytes())
for feature in ('default', 'lean'):
    failed = [r for r in previous['runs'] if r['feature'] == feature and r['returncode']
              and any(str(arg).endswith('synthetic-large_unit.d') for arg in r['command'])]
    assert failed
    command = failed[-1]['command']
    command = command[command.index('ldc2'):]
    namespace['feature'] = feature
    result, seconds, rss = namespace['measure_native'](command)
    path = HERE / (feature + '.csv')
    with path.open() as stream:
        reader = csv.DictReader(stream)
        columns = reader.fieldnames
        rows = list(reader)
    for row in rows:
        if row['grammar'] != 'synthetic-large':
            continue
        obj = Path(next(arg.removeprefix('-of=') for arg in command if arg.startswith('-of=')))
        row.update(compile_seconds=f'{seconds:.2f}' if result.returncode == 0 else 'FAILED',
                   object_bytes=str(obj.stat().st_size) if result.returncode == 0 else 'N/A',
                   peak_rss_kib=str(rss) if result.returncode == 0 else 'N/A')
    with path.open('w') as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    print(feature, 'returncode', result.returncode, 'seconds', seconds, 'peak RSS KiB', rss, flush=True)
previous['runs'].extend(namespace['records'])
previous['large_compile_address_limit_bytes'] = 17179869184
previous['runtime_and_other_command_address_limit_bytes'] = 4294967296
previous['native_resource_measurement'] = 'per-child POSIX wait4, includes reaped descendants'
previous['large_compile_note'] = 'Both baseline and candidate exceeded 4 GiB and 8 GiB native-compiler caps. Only the 200-rule native compiler retry uses 16 GiB; runtime/test budgets remain unchanged. Earlier attempts are retained.'
previous['supplementary_source_hashes'] = {str(p.relative_to(namespace['ROOT'])):hashlib.sha256(p.read_bytes()).hexdigest()
    for p in (recipe, Path(__file__).resolve(), HERE / 'gen_source_scoped.d')}
(HERE / 'metadata.json').write_text(json.dumps(previous, indent=2) + '\n')
