"""Summarize a complete R06 matrix without promoting the experimental policy."""
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics
import sys

folder = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent / 'matrix')
metadata = list(folder.glob('*.metadata.json'))
assert len(metadata) == 48, f'expected 48 policy cohorts, found {len(metadata)}'
source_pins = None
raw = {}
metrics = {}
binaries = {}
for path in metadata:
    data = json.loads(path.read_text())
    if source_pins is None:
        source_pins = data['sourceHashes']
    assert source_pins == data['sourceHashes'], 'mixed source revisions'
    name = path.name.removesuffix('.metadata.json')
    backend, memo, selector, policy, mode = name.split('-')
    binaries[backend, memo, selector, policy, mode] = data['binarySha256']
    rows = []
    for filename, digest in data['rawHashes'].items():
        source = folder / filename
        assert hashlib.sha256(source.read_bytes()).hexdigest() == digest, filename
        with source.open() as stream:
            cohort = list(csv.DictReader(stream))
        assert len(cohort) == (68 if mode == 'metrics' else 476), filename
        rows.extend(cohort)
    for row in rows:
        case = tuple(row[k] for k in ('grammar', 'shape', 'size', 'valid'))
        key = backend, memo, selector, policy, case
        if mode == 'metrics':
            assert key not in metrics
            metrics[key] = row
        else:
            raw.setdefault(key, []).append(int(row['ns']) / int(row['iterations']))
for key, digest in binaries.items():
    backend, memo, selector, policy, mode = key
    if policy == 'candidate':
        assert digest == binaries[backend, memo, selector, 'control', mode]
ratios = []
for key, samples in raw.items():
    backend, memo, selector, policy, case = key
    assert len(samples) == 21
    if policy != 'candidate':
        continue
    reference = raw[backend, memo, selector, 'reference', case]
    control = raw[backend, memo, selector, 'control', case]
    per_run = [statistics.median(samples[i:i+7]) / statistics.median(reference[i:i+7])
               for i in (0, 7, 14)]
    ratios.append(dict(backend=backend, memo=memo, selector=selector, grammar=case[0],
                       shape=case[1], size=int(case[2]), valid=int(case[3]),
                       candidate_reference=statistics.median(samples) / statistics.median(reference),
                       control_reference=statistics.median(control) / statistics.median(reference),
                       candidate_control=statistics.median(samples) / statistics.median(control),
                       ratios_by_run=per_run))
ratios.sort(key=lambda r: r['candidate_reference'], reverse=True)
report = dict(decision='retain-experimental-only; no-default-promotion', timedSamples=sum(map(len, raw.values())),
              counterSamples=len(metrics), cohorts=len(metadata),
              worstCases=ratios[:30], sourceHashes=source_pins,
              note='No default promotion. Snapshot work and flat replay are separate mechanisms.')
(folder.parent / 'analysis.json').write_text(json.dumps(report, indent=2) + '\n')
with (folder.parent / 'ratios.csv').open('w') as stream:
    writer = csv.DictWriter(stream, fieldnames=ratios[0].keys(), lineterminator='\n')
    writer.writeheader()
    writer.writerows(ratios)
lines = ['# R06 complete timing matrix', '',
         'Ratios below 1 favor the enabled candidate. All timing builds exclude metrics.', '',
         '| Backend | Memo | Grammar / case | Candidate/reference | Control/reference | Three run ratios |',
         '|---|---|---|---:|---:|---|']
for row in sorted(ratios, key=lambda r: (r['backend'], r['memo'], r['grammar'], r['size'])):
    if row['selector'] != 'all' or not row['valid']:
        continue
    if row['size'] != 2048 and not (row['shape'] == 'siblings' and row['size'] in (16,32,512)) and row['shape'] != 'control':
        continue
    lines.append(f"| {row['backend']} | {row['memo']} | {row['grammar']} {row['shape']} {row['size']} | "
                 f"{row['candidate_reference']:.3f} | {row['control_reference']:.3f} | "
                 + '/'.join(f'{v:.3f}' for v in row['ratios_by_run']) + ' |')
lines += ['', '## Worst measured cases', '']
for row in ratios[:12]:
    lines.append(f"- {row['backend']}/{row['memo']}/{row['selector']} {row['grammar']} "
                 f"{row['shape']} {row['size']} valid={row['valid']}: "
                 f"{row['candidate_reference']:.3f}× reference, {row['candidate_control']:.3f}× compiled-off control.")
(folder.parent / 'timing-summary.md').write_text('\n'.join(lines) + '\n')
import matplotlib
matplotlib.use('Agg')
matplotlib.rcParams['svg.hashsalt'] = 'R06'
import matplotlib.pyplot as plt
fig, axes = plt.subplots(2, 4, figsize=(16, 8), layout='constrained')
for column, (backend, memo) in enumerate((b,m) for b in ('combinators','direct') for m in ('selective','full')):
    for row_index, grammar in enumerate(('DirectChain','IndirectChain')):
        ax = axes[row_index,column]
        for policy in ('reference','candidate'):
            selected = [(int(case[2]), row) for (b,m,s,p,case),row in metrics.items()
                        if (b,m,s,p,case[0],case[1],case[3]) == (backend,memo,'all',policy,grammar,'flat','1')]
            selected.sort()
            x = [n for n,_ in selected]
            for field, label, style in [('snapshot_bytes','snapshot copies','-'),
                                        ('restore_bytes','flat replay','--'),
                                        ('peak','retained arena bytes',':')]:
                ax.plot(x,[int(r[field]) for _,r in selected],style,label=f'{policy} {label}')
        ax.set_xscale('log',base=2);ax.set_yscale('log',base=2)
        ax.set_title(f'{backend}/{memo}/{grammar}')
        ax.set_xlabel('terms');ax.set_ylabel('bytes');ax.grid(alpha=.2)
handles,labels=axes[0,0].get_legend_handles_labels()
fig.legend(handles,labels,loc='outside lower center',ncol=3)
fig.suptitle('R06 snapshot copying, flat replay and arena retention')
figure_path = folder.parent / 'copying-and-memory.svg'
fig.savefig(figure_path, metadata={'Date': None})
figure_path.write_text('\n'.join(line.rstrip() for line in figure_path.read_text().splitlines()) + '\n')

# Large-range exponents distinguish frozen snapshots from unavoidable flat replay.
scaling = []
for backend in ('combinators', 'direct'):
    for memo in ('selective', 'full'):
        for grammar in ('DirectChain', 'IndirectChain'):
            for policy in ('reference', 'candidate'):
                first_case = (grammar, 'flat', '512', '1')
                last_case = (grammar, 'flat', '2048', '1')
                first = metrics[backend, memo, 'all', policy, first_case]
                last = metrics[backend, memo, 'all', policy, last_case]
                values = {field: math.log(int(last[field]) / int(first[field]), 4)
                          for field in ('snapshot_bytes', 'restore_bytes', 'peak', 'requested')}
                values['time'] = math.log(
                    statistics.median(raw[backend, memo, 'all', policy, last_case]) /
                    statistics.median(raw[backend, memo, 'all', policy, first_case]), 4)
                scaling.append(dict(backend=backend, memo=memo, grammar=grammar,
                                    policy=policy, exponents=values,
                                    last={field: int(last[field]) for field in
                                          ('snapshot_bytes', 'restore_bytes', 'peak', 'requested', 'nodes')}))
report['scaling512to2048'] = scaling
compile_ratios = []
for path in metadata:
    if '-candidate-timing.' not in path.name:
        continue
    candidate = json.loads(path.read_text())
    reference = json.loads(Path(str(path).replace('-candidate-', '-reference-')).read_text())
    compile_ratios.append(candidate['compileWallSeconds'] / reference['compileWallSeconds'])
report['compileWallRatio'] = dict(median=statistics.median(compile_ratios), maximum=max(compile_ratios),
                                note='One compile per unique binary, two concurrent jobs; descriptive, not a repeated compiler benchmark.')
(folder.parent / 'analysis.json').write_text(json.dumps(report, indent=2) + '\n')
with (folder.parent / 'timing-summary.md').open('a') as stream:
    stream.write('\n## Large-range scaling\n\nExponents from 512 to 2048 terms; 1 is linear and 2 is quadratic.\n\n')
    stream.write('| Backend/memo | Grammar | Policy | Snapshot | Replay | Retained | Time |\n|---|---|---|---:|---:|---:|---:|\n')
    for row in scaling:
        v = row['exponents']
        stream.write(f"| {row['backend']}/{row['memo']} | {row['grammar']} | {row['policy']} | "
                     f"{v['snapshot_bytes']:.2f} | {v['restore_bytes']:.2f} | {v['peak']:.2f} | {v['time']:.2f} |\n")
