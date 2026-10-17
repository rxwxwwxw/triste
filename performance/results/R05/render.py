"""Render the archived R05 work/memory data; no timing inference."""
import csv
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parent
with (folder / 'ldc2.csv').open() as stream:
    rows = list(csv.DictReader(stream))
x = [int(r['depth']) for r in rows]
fig, axes = plt.subplots(1, 2, figsize=(11, 4), layout='constrained')
for key, label in [('flat_snapshot_bytes', 'flat snapshot copies'),
                   ('shared_frozen_bytes', 'shared frozen bytes'),
                   ('shared_replay_bytes', 'final shared replay')]:
    axes[0].plot(x, [int(r[key]) for r in rows], marker='.', label=label)
for key, label in [('flat_peak', 'flat snapshot arena'),
                   ('shared_peak', 'shared fragment arena'),
                   ('scratch_peak', 'replay stack arena')]:
    axes[1].plot(x, [int(r[key]) for r in rows], marker='.', label=label)
for ax in axes:
    ax.set_xscale('log', base=2)
    ax.set_yscale('log', base=2)
    ax.set_xlabel('growth depth / final nodes')
    ax.set_ylabel('bytes')
    ax.grid(alpha=.2)
    ax.legend()
axes[0].set_title('Cumulative work (shared curves coincide)')
axes[1].set_title('Retained arena bytes at completion')
fig.suptitle('R05 isolated deep growth: exact equal-output oracle')
fig.savefig(folder / 'deep-growth.svg')
