#!/usr/bin/env python3
"""Paired prebuilt A/B runs with a fixed CPU and matching exported fixtures.

Usage: compare_builds.py BEFORE.json BEFORE_BINARY AFTER.json AFTER_BINARY OUTPUT_PREFIX
The input gate reports preserve the compiler commands and source hashes for each
binary. New reports retain all fresh samples, alternating binary order per job.
"""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from performance_gate import paired_ratios, source_hashes

def run(binary, arguments):
    command = ['prlimit', '--as=4294967296', 'timeout', '--kill-after=2s', '120s',
               str(binary), *arguments]
    return json.loads(subprocess.check_output(command, cwd=ROOT, text=True, timeout=125))

def main():
    if len(sys.argv) != 6:
        raise SystemExit(__doc__)
    snapshots = source_hashes()
    before_json, before_bin, after_json, after_bin, prefix = map(Path, sys.argv[1:])
    templates = [json.loads(path.read_text()) for path in (before_json, after_json)]
    binaries = [path.resolve() for path in (before_bin, after_bin)]
    cpu = max(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
    jobs = []
    for suite, extra in [('json-ambiguity', []), ('handwritten-workloads', ['--workloads'])]:
        for mode in ('validation', 'spans', 'tree'):
            corpora = [run(binary, [*extra, '--export-corpus', '--mode=' + mode])
                       for binary in binaries]
            if corpora[0] != corpora[1]:
                raise ValueError('Different exported corpus: ' + suite + '/' + mode)
            names = [case['name'] for case in corpora[0] if case['timed']]
            jobs.append((suite, mode, names, extra))
    outputs = [copy.deepcopy(template) for template in templates]
    for output, binary in zip(outputs, binaries):
        if binary.stat().st_size != output['metadata']['binaryBytes']:
            raise ValueError('Binary size differs from build report: ' + str(binary))
        output['metadata'].update(cpuPinning=[cpu], iterations=5000, samples=7, runs=3,
                                  binarySha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                                  measurementOrder='alternating prebuilt A/B blocks',
                                  measurementSourceHashes=snapshots,
                                  measurementMemoryLimitBytes=4294967296,
                                  measurementNotes='Coverage compilation may be active; CPU is pinned and A/B order alternates. Governor uncontrolled.')
        output['measurements'] = []
        output['ratios'] = []
    for repeat in range(3):
        for job, (suite, mode, names, extra) in enumerate(jobs):
            order = (0, 1) if (repeat + job) % 2 == 0 else (1, 0)
            for index in order:
                measured = run(binaries[index], ['--target-engines', '--json', '--memory',
                    '--mode=' + mode, '--iterations=5000', '--samples=7', *extra])
                paired = paired_ratios(measured, names, mode)
                outputs[index]['ratios'].extend(dict(row, run=repeat + 1, suite=suite) for row in paired)
                outputs[index]['measurements'].append(dict(run=repeat + 1, suite=suite,
                                                           output=mode, report=measured))
            print(f'Paired block {repeat + 1}/3 {suite}/{mode}', flush=True)
    if source_hashes() != snapshots:
        raise ValueError('Source changed during A/B measurement')
    for suffix, output in zip(('before', 'after'), outputs):
        output['failures'] = [row for row in output['ratios'] if row['ratio'] > output['targetRatio']]
        output['passed'] = not output['failures']
        path = Path(str(prefix) + '-' + suffix + '.json')
        path.write_text(json.dumps(output, indent=2) + '\n')
        print(path)

if __name__ == '__main__':
    main()
