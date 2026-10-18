#!/usr/bin/env python3
"""Run repeated paired performance gates for the current equal-output corpus."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

from compare_benchmarks import ROOT, positive, run


def paired_ratios(report, names, mode):
    """Reject incomplete, unequal or unresolved measurements before computing ratios."""
    pairs = {}
    for row in report['benchmarks']:
        key = row['name']
        engine = row['engine']
        if engine not in ('NPegged', 'Handwritten') or engine in pairs.setdefault(key, {}):
            raise ValueError(f'Unexpected or duplicate engine: {key}/{engine}')
        pairs[key][engine] = row
    if set(pairs) != set(names):
        raise ValueError('Timed corpus differs from the exported corpus')
    result = []
    for name in names:
        pair = pairs[name]
        if set(pair) != {'NPegged', 'Handwritten'}:
            raise ValueError(f'Missing paired engine: {name}')
        np, hand = pair['NPegged'], pair['Handwritten']
        if np['output'] != mode:
            raise ValueError(f'Unexpected output mode: {name}')
        for key in ('inputBytes', 'iterations', 'samples', 'output', 'expectedAccepted',
                    'outputHash', 'outputNodes'):
            if np[key] != hand[key]:
                raise ValueError(f'Unequal output/work: {name}/{key}')
        for row in (np, hand):
            if row['iterations'] <= 0 or row['samples'] < 7:
                raise ValueError(f'Insufficient measurement: {name}')
            if not math.isfinite(row['meanMs']) or row['meanMs'] <= 0:
                raise ValueError(f'Unresolved clock or nonfinite measurement: {name}')
        result.append({'name': name, 'output': mode,
                       'ratio': np['meanMs'] / hand['meanMs'],
                       'npNsPerParse': np['meanMs'] * 1e6 / np['iterations'],
                       'handwrittenNsPerParse': hand['meanMs'] * 1e6 / hand['iterations']})
    return result


def source_hashes():
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for directory in ('src', 'benchmark', 'scripts', 'tests')
            for path in sorted((ROOT / directory).rglob('*'))
            if path.is_file() and path.suffix in ('.d', '.py', '.sh', '.rs', '.toml', '.lock')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iterations', type=positive, default=2000)
    parser.add_argument('--samples', type=positive, default=7)
    parser.add_argument('--runs', type=positive, default=3)
    parser.add_argument('--modes', nargs='+', choices=('validation', 'spans', 'tree'),
                        default=['validation', 'spans', 'tree'])
    parser.add_argument('--target-ratio', type=float, default=1.5,
                        help='Target maximum ratio against handwritten baseline (default: 1.5)')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/performance-acceptance.json')
    args = parser.parse_args()
    if args.samples < 7 or args.runs < 3 or len(set(args.modes)) != len(args.modes):
        parser.error('require at least seven samples, three runs, and unique modes')
    before = source_hashes()
    environment = os.environ.copy()
    compiler = Path(environment.get('DC', 'ldc2')).name
    build_started = time.monotonic()
    build = run(['bash', 'scripts/benchmark.sh', '--export-corpus'], env=environment)
    build_seconds = time.monotonic() - build_started
    corpus = json.loads(build.stdout)
    names = [case['name'] for case in corpus if case['timed']]
    reports, ratios = [], []
    binary = str(ROOT / 'build' / compiler / 'benchmark_runner')
    text_bytes = None
    if shutil.which('size'):
        sections = run(['size', '-A', binary], timeout=10).stdout.splitlines()
        text_bytes = sum(int(fields[1]) for line in sections
                         if (fields := line.split()) and fields[0].startswith('.text'))
    workload_corpora = {}
    jobs = [('json-ambiguity', mode, names, []) for mode in args.modes]
    for mode in dict.fromkeys(['validation', *args.modes]):
        workload_corpus = json.loads(run([binary, '--workloads', '--export-corpus',
                                         f'--mode={mode}'], env=environment, timeout=120).stdout)
        workload_names = [case['name'] for case in workload_corpus if case['timed']]
        if not workload_names:
            raise ValueError(f'Missing handwritten workload corpus: {mode}')
        workload_corpora[mode] = workload_corpus
        jobs.append(('handwritten-workloads', mode, workload_names, ['--workloads']))
    for repeat in range(args.runs):
        for suite, mode, case_names, extra in jobs:
            measured = json.loads(run([binary, '--target-engines', '--json', '--memory',
                                       f'--mode={mode}', f'--iterations={args.iterations}',
                                       f'--samples={args.samples}', *extra], env=environment, timeout=120).stdout)
            paired = paired_ratios(measured, case_names, mode)
            for row in paired:
                row['run'] = repeat + 1
                row['suite'] = suite
            ratios.extend(paired)
            reports.append({'run': repeat + 1, 'suite': suite, 'output': mode, 'report': measured})
            print(f'Run {repeat + 1}/{args.runs} {suite}/{mode}: worst ratio '
                  f"{max(row['ratio'] for row in paired):.3f}x", file=sys.stderr)
    if source_hashes() != before:
        raise ValueError('Sources changed during measurement; discard this run')
    cpu = platform.processor()
    if Path('/proc/cpuinfo').is_file():
        cpu = next((line.split(':', 1)[1].strip()
                    for line in Path('/proc/cpuinfo').read_text().splitlines()
                    if line.startswith('model name')), cpu)
    failed = [row for row in ratios if row['ratio'] > args.target_ratio]
    result = {'schemaVersion': 1, 'passed': not failed, 'targetRatio': args.target_ratio,
              'coverage': 'JSON/ambiguity selected output modes; arithmetic/CSV selected output modes; numbers and handwritten PEG syntax validation',
              'corpora': {'json-ambiguity': corpus, 'handwritten-workloads': workload_corpora['validation'],
                          'handwritten-workload-outputs': workload_corpora},
              'allOutputModes': set(args.modes) == {'validation', 'spans', 'tree'},
              'metadata': {'cpu': cpu, 'platform': platform.platform(),
                           'compiler': compiler, 'buildLog': build.stderr,
                           'backend': environment.get('PARSER_BACKEND', 'combinators'),
                           'buildAndExportSeconds': build_seconds,
                           'binaryBytes': Path(binary).stat().st_size,
                           'textBytes': text_bytes,
                           'revision': run(['git', 'rev-parse', 'HEAD']).stdout.strip(),
                           'worktreeDirty': bool(run(['git', 'status', '--porcelain']).stdout),
                           'sourceHashes': before, 'iterations': args.iterations,
                           'samples': args.samples, 'runs': args.runs,
                           'ratioDefinition': f'paired mean time per parse; every case must be <={args.target_ratio} in every run'},
              'ratios': ratios, 'failures': failed, 'measurements': reports}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
    print(f"{'PASS' if not failed else 'FAIL'}: {len(ratios) - len(failed)}/{len(ratios)} "
          f'paired checks; report: {args.output}')
    return bool(failed)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
