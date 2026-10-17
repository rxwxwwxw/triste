#!/usr/bin/env python3
"""R01: bounded, source-matched recognition-only scaling cohorts."""
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def bounded():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))


def main():
    os.chdir(ROOT)
    destination = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/recognition-scaling')
    destination.mkdir(parents=True, exist_ok=True)
    sources = sorted(Path('src').rglob('*.d')) + [Path('benchmark/measurement.d'),
              Path('benchmark/diagnostics/recursion_recognition.d'), Path(__file__).relative_to(ROOT)]
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    for backend in ('combinators', 'direct'):
        for memo in ('selective', 'full'):
            for metrics in (False, True):
                prefix = destination / f'{backend}-{memo}-{"metrics" if metrics else "timing"}'
                flags = ['-Isrc', '-I.', '-defaultlib=druntime-ldc', '-fno-exceptions',
                         '-O3', '-release', '-w', '-checkaction=halt']
                if backend == 'direct': flags += ['-d-version=NPeggedDirect']
                if memo == 'full': flags += ['-d-version=NPeggedFullMemo']
                if metrics: flags += ['-d-version=NPeggedMetrics']
                command = ['ldc2', *flags, *map(str, sources[:-1]), f'-of={prefix}.runner']
                subprocess.run(command, timeout=300, preexec_fn=bounded, check=True)
                for run in range(1, 2 if metrics else 4):
                    output = Path(f'{prefix}-run{run}.csv')
                    with output.open('w') as stream:
                        subprocess.run(['timeout', '--kill-after=2s', '60s', f'./{prefix}.runner'],
                                       stdout=stream, timeout=65, preexec_fn=bounded, check=True)
                    with output.open() as stream: rows = list(csv.DictReader(stream))
                    expected = {(grammar, str(valid), str(n), str(sample))
                                for grammar in ('DirectChain', 'IndirectChain') for valid in (0, 1)
                                for n in (16,32,64,128,256,512,1024,2048,4096,8192)
                                for sample in range(1 if metrics else 7)}
                    assert len(rows) == len(expected) and {tuple(r[k] for k in ('grammar','valid','terms','sample')) for r in rows} == expected
                    if metrics: assert all(int(r['snapshot_bytes']) == 0 for r in rows)
                metadata = dict(command=command, compiler=subprocess.check_output(['ldc2','--version'],text=True),
                                platform=platform.platform(),cpu=Path('/proc/cpuinfo').read_text(),
                                revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
                                sourceHashes=hashes, diagnostic=metrics, runs=1 if metrics else 3,
                                samples=1 if metrics else 7,iterations=1 if metrics else 64,
                                timeoutSeconds=60,memoryLimitBytes=4*1024**3)
                Path(f'{prefix}.metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
                Path(f'{prefix}.runner').unlink()
                Path(f'{prefix}.o').unlink(missing_ok=True)
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h for p,h in hashes.items())


if __name__ == '__main__': main()
