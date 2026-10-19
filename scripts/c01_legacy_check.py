#!/usr/bin/env python3
"""C01: compiler/activation checks for repaired historical P09/P13 harnesses.

Printed instrumented clock values are raw diagnostic output only. The repeated
uninstrumented crossover evidence is produced by c01_shared_output.py.
"""
import csv
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'performance/phase3/C01/legacy'


def bounded():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))


def main():
    os.chdir(ROOT)
    DEST.mkdir(parents=True, exist_ok=True)
    (ROOT / 'build/C01/imports/npegged').mkdir(parents=True, exist_ok=True)
    link = ROOT / 'build/C01/imports/npegged/examples'
    if not link.exists(): link.symlink_to(ROOT / 'examples', target_is_directory=True)
    sources = sorted(Path('src').rglob('*.d')) + [Path('examples/json.d'), Path('examples/csv.d')]
    pins = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources,
        Path('benchmark/p09_crossover.d'), Path('benchmark/p13_tuning.d'), Path(__file__).relative_to(ROOT)]}
    reports = []
    activation = {}
    for compiler in ('dmd', 'ldc2'):
        for fixture in ('p09_crossover', 'p13_tuning'):
            name = f'{compiler}-{fixture}'
            binary = ROOT / 'build/C01' / name
            flags = ['-Isrc', '-I.', '-Ibuild/C01/imports', '-w', '-de', '-checkaction=halt']
            if compiler == 'dmd':
                flags += ['-defaultlib=druntime', '-nothrow', '-O',
                          '-version=NPeggedSharedOutput', '-version=NPeggedMetrics']
            else:
                flags += ['-defaultlib=druntime-ldc', '-fno-exceptions', '-O3',
                          '-d-version=NPeggedSharedOutput', '-d-version=NPeggedMetrics']
            command = [compiler, *flags, *map(str, sources), f'benchmark/{fixture}.d', f'-of={binary}']
            build = subprocess.run(command, capture_output=True, text=True, check=False,
                                   timeout=300, preexec_fn=bounded)
            (DEST / (name + '.build.log')).write_text(build.stdout + build.stderr)
            build.check_returncode()
            run = subprocess.run([str(binary)], capture_output=True, text=True, check=False,
                                 timeout=120, preexec_fn=bounded)
            path = DEST / (name + '.txt'); path.write_text(run.stdout)
            (DEST / (name + '.run.log')).write_text(run.stderr)
            run.check_returncode()
            assert not run.stderr
            if fixture == 'p09_crossover':
                rows = list(csv.DictReader(run.stdout.splitlines()))
                assert len(rows) == 51, len(rows)
                counts = [tuple(r[k] for k in ('grammar', 'density', 'depth', 'valid',
                          'committed_nodes', 'shared_snapshots', 'reused_nodes', 'frozen_nodes')) for r in rows]
                assert any(int(r['shared_snapshots']) > 0 for r in rows if r['grammar'] == 'DenseChain')
            else:
                counts = [line for line in run.stdout.splitlines() if line.startswith('activation ')]
                assert len(counts) == 5
                assert all('snapshots=0 ' not in line for line in counts[:3])
            assert activation.setdefault(fixture, counts) == counts, ('compiler activation mismatch', name)
            reports.append(dict(name=name, command=command,
                compilerVersion=subprocess.check_output([compiler, '--version'], text=True),
                binarySha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                outputSha256=hashlib.sha256(path.read_bytes()).hexdigest()))
            print(name, 'activation/parity passed', flush=True)
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h for p, h in pins.items())
    (DEST / 'manifest.json').write_text(json.dumps(dict(milestone='C01', sourceHashes=pins,
        memoryLimitBytes=4 * 1024**3, timeoutSeconds=120, diagnosticOnly=True, builds=reports), indent=2) + '\n')


if __name__ == '__main__':
    main()
