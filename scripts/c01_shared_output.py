#!/usr/bin/env python3
"""C01: active shared-output crossover and explicit finite-budget fallback matrix."""
from concurrent.futures import ThreadPoolExecutor
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import resource
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'performance/phase3/C01'
BUILD = ROOT / 'build/C01'
MEMORY = 4 * 1024**3


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounded():
    resource.setrlimit(resource.RLIMIT_AS, (MEMORY, MEMORY))


def expected(finite, diagnostic):
    samples = range(1 if diagnostic else 7)
    flat = (16, 32, 64, 128) if finite else (16, 32, 64, 128, 256, 512, 1024, 2048)
    siblings = (16, 32, 64, 128) if finite else (16, 32, 64, 128, 256, 512)
    keys = {(g, 'flat', str(n), str(v), str(s)) for g in ('DirectChain', 'IndirectChain')
            for n in flat for v in (0, 1) for s in samples}
    keys |= {('NestedChain', shape, str(n), str(v), str(s))
             for shape, sizes in [('siblings', siblings), ('depth', range(9))]
             for n in sizes for v in (0, 1) for s in samples}
    keys |= {(g, 'control', str(n), str(v), str(s))
             for g, n in [('JSON', 27), ('CSV', 12), ('PEG', 12)]
             for v in (0, 1) for s in samples}
    return keys


def main():
    os.chdir(ROOT)
    DEST.mkdir(parents=True, exist_ok=True)
    (BUILD / 'imports/npegged').mkdir(parents=True, exist_ok=True)
    link = BUILD / 'imports/npegged/examples'
    if not link.exists():
        link.symlink_to(ROOT / 'examples', target_is_directory=True)
    assert link.resolve() == ROOT / 'examples'
    sources = sorted(Path('src').rglob('*.d')) + [Path(p) for p in (
        'examples/json.d', 'examples/csv.d', 'examples/PEG.d', 'benchmark/measurement.d',
        'benchmark/diagnostics/shared_output.d')]
    pins = {str(p): sha(p) for p in [*sources, Path(__file__).relative_to(ROOT)]}
    def verify():
        assert all(sha(Path(p)) == digest for p, digest in pins.items()), 'Source changed'
    compiler = subprocess.check_output(['ldc2', '--version'], text=True)
    jobs = []
    for selector in ('all', 'expr', 'root'):
        for diagnostic in (False, True):
            for compiled in (False, True):
                name = f'{selector}-{"metrics" if diagnostic else "timing"}-{"shared" if compiled else "flat"}'
                binary = BUILD / name
                flags = ['-Isrc', '-I.', '-Ibuild/C01/imports', '-defaultlib=druntime-ldc',
                         '-fno-exceptions', '-O3', '-release', '-boundscheck=off', '-w', '-de', '-checkaction=halt']
                if selector == 'expr': flags.append('-d-version=ExprOnly')
                if selector == 'root': flags.append('-d-version=RootOnly')
                if diagnostic: flags.append('-d-version=NPeggedMetrics')
                if compiled: flags.append('-d-version=NPeggedSharedOutput')
                command = ['ldc2', *flags, *map(str, sources), f'-of={binary}']
                jobs.append(dict(name=name, selector=selector, diagnostic=diagnostic,
                                 compiled=compiled, binary=str(binary), command=command))
    def build(job):
        verify()
        log = DEST / (job['name'] + '.build.log')
        started = time.monotonic()
        with log.open('w') as stream:
            subprocess.run(['timeout', '--kill-after=2s', '300s', *job['command']],
                           stdout=stream, stderr=subprocess.STDOUT, check=True,
                           timeout=305, preexec_fn=bounded)
        verify()
        job.update(compileSeconds=time.monotonic() - started, binarySha256=sha(Path(job['binary'])))
        return job
    # Independent compiles only. No timing begins before the barrier.
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = list(pool.map(build, jobs))
    manifest = dict(milestone='C01', revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        compiler=compiler, platform=platform.platform(), cpu=Path('/proc/cpuinfo').read_text(),
        sourceHashes=pins, backend='combinators', memo='selective', ownership='OwnInput=true',
        compileConcurrency=2, memoryLimitBytes=MEMORY, timeoutSeconds=120, warmupBatches=1,
        unlimitedBudgets='step/depth/memory/output=size_t.max',
        finiteBudgets='ParseContext defaults: steps=10000000, depth=1024, memory=256MiB; output=256MiB; sizes<=128',
        policySelectedEvidence='Fixture reports generated eligibility AND compile version AND request AND unlimited guards; nonzero operations independently establish activity above threshold.',
        jobs=jobs, measurements=[])
    (DEST / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    cpu = min(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
    manifest['timingCpu'] = cpu
    order = []
    for job in jobs:
        for finite in (False, True):
            policies = ('off', 'on') if job['compiled'] else ('flat',)
            for policy in policies:
                for repeat in range(1 if job['diagnostic'] else 3):
                    order.append((job, finite, policy, repeat + 1))
    random.Random(101).shuffle(order)
    signatures, footprints, transcripts = {}, {}, {}
    collected = []
    for job, finite, policy, repeat in order:
        verify()
        assert sha(Path(job['binary'])) == job['binarySha256']
        name = f"{job['name']}-{'finite' if finite else 'unlimited'}-{policy}-r{repeat}"
        environment = dict(os.environ, NPEGGED_SHARED_OUTPUT='1' if policy == 'on' else '0',
                           NPEGGED_FINITE_BUDGETS='1' if finite else '0')
        result = subprocess.run([job['binary']], capture_output=True, text=True, env=environment,
                                check=True, timeout=120, preexec_fn=bounded)
        raw = DEST / (name + '.csv'); raw.write_text(result.stdout)
        transcript = DEST / (name + '.tuples.txt'); transcript.write_text(result.stderr)
        rows = list(csv.DictReader(result.stdout.splitlines()))
        keyfields = ('grammar', 'shape', 'size', 'valid', 'sample')
        actual = {tuple(r[k] for k in keyfields) for r in rows}
        assert len(rows) == len(actual) and actual == expected(finite, job['diagnostic']), (name, len(rows))
        if job['diagnostic']:
            # Every result tuple, parent, end/failEnd and status must match, not just hashes.
            identity = (job['selector'], finite)
            assert transcripts.setdefault(identity, result.stderr) == result.stderr, ('tuple parity', name)
        else:
            assert not result.stderr
        for row in rows:
            key = tuple(row[k] for k in keyfields[:-1])
            identity = (job['selector'], finite, key)
            signature = tuple(row[k] for k in ('nodes', 'end', 'fail_end', 'hash'))
            assert signatures.setdefault(identity, signature) == signature, ('output', name, key)
            assert int(row['ns']) > 0
            assert int(row['finite_budgets']) == finite
            selected = job['compiled'] and policy == 'on' and not finite and row['grammar_eligible'] == '1'
            assert int(row['policy_selected']) == selected
            inactive = not selected
            if inactive:
                fkey = (job['selector'], finite, job['diagnostic'], key)
                footprint = tuple(row[k] for k in ('peak', 'requested', 'allocations'))
                assert footprints.setdefault(fkey, footprint) == footprint, ('fallback memory', name, key)
            if job['diagnostic']:
                ops = ('shared_snapshots', 'reused_nodes', 'frozen_nodes', 'shared_replays')
                if inactive:
                    assert all(int(row[k]) == 0 for k in ops), ('inactive operations', name, key)
                if selected and row['shape'] == 'flat' and row['size'] == '2048':
                    assert int(row['shared_snapshots']) > 0 and int(row['shared_replays']) > 0
                    assert int(row['reused_nodes']) > 0
            collected.append(dict(selector=job['selector'], diagnostic=job['diagnostic'],
                compiled=job['compiled'], finite=finite, policy=policy, run=repeat, **row))
        manifest['measurements'].append(dict(name=name, job=job['name'], finite=finite, policy=policy,
            run=repeat, csvSha256=sha(raw), tupleSha256=sha(transcript), rows=len(rows)))
        (DEST / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        print(name, flush=True)
    verify()
    with (DEST / 'observations.csv').open('w') as stream:
        fields = list(dict.fromkeys(k for row in collected for k in row))
        writer = csv.DictWriter(stream, fieldnames=fields); writer.writeheader(); writer.writerows(collected)
    print(f'C01 completed: {len(manifest["measurements"])} invocations, {len(collected)} observations')


if __name__ == '__main__':
    main()
