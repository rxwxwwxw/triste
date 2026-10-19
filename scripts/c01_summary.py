#!/usr/bin/env python3
"""Summarize separate C01 timing and active-operation evidence; save crossover curves."""
import csv
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'performance/phase3/C01'


def main():
    rows = list(csv.DictReader((DEST / 'observations.csv').open()))
    groups, metrics = {}, {}
    for row in rows:
        identity = tuple(row[k] for k in ('selector', 'finite', 'grammar', 'shape', 'size', 'valid'))
        if row['diagnostic'] == 'True':
            metrics[(*identity, row['policy'])] = row
        else:
            group = (*identity, row['policy'])
            groups.setdefault(group, {}).setdefault(int(row['run']), []).append(int(row['ns']) / int(row['iterations']))
    summary = []
    for key, rounds in sorted(groups.items()):
        if key[-1] != 'on':
            continue
        base = groups[(*key[:-1], 'flat')]
        off = groups[(*key[:-1], 'off')]
        ratios = [statistics.median(rounds[r]) / statistics.median(base[r]) for r in sorted(rounds)]
        off_ratios = [statistics.median(off[r]) / statistics.median(base[r]) for r in sorted(rounds)]
        m = metrics[key]
        summary.append(dict(zip(('selector', 'finite', 'grammar', 'shape', 'size', 'valid'), key[:-1])) | dict(
            medianOnOverFlat=statistics.median(ratios), runRatios=ratios,
            runRatioRange=[min(ratios), max(ratios)], medianOffOverFlat=statistics.median(off_ratios),
            medianFlatNs=statistics.median(statistics.median(v) for v in base.values()),
            medianOnNs=statistics.median(statistics.median(v) for v in rounds.values()),
            inputBytes=int(m['input_bytes']), nodes=int(m['nodes']), policySelected=int(m['policy_selected']),
            sharedSnapshots=int(m['shared_snapshots']), sharedReplays=int(m['shared_replays']),
            reusedNodes=int(m['reused_nodes']), frozenNodes=int(m['frozen_nodes']),
            flatSnapshotBytes=int(metrics[(*key[:-1], 'flat')]['snapshot_bytes']),
            activeSnapshotBytes=int(m['snapshot_bytes']), activeRestoreBytes=int(m['restore_bytes']),
            flatRestoreBytes=int(metrics[(*key[:-1], 'flat')]['restore_bytes']),
            growthCopyBytes=int(m['growth_copy_bytes'])))
    (DEST / 'summary.json').write_text(json.dumps(dict(milestone='C01', comparisons=summary), indent=2) + '\n')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 3, figsize=(13, 4), sharey=True, layout='constrained')
    for axis, (grammar, shape) in zip(axes, [('DirectChain', 'flat'), ('IndirectChain', 'flat'), ('NestedChain', 'siblings')]):
        for selector, color in [('all', '#0072B2'), ('expr', '#D55E00'), ('root', '#009E73')]:
            for valid, style in [('1', '-'), ('0', '--')]:
                data = sorted((r for r in summary if r['grammar'] == grammar and r['shape'] == shape
                    and r['selector'] == selector and r['finite'] == 'False' and r['valid'] == valid),
                    key=lambda r: int(r['size']))
                axis.plot([int(r['size']) for r in data], [r['medianOnOverFlat'] for r in data],
                          style, color=color, marker='.', label=f'{selector}, {"success" if valid == "1" else "late failure"}')
        axis.axhline(1, color='black', linewidth=.7)
        axis.set_xscale('log', base=2); axis.set_xlabel('Terms / sibling groups')
        axis.set_title(f'{grammar}: {shape}'); axis.grid(alpha=.2)
    axes[0].set_ylabel('Shared request / flat latency (lower is faster)')
    axes[-1].legend(fontsize=7)
    fig.suptitle('C01: unlimited active-policy crossover; root-only is ineligible')
    fig.savefig(DEST / 'crossover.svg')
    plt.close(fig)
    for r in summary:
        if r['selector'] in ('all', 'expr') and r['finite'] == 'False' and r['valid'] == '1' and r['size'] in ('64', '128', '512', '2048'):
            print(r['selector'], r['grammar'], r['shape'], r['size'], round(r['medianOnOverFlat'], 3), r['sharedSnapshots'], r['sharedReplays'])


if __name__ == '__main__':
    main()
