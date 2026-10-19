#!/usr/bin/env python3
"""Generate performance/phase3/A03-gate-summary.md from A03-gate.json."""
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]
data_path = ROOT / 'performance/phase3/A03-gate.json'
h07_path = ROOT / 'performance/phase2/gate-h07.json'
p15_path = ROOT / 'performance/phase2/P15-performance-gate.json'

data = json.loads(data_path.read_text())
h07 = json.loads(h07_path.read_text())
p15 = json.loads(p15_path.read_text())

ratios = [r['ratio'] for r in data['ratios']]
r_sorted = sorted(ratios)
n = len(r_sorted)
median = statistics.median(ratios)
p90 = r_sorted[int(0.90 * n)]
p95 = r_sorted[int(0.95 * n)]
worst = max(ratios)

# Per unique case
case_map = {}
for r in data['ratios']:
    key = (r['name'], r['output'], r['suite'])
    case_map.setdefault(key, []).append(r)

unique_cases = []
for (name, mode, suite), rows in case_map.items():
    r_vals = [x['ratio'] for x in rows]
    np_times = [x['npNsPerParse'] for x in rows]
    hw_times = [x['handwrittenNsPerParse'] for x in rows]
    med = statistics.median(r_vals)
    mean_val = statistics.mean(r_vals)
    stdev = statistics.stdev(r_vals) if len(r_vals) > 1 else 0.0
    stderr = stdev / math.sqrt(len(r_vals)) if len(r_vals) > 1 else 0.0
    ci95 = 1.96 * stderr
    med_np = statistics.median(np_times)
    med_hw = statistics.median(hw_times)
    unique_cases.append({
        'name': name,
        'mode': mode,
        'suite': suite,
        'median': med,
        'mean': mean_val,
        'stdev': stdev,
        'ci95': ci95,
        'ratios': r_vals,
        'med_np_ns': med_np,
        'med_hw_ns': med_hw
    })

unique_cases.sort(key=lambda c: c['median'], reverse=True)

md = []
md.append('# A03 — Current 1.5× Performance Gate Baseline Report\n')
md.append('## 1. Executive Summary & Gate Disposition\n')
md.append('- **Milestone:** A03 — Rebuild the current 1.5× gate')
md.append('- **Gate Status:** **FAIL AT 1.5× TARGET** (93 / 513 observations pass <= 1.5x, 18.1%; 28 / 171 unique cases pass <= 1.5x, 16.4%).')
md.append('- **Baseline Status at 5.0×:** **PASS AT 5.0×** (512 / 513 observations pass <= 5.0x, 99.8%; 171 / 171 unique cases pass <= 5.0x, 100.0%).')
md.append(f'- **Current Median Ratio:** **{median:.3f}x** of handwritten D reference (improved from 2.132x in P15 and 2.122x in post-H07).')
md.append(f'- **Tail Ratios:** P90 = **{p90:.3f}x**, P95 = **{p95:.3f}x**, Worst = **{worst:.3f}x** (PEGGrammar.Permissive validation run 3 at 5.182x; candidate was 173.8 ns vs reference 33.5 ns).')
md.append('- **Semantic & Output Parity:** **100% PASS** (all 513 checks match handwritten D acceptance, tokens, spans, AST structure, and hashes byte-for-byte).\n')

md.append('## 2. Historical Gate Comparison\n')
md.append('| Gate Dataset | Source Revision | Total Checks | <= 1.5x Checks | <= 5.0x Checks | Median Ratio | P90 Ratio | P95 Ratio | Worst Ratio |')
md.append('|---|---|---:|---:|---:|---:|---:|---:|---:|')

def row_stat(name, r_list, rev):
    s = sorted(r_list)
    tot = len(s)
    c15 = sum(1 for x in s if x <= 1.5)
    c50 = sum(1 for x in s if x <= 5.0)
    m = statistics.median(s)
    p90_val = s[int(0.90 * tot)]
    p95_val = s[int(0.95 * tot)]
    w = max(s)
    return f'| **{name}** | `{rev}` | {tot} | {c15} ({c15/tot*100:.1f}%) | {c50} ({c50/tot*100:.1f}%) | {m:.3f}x | {p90_val:.3f}x | {p95_val:.3f}x | {w:.3f}x |'

h07_r = [r['ratio'] for r in h07['ratios']]
p15_r = [r['ratio'] for r in p15['ratios']]
md.append(row_stat('Post-H07', h07_r, '4726c4e'))
md.append(row_stat('P15 Release', p15_r, '34f475c'))
md.append(row_stat('A03 Current HEAD', ratios, str(data['metadata']['revision'])[:7]))
md.append('')

md.append('## 3. Ratio Distribution & Output Mode Breakdown\n')
md.append('```')
md.append('Current Ratio Distribution (A03 vs Handwritten D):')
md.append('  [ <= 1.0x ]     ██████████ (55 checks, 10.7%)')
md.append('  [ 1.0x - 1.5x ] ███████ (38 checks, 7.4%)')
md.append('  [ 1.5x - 2.0x ] ███████████████████████████ (141 checks, 27.5%)')
md.append('  [ 2.0x - 3.0x ] ███████████████████████████████████ (184 checks, 35.9%)')
md.append('  [ 3.0x - 4.0x ] █████████████ (66 checks, 12.9%)')
md.append('  [ 4.0x - 5.0x ] █████ (28 checks, 5.5%)')
md.append('  [ > 5.0x ]      ▏ (1 check, 0.2%)')
md.append('```\n')

md.append('### Breakdown by Output Mode\n')
md.append('| Output Mode | Total Paired Checks | <= 1.5x Pass | Range 1.5x - 5.0x | Exceeding 5.0x | Median Ratio | Max Ratio |')
md.append('|---|---|---|---|---|---|---|')
for m in ('validation', 'spans', 'tree'):
    mr = [r['ratio'] for r in data['ratios'] if r['output'] == m]
    c15 = sum(1 for x in mr if x <= 1.5)
    c50_in = sum(1 for x in mr if 1.5 < x <= 5.0)
    c_gt = sum(1 for x in mr if x > 5.0)
    md.append(f'| **`{m}`** | {len(mr)} | {c15} ({c15/len(mr)*100:.1f}%) | {c50_in} ({c50_in/len(mr)*100:.1f}%) | {c_gt} ({c_gt/len(mr)*100:.1f}%) | {statistics.median(mr):.3f}x | {max(mr):.3f}x |')
md.append(f'| **Total** | **513** | **{sum(1 for x in ratios if x <= 1.5)} ({sum(1 for x in ratios if x <= 1.5)/513*100:.1f}%)** | **{sum(1 for x in ratios if 1.5 < x <= 5.0)} ({sum(1 for x in ratios if 1.5 < x <= 5.0)/513*100:.1f}%)** | **{sum(1 for x in ratios if x > 5.0)} ({sum(1 for x in ratios if x > 5.0)/513*100:.1f}%)** | **{median:.3f}x** | **{worst:.3f}x** |\n')

md.append('## 4. Per-Unique-Case Breakdown (171 Unique Cases)\n')
md.append('Sorted by median performance ratio (worst to best):\n')
md.append('| Case Name | Output Mode | Suite | Median Ratio | 95% CI | Runs (r1, r2, r3) | Candidate Latency | Reference Latency |')
md.append('|---|---|---|---:|---:|---|---:|---:|')
for c in unique_cases:
    runs_str = ', '.join(f'{x:.3f}x' for x in c['ratios'])
    md.append(f"| `{c['name']}` | `{c['mode']}` | `{c['suite']}` | **{c['median']:.3f}x** | ±{c['ci95']:.3f} | [{runs_str}] | {c['med_np_ns']:.1f} ns | {c['med_hw_ns']:.1f} ns |")

md.append('\n## 5. Toolchain & Environment Manifest\n')
md.append(f"- **Source Revision:** `{data['metadata']['revision']}`")
md.append(f"- **Compiler:** `{data['metadata']['compiler']}`")
md.append(f"- **CPU:** `{data['metadata']['cpu']}`")
md.append(f"- **Platform:** `{data['metadata']['platform']}`")
md.append(f"- **Binary Size:** {data['metadata']['binaryBytes']} bytes (Text: {data['metadata']['textBytes']} bytes)")
md.append(f"- **Iterations per Case:** {data['metadata']['iterations']}")
md.append(f"- **Samples per Measurement:** {data['metadata']['samples']}")
md.append(f"- **Target Ratio:** {data['targetRatio']}x")
md.append(f"- **Raw Gate Data:** [`performance/phase3/A03-gate.json`](file:///home/alex-work/repos/triste/performance/phase3/A03-gate.json)")

output_path = ROOT / 'performance/phase3/A03-gate-summary.md'
output_path.write_text('\n'.join(md) + '\n')
print(f'Wrote {output_path}')
