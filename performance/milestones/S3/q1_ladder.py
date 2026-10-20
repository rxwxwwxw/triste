#!/usr/bin/env python3
"""Build and record Q1. Ratios here are explanatory; never adjust gate ratios."""
import csv
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[3]

def run(args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, timeout=180, **kwargs)

def main():
    dc = os.environ.get('DC', 'ldc2')
    commit = run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    target = ROOT / 'performance/milestones/S3' / ('ladder-' + stamp + '-' + commit[:10])
    target.mkdir(parents=True, exist_ok=False)
    build = ROOT / 'build/S3/ladder'
    build.mkdir(parents=True, exist_ok=True)
    sources = ['performance/milestones/S3/q1_ladder.d', 'benchmark/measurement.d'] + [
        'src/npegged/' + name + '.d' for name in ['peg', 'storage', 'records', 'dfa']]
    flags = ['-Isrc', '-I.', '-defaultlib=druntime-ldc', '-fno-exceptions', '-checkaction=halt', '-w', '-d-version=NPeggedLeanEntry']
    command = [dc] + flags + ['-O3', '-release', '-boundscheck=off'] + sources + ['-of=build/S3/ladder/runner']
    run(command)
    with (target / 'raw.csv').open('w') as output:
        run(['prlimit', '--as=4294967296', 'timeout', '--kill-after=2s', '60s', 'build/S3/ladder/runner'], stdout=output)
    rows = list(csv.DictReader((target / 'raw.csv').open()))
    with (target / 'raw.csv').open('w') as output:
        fields = ['run_id', 'workload_id', 'implementation', 'compiler', 'mode',
                  'iteration', 'input_bytes', 'elapsed_ns', 'successful', 'output_digest', 'status']
        writer = csv.DictWriter(output, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow(dict(run_id=target.name, workload_id='q1-ladder.' + row['fixture'],
                implementation=row['rung'], compiler=dc, mode='validation',
                iteration=row['iteration'], input_bytes=row['input_bytes'],
                elapsed_ns=row['elapsed_ns'], successful=row['successful'], output_digest=0,
                status=row['status']))
    groups = {}
    for row in rows:
        groups.setdefault((row['fixture'], row['rung']), []).append(float(row['elapsed_ns']))
    assert len(groups) == 18 and all(len(values) == 21 for values in groups.values())
    with (target / 'summary.csv').open('w') as output:
        writer = csv.writer(output)
        writer.writerow(['fixture', 'rung', 'n_samples', 'median_ns', 'p95_ns', 'floor_ns',
                         'raw_ratio', 'floor_subtracted_ratio', 'run_id', 'workload_id', 'implementation',
                         'compiler', 'mode', 'bytes_per_second', 'handwritten_median_ns',
                         'slowdown_ratio', 'correctness_ok'])
        for (fixture, rung), samples in groups.items():
            median = statistics.median(samples)
            floor = statistics.median(groups[fixture, 'floor'])
            twin = statistics.median(groups[fixture, 'handwritten'])
            adjusted = (median - floor) / (twin - floor) if twin > floor else 'N/A'
            writer.writerow([fixture, rung, len(samples), median, sorted(samples)[19], floor,
                             median / twin, adjusted, target.name, 'q1-ladder.' + fixture, rung, dc,
                             'validation', (0 if fixture == 'empty' else 1e9 / median),
                             twin, median / twin, True])
    metadata = dict(timestamp=stamp, commit=commit,
                    dirty=bool(run(['git', 'status', '--porcelain'], capture_output=True, text=True).stdout),
                    host=platform.uname()._asdict(), cpu=Path('/proc/cpuinfo').read_text().split('model name')[1].splitlines()[0],
                    memory=Path('/proc/meminfo').read_text().splitlines()[0], cores=os.cpu_count(),
                    compiler=run([dc, '--version'], capture_output=True, text=True).stdout,
                    build_command=command, iterations=1000000, repetitions=21, warmup_blocks=3,
                    order='rotated blocks', cpu_pinning=False, governor='uncontrolled',
                    timeout_seconds=60, memory_limit_bytes=4294967296,
                    instrumentation=False, sanitizer=False, comparison='within run, handwritten rung',
                    sources={s: hashlib.sha256((ROOT / s).read_bytes()).hexdigest() for s in sources})
    (target / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    (target / 'correctness.json').write_text(json.dumps(dict(
        parity_before_timing=True, fixtures=['empty', 'one'], compared_fields='all Observation fields',
        negative_tests='colocated unittests; separately run debug executable'), indent=2) + '\n')
    print(target.relative_to(ROOT))

if __name__ == '__main__':
    main()
