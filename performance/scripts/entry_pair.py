#!/usr/bin/env python3
"""S3 diagnostic benchmark: same grammar, generated entry versus exact wrapper."""
import csv
import datetime
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]

def run(command, **kwargs):
    return subprocess.run(command, cwd=ROOT, check=True, timeout=180, **kwargs)

def main():
    commit = run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    target = ROOT / 'performance/milestones/S3' / ('entry-' + stamp + '-' + commit[:10])
    target.mkdir(parents=True, exist_ok=False)
    sources = ['benchmark/entry_pair.d', 'benchmark/measurement.d'] + [
        str(path.relative_to(ROOT)) for path in sorted((ROOT / 'src').rglob('*.d'))]
    command = ['ldc2', '-Isrc', '-I.', '-defaultlib=druntime-ldc', '-fno-exceptions',
               '-checkaction=halt', '-w', '-d-version=NPeggedLeanEntry', '-O3', '-release', '-boundscheck=off'] + sources + ['-of=build/S3/entry-pair']
    started = time.monotonic()
    run(command)
    compile_seconds = time.monotonic() - started
    result = run(['prlimit', '--as=4294967296', 'timeout', '--kill-after=2s', '60s',
                  'build/S3/entry-pair'], capture_output=True, text=True)
    rows = list(csv.DictReader(result.stdout.splitlines()))
    groups = {}
    for row in rows:
        groups.setdefault((row['fixture'], row['implementation']), []).append(float(row['elapsed_ns']))
    assert len(groups) == 12 and all(len(values) == 21 for values in groups.values())
    raw_columns = ['run_id', 'workload_id', 'implementation', 'compiler', 'mode', 'iteration',
                   'input_bytes', 'elapsed_ns', 'successful', 'output_digest', 'status']
    with (target / 'raw.csv').open('w') as output:
        writer = csv.DictWriter(output, fieldnames=raw_columns, lineterminator='\n')
        writer.writeheader()
        for row in rows:
            writer.writerow(dict(run_id=target.name, workload_id='entry.' + row['fixture'],
                implementation=row['implementation'], compiler='ldc2', mode='validation',
                **{key: row[key] for key in ['iteration', 'input_bytes', 'elapsed_ns',
                                             'successful', 'output_digest', 'status']}))
    with (target / 'summary.csv').open('w') as output:
        writer = csv.writer(output, lineterminator='\n')
        writer.writerow(['run_id', 'workload_id', 'implementation', 'compiler', 'mode', 'n_samples',
                         'median_ns', 'p95_ns', 'bytes_per_second', 'handwritten_median_ns',
                         'slowdown_ratio', 'correctness_ok', 'exact_median_ns', 'entry_vs_exact'])
        for (fixture, implementation), samples in groups.items():
            median = statistics.median(samples)
            exact = statistics.median(groups[fixture, 'exact'])
            length = int(next(row['input_bytes'] for row in rows if row['fixture'] == fixture))
            writer.writerow([target.name, 'entry.' + fixture, implementation, 'ldc2', 'validation',
                             len(samples), median, sorted(samples)[19], length * 1e9 / median,
                             'N/A', 'N/A', True, exact, median / exact])
    fixtures = dict(zip(['empty', 'one', 'eight', 'invalid', 'trailing', 'utf8_invalid'],
                        [b'', b'a', b'aaaaaaaa', b'!', b'aaa!', b'\xff']))
    metadata = dict(timestamp=stamp, git_commit=commit, git_dirty=True,
        host=platform.uname()._asdict(), cpu=Path('/proc/cpuinfo').read_text().split('model name')[1].splitlines()[0],
        memory=Path('/proc/meminfo').read_text().splitlines()[0],
        compiler=run(['ldc2', '--version'], capture_output=True, text=True).stdout,
        build_command=command, build_seconds=compile_seconds,
        binary_bytes=(ROOT / 'build/S3/entry-pair').stat().st_size,
        sanitizer=False, instrumentation=False, repetitions=21, warmups=3,
        iterations=1000000, order='alternating blocks', cpu_pinning=False,
        governor='uncontrolled', timeout_seconds=60, memory_limit_bytes=4294967296,
        grammar='Entry: Root <- [a-z]* eoi', backend='direct', handwritten_reference=None,
        comparison='same generated grammar, exact wrapper without an entry marker',
        fixtures={key: dict(bytes=len(value), sha256=hashlib.sha256(value).hexdigest())
                  for key, value in fixtures.items()},
        source_hashes={source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest() for source in sources})
    (target / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    (target / 'correctness.json').write_text(json.dumps(dict(
        parity_before_timing=True, checksum_each_batch=True,
        contract='Observation including status, arena counters and encoded end/failEnd',
        diagnostics='also compared directly by tests/entry.d and colocated dfa unittest'), indent=2) + '\n')
    (target / 'notes.md').write_text('Same-input generated-vs-generated diagnostic run. '
        'No handwritten reference, so handwritten ratios are N/A. '
        'All timing samples are retained; no gate ratios are adjusted.\n')
    print(target.relative_to(ROOT))

if __name__ == '__main__':
    main()
