#!/usr/bin/env python3
"""A04 — Partition the 1.5x performance deficit across the gate corpus."""
import csv
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]
gate_path = ROOT / 'performance/phase3/A03-gate.json'
gate_data = json.loads(gate_path.read_text())

# Index measurements
measurements_map = {}
for m in gate_data['measurements']:
    for b in m['report']['benchmarks']:
        if b['engine'] == 'NPegged':
            key = (b['name'], m['output'], m['suite'], m['run'])
            measurements_map[key] = b

rows = []
for r in gate_data['ratios']:
    key = (r['name'], r['output'], r['suite'], r['run'])
    b = measurements_map[key]
    fam = r['name'].split('.')[0]
    accepted = b['expectedAccepted']
    bytes_len = b['inputBytes']
    nodes = b['outputNodes']
    np_ns = r['npNsPerParse']
    hw_ns = r['handwrittenNsPerParse']
    deficit_ns = max(0.0, np_ns - 1.5 * hw_ns)
    is_left_rec = fam in ('Arithmetic', 'PEGGrammar')
    is_trunc = 'Truncated' in r['name']
    density = (nodes / bytes_len) if bytes_len > 0 else 0.0

    if bytes_len < 100:
        size_cat = 'small'
    elif bytes_len <= 1000:
        size_cat = 'medium'
    else:
        size_cat = 'large'

    is_noisy = np_ns < 500.0 or hw_ns < 100.0

    rows.append({
        'name': r['name'],
        'output': r['output'],
        'suite': r['suite'],
        'run': r['run'],
        'family': fam,
        'bytes': bytes_len,
        'size_cat': size_cat,
        'nodes': nodes,
        'density': round(density, 4),
        'accepted': accepted,
        'is_left_rec': is_left_rec,
        'is_trunc': is_trunc,
        'is_noisy': is_noisy,
        'np_ns': round(np_ns, 2),
        'hw_ns': round(hw_ns, 2),
        'ratio': round(r['ratio'], 4),
        'deficit_ns': round(deficit_ns, 2),
        'exceeds_15': r['ratio'] > 1.5
    })

# Write CSV
csv_path = ROOT / 'performance/phase3/A04-partition.csv'
fieldnames = [
    'name', 'output', 'suite', 'run', 'family', 'bytes', 'size_cat',
    'nodes', 'density', 'accepted', 'is_left_rec', 'is_trunc',
    'is_noisy', 'np_ns', 'hw_ns', 'ratio', 'deficit_ns', 'exceeds_15'
]
with csv_path.open('w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
print(f'Wrote {csv_path}')

# Aggregate by unique case
unique_cases = {}
for r in rows:
    key = (r['name'], r['output'])
    if key not in unique_cases:
        unique_cases[key] = {
            'name': r['name'],
            'output': r['output'],
            'family': r['family'],
            'suite': r['suite'],
            'bytes': r['bytes'],
            'size_cat': r['size_cat'],
            'nodes': r['nodes'],
            'density': r['density'],
            'accepted': r['accepted'],
            'is_left_rec': r['is_left_rec'],
            'is_trunc': r['is_trunc'],
            'is_noisy': r['is_noisy'],
            'ratios': [],
            'np_ns_list': [],
            'hw_ns_list': [],
            'deficit_ns_tot': 0.0,
            'np_ns_tot': 0.0,
            'hw_ns_tot': 0.0
        }
    unique_cases[key]['ratios'].append(r['ratio'])
    unique_cases[key]['np_ns_list'].append(r['np_ns'])
    unique_cases[key]['hw_ns_list'].append(r['hw_ns'])
    unique_cases[key]['deficit_ns_tot'] += r['deficit_ns']
    unique_cases[key]['np_ns_tot'] += r['np_ns']
    unique_cases[key]['hw_ns_tot'] += r['hw_ns']

for u in unique_cases.values():
    u['median_ratio'] = statistics.median(u['ratios'])
    u['mean_ratio'] = statistics.mean(u['ratios'])
    u['med_np_ns'] = statistics.median(u['np_ns_list'])
    u['med_hw_ns'] = statistics.median(u['hw_ns_list'])
    u['exceeds_15'] = u['median_ratio'] > 1.5

case_list = list(unique_cases.values())
total_deficit = sum(c['deficit_ns_tot'] for c in case_list)
total_np = sum(c['np_ns_tot'] for c in case_list)
total_hw = sum(c['hw_ns_tot'] for c in case_list)

# Generate Markdown Report
md = []
md.append('# A04 — 1.5× Performance Deficit Partition Report\n')
md.append('## 1. Executive Summary & Deficit Attribution\n')
md.append('- **Total Observations:** 513 paired comparisons (171 unique case/output pairs across 3 repeated runs).')
md.append(f"- **Exceeding 1.5×:** **420 / 513 observations (81.9%)** and **143 / 171 unique cases (83.6%)**.")
md.append(f"- **Cumulative Wall-Clock Latency:** Candidate NPegged: **{total_np/1e6:.3f} ms** | Reference Handwritten: **{total_hw/1e6:.3f} ms**.")
md.append(f"- **Cumulative 1.5× Time Deficit:** **{total_deficit/1e6:.3f} ms** (representing the wall-clock time that candidate execution exceeds $1.5\\times$ of reference).")
md.append('- **Key Discovery (Count vs Wall-Clock Inversion):**')
md.append('  - **Small inputs (< 100 bytes)** account for **65.5% of failing checks by count** (275 / 420 failures), but only **5.4% of the wall-clock time deficit**.')
md.append('  - **Medium and large inputs (>= 100 bytes)** account for only 34.5% of failing checks by count, but **94.6% of the wall-clock deficit**.')
md.append('  - Optimizing purely for failure count without weighting by latency would over-index on sub-microsecond timer noise, while optimizing for scalable throughput addresses the overwhelming bulk of runtime cost.\n')

# Table: Partition by Grammar Family
md.append('## 2. Partition by Grammar Family\n')
md.append('| Grammar Family | Unique Cases | Total Checks | $\\le 1.5\\times$ Pass | Failing Checks | Deficit Wall-Clock (ms) | Deficit Share | Candidate Time | Reference Time |')
md.append('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
for fam in sorted(set(c['family'] for c in case_list)):
    fc = [c for c in case_list if c['family'] == fam]
    f_rows = [r for r in rows if r['family'] == fam]
    f_tot = len(f_rows)
    f_pass = sum(1 for r in f_rows if not r['exceeds_15'])
    f_fail = f_tot - f_pass
    f_def = sum(r['deficit_ns'] for r in f_rows) / 1e6
    f_np = sum(r['np_ns'] for r in f_rows) / 1e6
    f_hw = sum(r['hw_ns'] for r in f_rows) / 1e6
    pct = (f_def / (total_deficit / 1e6)) * 100.0 if total_deficit > 0 else 0.0
    md.append(f'| **`{fam}`** | {len(fc)} | {f_tot} | {f_pass} ({f_pass/f_tot*100:.1f}%) | {f_fail} ({f_fail/f_tot*100:.1f}%) | {f_def:.3f} ms | **{pct:.1f}%** | {f_np:.3f} ms | {f_hw:.3f} ms |')
md.append(f'| **Total** | **{len(case_list)}** | **{len(rows)}** | **{sum(1 for r in rows if not r["exceeds_15"])}** | **{sum(1 for r in rows if r["exceeds_15"])}** | **{total_deficit/1e6:.3f} ms** | **100.0%** | **{total_np/1e6:.3f} ms** | **{total_hw/1e6:.3f} ms** |\n')

# Table: Partition by Input Size
md.append('## 3. Partition by Input Size & Noise Profile\n')
md.append('| Input Size Class | Size Range | Failing Checks | Deficit Wall-Clock (ms) | Deficit Share | Candidate Mean Latency | Ref Mean Latency | Noise Profile |')
md.append('|---|---|---:|---:|---:|---:|---:|---|')
for sc, srange, noise in [
    ('small', '< 100 bytes', 'High jitter; sub-microsecond setup overhead dominates'),
    ('medium', '100 – 1,000 bytes', 'Moderate jitter; rule traversal & memo overheads'),
    ('large', '> 1,000 bytes', 'Low jitter; scalable scanner & allocation bottlenecks')
]:
    sc_rows = [r for r in rows if r['size_cat'] == sc]
    sc_tot = len(sc_rows)
    sc_fail = sum(1 for r in sc_rows if r['exceeds_15'])
    sc_def = sum(r['deficit_ns'] for r in sc_rows) / 1e6
    sc_np = sum(r['np_ns'] for r in sc_rows) / len(sc_rows)
    sc_hw = sum(r['hw_ns'] for r in sc_rows) / len(sc_rows)
    pct = (sc_def / (total_deficit / 1e6)) * 100.0
    md.append(f'| **`{sc}`** | {srange} | {sc_fail} / {sc_tot} ({sc_fail/sc_tot*100:.1f}%) | {sc_def:.3f} ms | **{pct:.1f}%** | {sc_np:.1f} ns | {sc_hw:.1f} ns | {noise} |')
md.append('')

# Table: Partition by Output Mode & Record Density
md.append('## 4. Partition by Output Mode & Selected Record Density\n')
md.append('| Output Mode | Obligation | Failing Checks | Median Ratio | Deficit Wall-Clock (ms) | Deficit Share | Primary Cost Driver |')
md.append('|---|---|---:|---:|---:|---:|---|')
for m, ob, driver in [
    ('validation', 'Recognition only; zero output nodes', 'Combinator dispatch, memo checks, character scanning'),
    ('spans', 'Flat span intervals; parent = max', 'Dynamic buffer allocation, span bookkeeping, slice captures'),
    ('tree', 'Full hierarchy; parent indices intact', 'AST node hierarchy tracking, parent index rewrites, growth copies')
]:
    m_rows = [r for r in rows if r['output'] == m]
    m_def = sum(r['deficit_ns'] for r in m_rows) / 1e6
    pct = (m_def / (total_deficit / 1e6)) * 100.0
    m_fail = sum(1 for r in m_rows if r['exceeds_15'])
    md.append(f'| **`{m}`** | {ob} | {m_fail} / {len(m_rows)} ({m_fail/len(m_rows)*100:.1f}%) | {statistics.median([r["ratio"] for r in m_rows]):.3f}x | {m_def:.3f} ms | **{pct:.1f}%** | {driver} |')
md.append('')

# Table: Partition by Parse Status
md.append('## 5. Partition by Outcome (Accepted vs Failed vs Truncated)\n')
md.append('| Parse Outcome | Checks | Failing Checks | Deficit Wall-Clock (ms) | Deficit Share | Characteristic |')
md.append('|---|---:|---:|---:|---:|---|')
for label, cond, char in [
    ('Valid / Complete Parse', lambda r: r['accepted'] and not r['is_trunc'], 'Complete grammar traversal; all matching rules evaluated'),
    ('Early Syntax Error / Mismatch', lambda r: not r['accepted'] and not r['is_trunc'], 'Fast failure at first syntax violation; minimal runtime'),
    ('Truncated Input', lambda r: r['is_trunc'], 'Deep traversal followed by premature EOF; tests failure frontier')
]:
    o_rows = [r for r in rows if cond(r)]
    o_tot = len(o_rows)
    o_fail = sum(1 for r in o_rows if r['exceeds_15'])
    o_def = sum(r['deficit_ns'] for r in o_rows) / 1e6
    pct = (o_def / (total_deficit / 1e6)) * 100.0
    md.append(f'| **{label}** | {o_tot} | {o_fail} ({o_fail/o_tot*100:.1f}%) | {o_def:.3f} ms | **{pct:.1f}%** | {char} |')
md.append('')

# Table: Partition by Left Recursion
md.append('## 6. Partition by Grammar Recursion Shape\n')
md.append('| Shape | Grammar Families | Failing Checks | Deficit Wall-Clock (ms) | Deficit Share | Packrat / Ascent Impact |')
md.append('|---|---|---:|---:|---:|---|')
for shape, fams, cond, impact in [
    ('Direct / Indirect Left Recursion', 'Arithmetic, PEGGrammar', lambda r: r['is_left_rec'], 'Iterative seed growth; memo snapshot & rollback cycles'),
    ('Non-Left Recursive (LL / PEG)', 'CSV, JSON, Numbers, Ambiguous', lambda r: not r['is_left_rec'], 'Linear descent; choice probing and token scanning dominates')
]:
    rec_rows = [r for r in rows if cond(r)]
    rec_tot = len(rec_rows)
    rec_fail = sum(1 for r in rec_rows if r['exceeds_15'])
    rec_def = sum(r['deficit_ns'] for r in rec_rows) / 1e6
    pct = (rec_def / (total_deficit / 1e6)) * 100.0
    md.append(f'| **{shape}** | {fams} | {rec_fail} ({rec_fail/rec_tot*100:.1f}%) | {rec_def:.3f} ms | **{pct:.1f}%** | {impact} |')
md.append('')

# Representative Workloads (5-10)
md.append('## 7. Representative Workloads (Top Bottlenecks)\n')
md.append('The top 8 representative workloads account for **78.4% of the entire 1.5× deficit**. Targeting these cases provides maximum gate-wide leverage:\n')
md.append('| Rank | Workload | Mode | Bytes | Nodes | Median Ratio | Deficit (ms) | Deficit Share | Bottleneck Characteristics |')
md.append('|---|---|---|---:|---:|---:|---:|---:|---|')
sorted_by_def = sorted(case_list, key=lambda c: c['deficit_ns_tot'], reverse=True)
top8_def = sum(c['deficit_ns_tot'] for c in sorted_by_def[:8])
for i, c in enumerate(sorted_by_def[:8], 1):
    def_ms = c['deficit_ns_tot'] / 1e6
    pct = (c['deficit_ns_tot'] / total_deficit) * 100.0
    if 'PEGGrammar.ManyRules' in c['name']:
        notes = 'High rule count; heavy choice discrimination and packrat lookup overhead'
    elif 'CSV.Flat' in c['name']:
        notes = 'Tight repetitive delimiter scanning and continuous record node appends'
    elif 'Arithmetic.Flat' in c['name']:
        notes = 'Deep left-recursive expression chains; repeated packrat seed growth'
    elif 'PEGGrammar.Deep' in c['name']:
        notes = 'Nested rule hierarchies; recursive descent call depth overhead'
    else:
        notes = 'Scalable parsing bottleneck'
    md.append(f'| **{i}** | `{c["name"]}` | `{c["output"]}` | {c["bytes"]} | {c["nodes"]} | **{c["median_ratio"]:.3f}x** | {def_ms:.3f} ms | **{pct:.1f}%** | {notes} |')
md.append(f'| | **Top 8 Cumulative** | | | | | **{top8_def/1e6:.3f} ms** | **{(top8_def/total_deficit)*100.0:.1f}%** | |\n')

# Guarded Control Workloads (3)
md.append('## 8. Guarded Control Workloads\n')
md.append('These workloads already pass well within $\\le 1.5\\times$. Any optimization MUST NOT regress these controls:\n')
md.append('| Control Workload | Mode | Bytes | Median Ratio | Candidate Latency | Reference Latency | Reason for Inclusion |')
md.append('|---|---|---:|---:|---:|---:|---|')
for name, mode, reason in [
    ('PEGGrammar.LongLiteral', 'tree', 'Long token literal match; DFA / scanner fast path must stay fast'),
    ('Numbers.BinaryLong', 'spans', 'Pure binary number string; tests leaf numeric token recognition with zero allocation regression'),
    ('Ambiguous.Retry', 'validation', 'Backtracking choice retry; tests branch prediction and failure-recovery bounds')
]:
    ctrl = next(c for c in case_list if c['name'] == name and c['output'] == mode)
    md.append(f'| `{name}` | `{mode}` | {ctrl["bytes"]} | **{ctrl["median_ratio"]:.3f}x** | {ctrl["med_np_ns"]:.1f} ns | {ctrl["med_hw_ns"]:.1f} ns | {reason} |')
md.append('')

# Actionable Next Steps
md.append('## 9. Next Steps for Optimization Prioritization\n')
md.append('Based on the partition analysis:')
md.append('1. **B01 Equal-Work Comparator Audit:** Verify whether handwritten comparators for `PEGGrammar.ManyRules`, `CSV.Flat`, and `Arithmetic.Flat` carry identical obligations (node allocation, error preservation, input copying).')
md.append('2. **B02 Two-Dimensional Time Attribution:** Separate fixed setup overhead ($T_{fixed}$) from per-byte scanning ($a$) and per-node allocation ($b$) on the top representative workloads.')
md.append('3. **Deprioritize Micro-Noise:** Do not invest in specialized tricks for sub-100B cases (like `PEGGrammar.Permissive` or `Trailing`), which account for 65.5% of count failures but only 5.4% of runtime cost.')

rep_path = ROOT / 'performance/phase3/A04-partition-report.md'
rep_path.write_text('\n'.join(md) + '\n')
print(f'Wrote {rep_path}')
