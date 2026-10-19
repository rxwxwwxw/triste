#!/usr/bin/env python3
"""C02: bounded storage semantics and guarded parser limit-transition oracle."""
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'performance/phase3/C02'
BUILD = ROOT / 'build/C02'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounded():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))


def main():
    os.chdir(ROOT)
    DEST.mkdir(parents=True, exist_ok=True); BUILD.mkdir(parents=True, exist_ok=True)
    sources = sorted(Path('src').rglob('*.d')) + [Path('tests/bounded_shared_output.d')]
    pins = {str(p): sha(p) for p in [*sources, Path(__file__).relative_to(ROOT)]}
    reports, transcripts = [], {}
    for compiler in ('dmd', 'ldc2'):
        for backend in ('combinators', 'direct'):
            name = f'{compiler}-{backend}'
            binary = BUILD / name
            flags = ['-Isrc', '-w', '-de', '-checkaction=halt']
            versions = ['NPeggedSharedOutput', 'NPeggedMetrics']
            if backend == 'direct': versions.append('NPeggedDirect')
            if compiler == 'dmd':
                flags += ['-defaultlib=druntime', '-nothrow']
                flags += [f'-version={v}' for v in versions]
            else:
                flags += ['-defaultlib=druntime-ldc', '-fno-exceptions']
                flags += [f'-d-version={v}' for v in versions]
            command = [compiler, *flags, *map(str, sources), f'-of={binary}']
            result = subprocess.run(command, capture_output=True, text=True,
                                    timeout=300, preexec_fn=bounded)
            (DEST / (name + '.build.log')).write_text(result.stdout + result.stderr)
            result.check_returncode()
            result = subprocess.run([str(binary)], capture_output=True, text=True,
                                    timeout=60, preexec_fn=bounded)
            path = DEST / (name + '.csv'); path.write_text(result.stdout)
            (DEST / (name + '.run.log')).write_text(result.stderr)
            result.check_returncode()
            assert result.stdout.endswith('C02 bounded shared-output oracle passed\n')
            assert transcripts.setdefault(backend, result.stdout) == result.stdout, ('compiler parity', name)
            lines = result.stdout.splitlines()
            for label, expected in [('snapshot', 36), ('work', 5), ('transition', 40),
                                    ('public', 150), ('allocation-failure', 1)]:
                assert sum(line.startswith(label + ',') for line in lines) == expected, (name, label)
            reports.append(dict(name=name, command=command,
                compilerVersion=subprocess.check_output([compiler, '--version'], text=True),
                binarySha256=sha(binary), transcriptSha256=sha(path), lines=len(lines)))
            print(name, 'resource oracle passed', flush=True)
    assert all(sha(Path(p)) == h for p, h in pins.items())
    (DEST / 'manifest.json').write_text(json.dumps(dict(milestone='C02', sourceHashes=pins,
        revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        timeoutSeconds=60, memoryLimitBytes=4 * 1024**3, assertionsEnabled=True,
        measurement='Correctness/resource diagnostics only; no latency measurements',
        transcriptSchema={
            'snapshot':['nodes','scratchLimit','sharingComponent','scratchStatus','scratchUsed','scratchRequested','sharedSnapshots','sharedReplays','snapshotBytes'],
            'work':['terms','flatSteps','sharedSteps','flatScratchRequested','sharedScratchRequested','flatScratchReserved','sharedScratchReserved','nodes','sharedSnapshots','sharedReplays'],
            'transition':['owned','budgetKind','inputBytes','adjacentSuccessLimit'],
            'public':['owned','budgetKind','inputBytes','limit','status','successful','end','failEnd','nodes','scratchReserved','outputReserved','sharedSnapshots','sharedReplays','traceEvents'],
            'allocation-failure':['status','allocatorCalls','scratchReserved']},
        budgetKinds=['steps','depth','memory','output','defaults','trace'], builds=reports), indent=2) + '\n')


if __name__ == '__main__':
    main()
