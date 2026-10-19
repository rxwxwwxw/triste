#!/usr/bin/env python3
"""B03: pin and interleave two preserved source-matched gate binaries."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import resource
import subprocess
import time


def bounded():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    cpu = min(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
    rng = random.Random(303)
    binaries = {p: str(getattr(args, p).resolve()) for p in ('before', 'after')}
    hashes = {p: hashlib.sha256(Path(b).read_bytes()).hexdigest() for p, b in binaries.items()}
    reports = []
    jobs = [(suite, mode) for suite in ('json-ambiguity', 'handwritten-workloads')
            for mode in ('validation', 'spans', 'tree')]
    for repeat in range(5):
        rng.shuffle(jobs)
        for suite, mode in jobs:
            order = ['before', 'after']
            rng.shuffle(order)
            pair = {}
            for policy in order:
                command = [binaries[policy], '--target-engines', '--json', '--memory',
                           f'--mode={mode}', '--iterations=2000', '--samples=7']
                if suite == 'handwritten-workloads':
                    command.append('--workloads')
                started = time.monotonic()
                result = subprocess.run(command, check=True, capture_output=True, text=True,
                                        timeout=120, preexec_fn=bounded)
                report = json.loads(result.stdout)
                pair[policy] = report
                reports.append(dict(run=repeat + 1, suite=suite, output=mode, policy=policy,
                                    order=order, command=command, report=report,
                                    elapsedSeconds=time.monotonic() - started))
            def observations(report):
                return {(r['name'], r['engine']): r for r in report['benchmarks']}
            before, after = observations(pair['before']), observations(pair['after'])
            assert before.keys() == after.keys()
            for key in before:
                for field in ('inputBytes', 'iterations', 'samples', 'output',
                              'expectedAccepted', 'outputHash', 'outputNodes',
                              'allocatorCallsPerOp', 'payloadBytesPerOp', 'reservedBytesPerOp'):
                    assert before[key][field] == after[key][field], (key, field)
            print(f'{repeat + 1}/5 {suite}/{mode}', flush=True)
    assert hashes == {p: hashlib.sha256(Path(b).read_bytes()).hexdigest()
                      for p, b in binaries.items()}
    args.output.write_text(json.dumps(dict(schemaVersion=1, milestone='B03', cpu=cpu,
        seed=303, runs=5, samples=7, warmupBatches=1, iterations=2000,
        memoryLimitBytes=4 * 1024**3, invocationTimeoutSeconds=120,
        binarySha256=hashes, measurements=reports), indent=2) + '\n')


if __name__ == '__main__':
    main()
