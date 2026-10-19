#!/usr/bin/env python3
"""D01: pure-island active/fallback timings and counters, with source-pinned builds."""
from concurrent.futures import ThreadPoolExecutor
import csv
import hashlib
import json
import os
from pathlib import Path
import random
import resource
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'performance/phase3/D01'
BUILD = ROOT / 'build/D01'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounded():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))


def expected(diagnostic):
    keys = set()
    for sample in range(1 if diagnostic else 7):
        for n in (16, 64, 256, 1024):
            for finite in (0, 1):
                for valid in (0, 1):
                    for mode in (0, 1, 2):
                        keys.add(('Identifier', str(mode), str(n), str(valid), str(finite), str(sample)))
        for n in (0, 16, 256):
            for finite in (0, 1):
                for mode in (0, 2):
                    keys.add(('Whitespace', str(mode), str(n), '1', str(finite), str(sample)))
        for n in (1, 16, 128):
            for finite in (0, 1):
                for valid in (0, 1):
                    for mode in (0, 1, 2, 3):
                        for case in ('Root', 'ActRoot'):
                            keys.add((case, str(mode), str(n), str(valid), str(finite), str(sample)))
        for case, size in [('JSON', 27), ('CSV', 12), ('PEG', 12)]:
            for valid in (0, 1):
                keys.add((case, '0', str(size), str(valid), '0', str(sample)))
    return keys


def inactive(row, selector, tracing):
    return (tracing or row['finite'] == '1' or row['case'] in ('ActRoot', 'JSON', 'CSV', 'PEG')
            or row['mode'] == '3' or (row['case'] == 'Root' and selector == 'all' and row['mode'] in ('1', '2')))


def main():
    os.chdir(ROOT)
    DEST.mkdir(parents=True, exist_ok=True); (BUILD / 'imports/npegged').mkdir(parents=True, exist_ok=True)
    link = BUILD / 'imports/npegged/examples'
    if not link.exists(): link.symlink_to(ROOT / 'examples', target_is_directory=True)
    assert link.resolve() == ROOT / 'examples'
    sources = sorted(Path('src').rglob('*.d')) + [Path(p) for p in (
        'examples/json.d', 'examples/csv.d', 'examples/PEG.d', 'benchmark/measurement.d',
        'tests/pure_islands.d', 'benchmark/diagnostics/pure_islands.d')]
    pins = {str(p): sha(p) for p in [*sources, Path(__file__).relative_to(ROOT)]}
    def verify():
        assert all(sha(Path(p)) == h for p, h in pins.items()), 'Source changed'
    jobs = []
    for selector in ('all', 'root', 'leaf'):
        for diagnostic in (False, True):
            for feature in (False, True):
                name = f'{selector}-{"metrics" if diagnostic else "timing"}-{"on" if feature else "off"}'
                binary = BUILD / name
                flags = ['-Isrc', '-I.', '-Ibuild/D01/imports', '-defaultlib=druntime-ldc',
                    '-fno-exceptions', '-O3', '-release', '-w', '-de', '-checkaction=halt',
                    '-d-version=PureIslandsBenchmark']
                if selector == 'root': flags.append('-d-version=RootOnly')
                if selector == 'leaf': flags.append('-d-version=LeafOnly')
                if diagnostic: flags += ['-d-version=NPeggedMetrics', '-enable-asserts=true']
                if feature: flags.append('-d-version=NPeggedPureIslands')
                command = ['ldc2', *flags, *map(str, sources), f'-of={binary}']
                jobs.append(dict(name=name, selector=selector, diagnostic=diagnostic,
                                 feature=feature, command=command, binary=str(binary)))
    def build(job):
        verify(); started = time.monotonic()
        log = DEST / (job['name'] + '.build.log')
        with log.open('w') as stream:
            process = subprocess.Popen(job['command'], stdout=stream, stderr=subprocess.STDOUT,
                                       preexec_fn=bounded)
            while True:
                pid, status, usage = os.wait4(process.pid, os.WNOHANG)
                if pid:
                    process.returncode = os.waitstatus_to_exitcode(status)
                    break
                if time.monotonic() - started > 300:
                    process.kill()
                    _, status, usage = os.wait4(process.pid, 0)
                    process.returncode = os.waitstatus_to_exitcode(status)
                    raise subprocess.TimeoutExpired(job['command'], 300)
                time.sleep(.05)
        if process.returncode:
            raise subprocess.CalledProcessError(process.returncode, job['command'])
        verify()
        job.update(compileWallSeconds=time.monotonic()-started,
                   compilePeakRssKiB=usage.ru_maxrss, binarySha256=sha(Path(job['binary'])),
                   binaryBytes=Path(job['binary']).stat().st_size)
        return job
    # Two independent compiler processes; no timings before the full barrier.
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = list(pool.map(build, jobs))
    manifest = dict(milestone='D01', revision=subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(),
        compiler=subprocess.check_output(['ldc2','--version'], text=True), sourceHashes=pins,
        memoPolicy='selective', backend='direct action grammar; conventional JSON/CSV/PEG controls',
        memoryLimitBytes=4*1024**3, timeoutSeconds=120, compileConcurrency=2,
        finitePolicy='Unchanged ParseContext defaults, including 10000000 steps; records output=256MiB',
        activePolicy='step/depth/memory and records output=size_t.max; trace=null',
        ownership='recognition borrowed; records borrowed/owned; tree owned; destruction inside timing',
        jobs=jobs, measurements=[])
    cpu = min(os.sched_getaffinity(0)); os.sched_setaffinity(0,{cpu}); manifest['timingCpu']=cpu
    rng = random.Random(10101)
    # Pair feature-on/off invocations closely, randomizing pair and policy order.
    pairs = [(selector, diagnostic, tracing, run+1) for selector in ('all','root','leaf')
        for diagnostic in (False,True) for tracing in (False,True)
        for run in range(1 if diagnostic else 3)]
    rng.shuffle(pairs)
    outputs, footprints, collected = {}, {}, []
    for selector, diagnostic, tracing, repeat in pairs:
        policies = [False, True]; rng.shuffle(policies)
        for feature in policies:
            job = next(j for j in jobs if (j['selector'],j['diagnostic'],j['feature']) == (selector,diagnostic,feature))
            verify(); assert sha(Path(job['binary'])) == job['binarySha256']
            name = f"{job['name']}-trace{int(tracing)}-r{repeat}"
            environment = dict(os.environ, NPEGGED_TRACE_PURE_ISLANDS=str(int(tracing)))
            result = subprocess.run([job['binary']], capture_output=True, text=True, env=environment,
                                    timeout=120, preexec_fn=bounded)
            raw=DEST/(name+'.csv'); raw.write_text(result.stdout)
            (DEST/(name+'.log')).write_text(result.stderr); result.check_returncode()
            assert not result.stderr
            rows=list(csv.DictReader(result.stdout.splitlines()))
            fields=('case','mode','size','valid','finite','sample')
            assert len(rows)==len(expected(diagnostic)) and {tuple(r[k] for k in fields) for r in rows}==expected(diagnostic)
            for row in rows:
                key=(selector,tracing,*tuple(row[k] for k in fields[:-1]))
                signature=tuple(row[k] for k in ('nodes','end','fail_end','hash','actions','trace_events'))
                assert outputs.setdefault(key,signature)==signature,('output parity',name,key)
                assert int(row['tracing']) == tracing and int(row['ns'])>0
                off_path=inactive(row,selector,tracing)
                if off_path:
                    memory_key=(diagnostic,*key)
                    footprint=tuple(row[k] for k in ('peak','requested','allocations'))
                    assert footprints.setdefault(memory_key,footprint)==footprint,('fallback allocation parity',name,key)
                if diagnostic:
                    if not feature or off_path: assert row['island_entries']=='0',(name,key)
                    elif row['valid']=='1': assert int(row['island_entries'])>0,('inactive target',name,key)
                collected.append(dict(selector=selector,diagnostic=diagnostic,feature=feature,
                    run=repeat,**row))
            manifest['measurements'].append(dict(name=name,job=job['name'],tracing=tracing,run=repeat,
                pairPolicyOrder=policies,csvSha256=sha(raw),rows=len(rows)))
            (DEST/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
            print(name,flush=True)
    verify()
    fields=list(dict.fromkeys(k for r in collected for k in r))
    with (DEST/'observations.csv').open('w') as stream:
        writer=csv.DictWriter(stream,fieldnames=fields); writer.writeheader(); writer.writerows(collected)
    print(f'D01 finished: {len(manifest["measurements"])} invocations, {len(collected)} rows')


if __name__=='__main__': main()
