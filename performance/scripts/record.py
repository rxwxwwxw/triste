#!/usr/bin/env python3
"""Convert a scripts/performance_gate.py report into the performance/ contract layout (A1).

Usage: record.py REPORT.json --baseline | --milestone ID [--notes TEXT]
Writes metadata.json, raw.csv, summary.csv, correctness.json, notes.md, appends trends.csv
and regenerates latest.md. Existing run directories are never overwritten.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import platform
import subprocess
import sys
import time

PERF = Path(__file__).resolve().parents[1]
ROOT = PERF.parent
HARNESS_VERSION = 'a1-1'
RAW_COLUMNS = ['run_id', 'workload_id', 'implementation', 'compiler', 'mode', 'iteration',
               'input_bytes', 'elapsed_ns', 'successful', 'output_digest', 'status']
SUMMARY_COLUMNS = ['run_id', 'workload_id', 'implementation', 'compiler', 'mode', 'n_samples',
                   'median_ns', 'p95_ns', 'bytes_per_second', 'handwritten_median_ns',
                   'slowdown_ratio', 'correctness_ok']
TREND_COLUMNS = ['run_id', 'kind', 'compiler', 'commit', 'workloads', 'within_target',
                 'pct_within_target', 'p50', 'p90', 'p95', 'geomean', 'worst', 'worst_workload']
TARGET = 1.5


def percentile(values, fraction):
    """Nearest-rank-with-interpolation percentile of a nonempty list."""
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    low = math.floor(position)
    high = math.ceil(position)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def implementation_name(engine):
    return {'NPegged': 'npegged', 'Handwritten': 'handwritten'}.get(engine, engine.lower())


def build_tables(report, run_id):
    """Return (raw_rows, summary_rows, correctness) from a gate report.

    Raises ValueError if any measured implementation lacks per-sample data, so a partial
    report can never become a baseline. Missing handwritten baselines give 'N/A'.
    """
    compiler = report['metadata']['compiler']
    raw, groups = [], {}
    for index, measurement in enumerate(report['measurements']):
        mode = measurement['output']
        for row in measurement['report']['benchmarks']:
            samples = row.get('sampleMs')
            if not samples or row['iterations'] <= 0:
                raise ValueError(f"No samples: {row['name']}/{row['engine']}")
            impl = implementation_name(row['engine'])
            workload = f"{measurement['suite']}/{row['name']}/{mode}"
            key = (workload, impl)
            groups.setdefault(key, dict(mode=mode, bytes=row['inputBytes'], hashes=set(),
                                        accepted=row['expectedAccepted'], ns=[]))
            groups[key]['hashes'].add(row['outputHash'])
            for sample, ms in enumerate(samples):
                ns = ms * 1e6 / row['iterations']
                groups[key]['ns'].append(ns)
                raw.append(dict(run_id=run_id, workload_id=workload, implementation=impl,
                                compiler=compiler, mode=mode,
                                iteration=measurement['run'] * 1000 + sample,
                                input_bytes=row['inputBytes'], elapsed_ns=f'{ns:.3f}',
                                successful=str(bool(row['expectedAccepted'])).lower(),
                                output_digest=f"{row['outputHash']:016x}", status='ok'))
    summary, mismatches = [], []
    for (workload, impl), group in sorted(groups.items()):
        hand = groups.get((workload, 'handwritten'))
        digests_equal = hand is None or group['hashes'] == hand['hashes']
        if not digests_equal:
            mismatches.append(dict(workload=workload, implementation=impl,
                                   digests=sorted(map(str, group['hashes']))))
        median = percentile(group['ns'], 0.5)
        hand_median = percentile(hand['ns'], 0.5) if hand else None
        ratio = 'N/A'
        if impl != 'handwritten' and hand_median:
            ratio = f'{median / hand_median:.4f}'
        elif impl == 'handwritten':
            ratio = 'N/A'
        summary.append(dict(run_id=run_id, workload_id=workload, implementation=impl,
                            compiler=compiler, mode=group['mode'], n_samples=len(group['ns']),
                            median_ns=f'{median:.3f}', p95_ns=f"{percentile(group['ns'], .95):.3f}",
                            bytes_per_second=f"{group['bytes'] / median * 1e9:.1f}",
                            handwritten_median_ns='N/A' if hand_median is None else f'{hand_median:.3f}',
                            slowdown_ratio=ratio, correctness_ok=str(digests_equal).lower()))
    return raw, summary, dict(ok=not mismatches, mismatches=mismatches,
                              note='Outputs are verified equal by the gate before timing; '
                                   'digests are re-compared here.')


def dashboard_stats(summary):
    ratios = [(float(r['slowdown_ratio']), r['workload_id']) for r in summary
              if r['implementation'] == 'npegged' and r['slowdown_ratio'] != 'N/A'
              and r['correctness_ok'] == 'true']
    if not ratios:
        return None
    values = [v for v, _ in ratios]
    worst = max(ratios)
    return dict(workloads=len(values), within_target=sum(v <= TARGET for v in values),
                pct_within_target=100.0 * sum(v <= TARGET for v in values) / len(values),
                p50=percentile(values, .5), p90=percentile(values, .9), p95=percentile(values, .95),
                geomean=math.exp(sum(map(math.log, values)) / len(values)),
                worst=worst[0], worst_workload=worst[1])


LEXICAL = ('Numbers.', 'CSV.', 'PEGGrammar.')
FAILURE_WORDS = ('Truncated', 'Trailing', 'Invalid', 'Empty', 'Permissive')
NESTED = ('Arithmetic.Deep', 'Arithmetic.Nested', 'Arithmetic.Flat', 'Arithmetic.Unary', 'JSON.DeepNesting',
          'PEGGrammar.Deep', 'PEGGrammar.ManyRules')


def workload_name(workload_id):
    """`suite/Name/mode` -> Name."""
    parts = workload_id.split('/')
    return parts[1] if len(parts) >= 2 else workload_id


def workload_label(workload_id):
    """Corpus provenance label: real | synthetic | learned | adversarial, or `fixture` for in-repo cases."""
    name = workload_name(workload_id)
    marker = '.corpus.'
    if marker in name:
        return name.split(marker, 1)[1].split('.', 1)[0]
    return 'fixture'


def workload_family(workload_id):
    """Benchmark family of section 1. Explicit `.family.<f>.` names win; otherwise a name-based classification."""
    name = workload_name(workload_id)
    if '.family.' in name:
        return name.split('.family.', 1)[1].split('.', 1)[0]
    if '.corpus.' in name:
        return 'corpus_' + name.split('.', 1)[0].lower()
    if name.startswith('Ambiguous.'):
        return 'pathological'
    if any(name.startswith(prefix) for prefix in NESTED):
        return 'nested_expr'
    if name.startswith('JSON.') and 'Invalid' in name:
        return 'failure'
    if any(word in name for word in FAILURE_WORDS) and not name.startswith('JSON.'):
        return 'failure'
    if name.startswith('JSON.'):
        return 'structured'
    if name.startswith(LEXICAL) or name.startswith('Arithmetic.'):
        return 'lex_ascii'
    return 'other'


def family_breakdown(summary):
    """Per (family, label) counts of paired npegged workloads, those within target and the geomean/worst ratio.
    Workloads without a handwritten twin are counted as `no_twin` and never given a ratio."""
    groups = {}
    for row in summary:
        if row['implementation'] != 'npegged':
            continue
        key = (workload_family(row['workload_id']), workload_label(row['workload_id']))
        group = groups.setdefault(key, dict(ratios=[], no_twin=0))
        if row['slowdown_ratio'] == 'N/A' or row['correctness_ok'] != 'true':
            group['no_twin'] += 1
        else:
            group['ratios'].append((float(row['slowdown_ratio']), row['workload_id']))
    rows = []
    for (family, label), group in sorted(groups.items()):
        values = [v for v, _ in group['ratios']]
        rows.append(dict(family=family, label=label, workloads=len(values) + group['no_twin'],
                         paired=len(values), no_twin=group['no_twin'],
                         within_target=sum(v <= TARGET for v in values),
                         geomean=f"{math.exp(sum(map(math.log, values)) / len(values)):.4f}" if values else 'N/A',
                         worst=f"{max(values):.4f}" if values else 'N/A'))
    return rows


FAMILY_COLUMNS = ['family', 'label', 'workloads', 'paired', 'no_twin', 'within_target', 'geomean', 'worst']


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def tool_version(command):
    try:
        out = subprocess.run(command, capture_output=True, text=True, timeout=20).stdout
        return out.splitlines()[0] if out else 'unknown'
    except (OSError, subprocess.TimeoutExpired):
        return 'unavailable'


def write_csv(path, columns, rows):
    with path.open('w', newline='') as handle:
        writer = csv.DictWriter(handle, columns, lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def corpus_manifest(report):
    entries = []
    for suite, value in report['corpora'].items():
        if suite == 'handwritten-workload-outputs':
            continue
        for case in value:
            data = json.dumps(case, sort_keys=True).encode()
            entries.append(dict(suite=suite, name=case['name'], grammar=case.get('grammar'),
                                bytes=((len(case['input'].encode('latin-1')) if case.get('inputLatin1') else len(case['input'].encode()))
                                   if 'input' in case else None),
                                expected_accepted=case['expectedAccepted'], timed=case['timed'],
                                sha256=hashlib.sha256(data).hexdigest(),
                                origin='in-repo fixture exported by scripts/benchmark.sh'))
    return sorted(entries, key=lambda e: (e['suite'], e['name']))


def run_metadata(run_id):
    paths = [PERF / 'baselines' / run_id / 'metadata.json']
    paths += list((PERF / 'milestones').glob('*/' + run_id + '/metadata.json'))
    for path in paths:
        if path.is_file():
            return json.loads(path.read_text())
    return {}


def comparable(left, right):
    """Missing provenance never establishes a controlled before/after comparison."""
    keys = ('host', 'architecture', 'cpu', 'os', 'compiler', 'flags', 'backend',
            'workloads_revision', 'corpus_checksums', 'cpu_pinning',
            'iterations_per_sample', 'warmups', 'sanitizers')
    if not all(left.get(key) and right.get(key)
               and left[key] not in ('unknown', 'N/A')
               and right[key] not in ('unknown', 'N/A') for key in keys):
        return False
    compiler_version = 'ldc' if left['compiler'] == 'ldc2' else 'dmd'
    return (all(left[key] == right[key] for key in keys)
            and bool(left.get(compiler_version))
            and left[compiler_version] not in ('unknown', 'N/A')
            and left.get(compiler_version) == right.get(compiler_version))


def family_section(run_id):
    """Per-family / provenance-label table of the newest run (runs recorded before Q2 have none)."""
    paths = [PERF / 'baselines' / run_id / 'families.csv']
    paths += list((PERF / 'milestones').glob('*/' + run_id + '/families.csv'))
    for path in paths:
        if path.is_file():
            with path.open() as handle:
                rows = list(csv.DictReader(handle))
            lines = ['', '## Families and corpus labels (newest run)', '',
                     'Labels: `fixture` = in-repo case, `real`/`synthetic`/`learned`/`adversarial` = G7 corpora. '
                     '`no_twin` workloads have no equal-output handwritten baseline and carry no ratio.', '',
                     '| family | label | workloads | paired | no_twin | within target | geomean | worst |',
                     '|---|---|---|---|---|---|---|---|']
            for r in rows:
                lines.append(f"| {r['family']} | {r['label']} | {r['workloads']} | {r['paired']} | {r['no_twin']} "
                             f"| {r['within_target']}/{r['paired']} | {r['geomean']} | {r['worst']} |")
            return lines
    return []


def regenerate_latest():
    """Rebuild latest.md from trends.csv and the newest run's summary."""
    trends_path = PERF / 'trends.csv'
    if not trends_path.exists():
        (PERF / 'latest.md').write_text('# Performance dashboard\n\nNo measured runs yet.\n')
        return
    with trends_path.open() as handle:
        rows = list(csv.DictReader(handle))
    last = rows[-1]
    lines = ['# Performance dashboard', '',
             'Generated from `performance/trends.csv`; do not edit by hand.', '',
             f"Latest run: `{last['run_id']}` ({last['kind']}, {last['compiler']}, commit {last['commit'][:9]})", '',
             f"- Workloads within {TARGET}x: {last['within_target']}/{last['workloads']} "
             f"({float(last['pct_within_target']):.1f}%)",
             f"- Slowdown p50/p90/p95: {float(last['p50']):.2f} / {float(last['p90']):.2f} / {float(last['p95']):.2f}",
             f"- Geometric mean: {float(last['geomean']):.2f}x",
             f"- Worst: {float(last['worst']):.2f}x ({last['worst_workload']})"]
    compatible = [row for row in rows[:-1]
                  if comparable(run_metadata(last['run_id']), run_metadata(row['run_id']))]
    if compatible:
        prev = compatible[-1]
        lines += ['', f"Delta vs comparable run `{prev['run_id']}`: within-target "
                      f"{int(last['within_target']) - int(prev['within_target']):+d}, p90 "
                      f"{float(last['p90']) - float(prev['p90']):+.2f}, geomean "
                      f"{float(last['geomean']) - float(prev['geomean']):+.2f}"]
    elif len(rows) > 1:
        lines += ['', 'No comparable prior run: host, compiler, backend, flags or corpus provenance differs or is missing.']
    lines += family_section(last['run_id'])
    lines += ['', '## History', '', '| run | kind | compiler | within target | p90 | geomean | worst |',
              '|---|---|---|---|---|---|---|']
    for r in rows:
        lines.append(f"| {r['run_id']} | {r['kind']} | {r['compiler']} | {r['within_target']}/{r['workloads']} "
                     f"| {float(r['p90']):.2f} | {float(r['geomean']):.2f} | {float(r['worst']):.2f} |")
    progress = PERF / 'progress.md'
    if progress.exists():
        lines += ['', '## Progress', '', progress.read_text().strip()]
    (PERF / 'latest.md').write_text('\n'.join(lines) + '\n')


def record(report, destination_root, run_id, kind, notes):
    destination = destination_root / run_id
    if destination.exists():
        raise ValueError(f'Run directory exists, refusing to overwrite: {destination}')
    raw, summary, correctness = build_tables(report, run_id)
    stats = dashboard_stats(summary)
    destination.mkdir(parents=True)
    meta = report['metadata']
    metadata = dict(run_id=run_id, timestamp_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                    git_commit=meta['revision'], git_dirty=meta['worktreeDirty'],
                    host=platform.node(), os=platform.platform(), architecture=platform.machine(), cpu=meta['cpu'],
                    cpu_model=tool_version(['sysctl', '-n', 'machdep.cpu.brand_string']),
                    cores=__import__('os').cpu_count(),
                    dmd=tool_version(['dmd', '--version']), ldc=tool_version(['ldc2', '--version']),
                    compiler=meta['compiler'], build_command='bash scripts/benchmark.sh --export-corpus',
                    flags=next((line.removeprefix('Build flags: ') for line in meta.get('buildLog', '').splitlines()
                                if line.startswith('Build flags: ')), 'unknown'),
                    sanitizers='none (timing build)',
                    harness_version=HARNESS_VERSION, backend=meta['backend'],
                    workloads_revision=hashlib.sha256((PERF / 'workloads.json').read_bytes()).hexdigest()
                    if (PERF / 'workloads.json').exists() else None,
                    corpus_checksums={f"{c['suite']}/{c['name']}": c['sha256'] for c in corpus_manifest(report)},
                    repetitions=meta['runs'], samples_per_repetition=meta['samples'],
                    iterations_per_sample=meta['iterations'], warmups='1 per case (in runner)',
                    cpu_pinning=meta.get('cpuPinning', 'none'), binary_bytes=meta['binaryBytes'], text_bytes=meta['textBytes'],
                    build_and_export_seconds=meta['buildAndExportSeconds'],
                    q2=meta.get('q2', False), corpus_index_sha256=meta.get('corpusIndexSha256'),
                    comparison_run=None, target_ratio=report['targetRatio'])
    if (PERF / 'trends.csv').exists():
        with (PERF / 'trends.csv').open() as handle:
            prior = list(csv.DictReader(handle))
        metadata['comparison_run'] = next((row['run_id'] for row in reversed(prior)
            if comparable(metadata, run_metadata(row['run_id']))), None)
    (destination / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    write_csv(destination / 'raw.csv', RAW_COLUMNS, raw)
    write_csv(destination / 'summary.csv', SUMMARY_COLUMNS, summary)
    write_csv(destination / 'families.csv', FAMILY_COLUMNS, family_breakdown(summary))
    (destination / 'correctness.json').write_text(json.dumps(correctness, indent=2) + '\n')
    (destination / 'notes.md').write_text(
        f"# {kind} {run_id}\n\n{notes}\n\n- Ratio = median(npegged ns/parse) / median(handwritten ns/parse), "
        f"both from identical output-mode workloads; N/A when no handwritten twin exists.\n"
        f"- Samples pool all repetitions (n_samples = runs x samples).\n"
        f"- Allocation/backtrack metrics are not collected here (separate instrumented runs, A2).\n"
        f"- Peak RSS and DMD timings: not measured by this harness (DC={meta['compiler']} only).\n")
    if stats:
        trends = PERF / 'trends.csv'
        new = not trends.exists()
        with trends.open('a', newline='') as handle:
            writer = csv.DictWriter(handle, TREND_COLUMNS, lineterminator='\n')
            if new:
                writer.writeheader()
            writer.writerow(dict(run_id=run_id, kind=kind, compiler=meta['compiler'],
                                 commit=meta['revision'], **{k: (f'{v:.4f}' if isinstance(v, float) else v)
                                                              for k, v in stats.items()}))
    regenerate_latest()
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--baseline', action='store_true')
    group.add_argument('--milestone')
    parser.add_argument('--notes', default='')
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    commit = report['metadata']['revision'][:9]
    run_id = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + str(time.time_ns() % 1_000_000_000).zfill(9) + '-' + commit
    backend = report['metadata'].get('backend', 'combinators')
    suffix = '' if backend == 'combinators' else f'[{backend}]'
    if args.baseline:
        root, kind = PERF / 'baselines', 'baseline' + suffix
    else:
        root, kind = PERF / 'milestones' / args.milestone, f'milestone:{args.milestone}' + suffix
    print(record(report, root, run_id, kind, args.notes))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
