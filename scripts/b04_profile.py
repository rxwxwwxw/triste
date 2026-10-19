#!/usr/bin/env python3
"""Collect bounded, source-verified Callgrind evidence for the B04 decision.

Instruction counts are diagnostics, never latency measurements or causal Amdahl
fractions. The existing benchmark also executes parity checks and both engines.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounded():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))



def summarize(annotation, name):
    total = int(re.search(r'([\d,]+) \(100.0%\)  PROGRAM TOTALS', annotation)[1].replace(',', ''))
    functions = []
    for line in annotation.splitlines():
        match = re.match(r'\s*([\d,]+)\s+\(\s*[\d.]+%\)\s+[^:]*:(.*) \[.*\]$', line)
        if match:
            functions.append((int(match[1].replace(',', '')), match[2]))
    append = sum(n for n, function in functions
                 if function.startswith('npegged.records.RecordBuffer.openKind('))
    memo = sum(n for n, function in functions
               if function.startswith('npegged.peg.State!') and '.memoizedRule!' in function)
    return dict(profile=name, totalInstructions=total, openKindSelfInstructions=append,
                openKindProgramShare=append / total, memoizedRuleOutOfLineSelfInstructions=memo,
                topFunctions=[dict(selfInstructions=n, function=f) for n, f in functions[:5]])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=ROOT / 'build/B03/before-runner')
    parser.add_argument('--binary-sha256', help='Explicit expected hash for an alternate source-matched binary')
    parser.add_argument('--gate', type=Path, default=ROOT / 'performance/phase3/B03-before-gate.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'performance/phase3/B04-profiles')
    args = parser.parse_args()
    os.chdir(ROOT)
    gate = json.loads(args.gate.read_text())
    sources = {name: sha for name, sha in gate['metadata']['sourceHashes'].items()
               if name.startswith(('src/', 'benchmark/'))}
    for name, sha in sources.items():
        assert digest(ROOT / name) == sha, f'Source mismatch: {name}'
    binary = args.binary.resolve()
    binary_hash = digest(binary)
    expected_hash = args.binary_sha256
    if expected_hash is None:
        expected_hash = json.loads((ROOT / 'performance/phase3/B03-validation.json').read_text())['binaries']['before']
    assert binary_hash == expected_hash, 'Binary differs from the preserved verified baseline'
    args.output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment['DEBUGINFOD_URLS'] = 'https://debuginfod.cachyos.org'
    environment['DEBUGINFOD_CACHE_PATH'] = str(ROOT / 'build/debug-cache-cachy')
    provenance = dict(binarySha256=binary_hash, sourceHashes=sources)
    checkpoint = args.output / 'provenance.json'
    if checkpoint.exists():
        assert json.loads(checkpoint.read_text()) == provenance
    else:
        assert not list(args.output.glob('*.callgrind.gz')), 'Cannot resume without provenance'
        checkpoint.write_text(json.dumps(provenance, indent=2) + '\n')
    jobs = [(name, mode) for name in ('PEGGrammar.ManyRules', 'CSV.Flat', 'Arithmetic.Flat',
             'JSON.WhitespaceHeavy', 'Numbers.BinaryLong') for mode in ('validation', 'spans', 'tree')]
    jobs += [('Ambiguous.Retry', 'validation'), ('CSV.SingleLine', 'validation'),
             ('JSON.InvalidTruncated', 'spans')]
    rows = []
    summaries = []
    for name, mode in jobs:
        prefix = args.output / f'{name}-{mode}'
        profile = prefix.with_suffix(prefix.suffix + '.callgrind')
        command = ['valgrind', '--tool=callgrind', f'--callgrind-out-file={profile}',
                   str(binary), '--target-engines', f'--filter={name}', f'--mode={mode}',
                   '--iterations=100', '--samples=7', '--json']
        if not name.startswith(('JSON.', 'Ambiguous.')):
            command.append('--workloads')
        report_path = prefix.with_suffix(prefix.suffix + '.benchmark.json')
        compressed = profile.with_suffix(profile.suffix + '.gz')
        if compressed.exists() and report_path.exists():
            # Resume only artifacts whose source and binary hashes are bound by
            # the checkpoint written before launching any profile.
            checkpoint = json.loads((args.output / 'provenance.json').read_text())
            assert checkpoint == dict(binarySha256=binary_hash, sourceHashes=sources)
            report = json.loads(report_path.read_text())
            raw = gzip.decompress(compressed.read_bytes())
            rows.append(dict(name=name, mode=mode, command=command, report=report,
                             profileSha256=hashlib.sha256(raw).hexdigest()))
            annotation_path = prefix.with_suffix(prefix.suffix + '.annotation.txt')
            summaries.append(summarize(annotation_path.read_text(), annotation_path.name))
            continue
        result = subprocess.run(command, capture_output=True, text=True, check=True,
                                timeout=60, preexec_fn=bounded, env=environment)
        report = json.loads(result.stdout)
        observed = report['benchmarks']
        assert len(observed) == 2 and {r['engine'] for r in observed} == {'NPegged', 'Handwritten'}
        for field in ('expectedAccepted', 'outputHash', 'outputNodes', 'inputBytes', 'output'):
            assert observed[0][field] == observed[1][field], (name, mode, field)
        annotation = subprocess.run(['callgrind_annotate', '--auto=no', '--threshold=100', str(profile)],
                                    capture_output=True, text=True, check=True, timeout=30).stdout
        annotation_path = prefix.with_suffix(prefix.suffix + '.annotation.txt')
        annotation_path.write_text(annotation)
        summaries.append(summarize(annotation, annotation_path.name))
        prefix.with_suffix(prefix.suffix + '.benchmark.json').write_text(result.stdout)
        prefix.with_suffix(prefix.suffix + '.log').write_text(result.stderr)
        raw = profile.read_bytes()
        profile.with_suffix(profile.suffix + '.gz').write_bytes(gzip.compress(raw, mtime=0))
        profile.unlink()
        rows.append(dict(name=name, mode=mode, command=command, report=report,
                         profileSha256=hashlib.sha256(raw).hexdigest()))
        print(f'{name}/{mode}', flush=True)
    assert digest(binary) == binary_hash
    for name, sha in sources.items():
        assert digest(ROOT / name) == sha, f'Source changed: {name}'
    manifest = dict(milestone='B04', revision=gate['metadata']['revision'],
                    binarySha256=binary_hash, sourceHashes=sources,
                    compilerBuildLog=gate['metadata']['buildLog'], platform=platform.platform(),
                    valgrindVersion=subprocess.check_output(['valgrind', '--version'], text=True).strip(),
                    memoryLimitBytes=4 * 1024**3, timeoutSeconds=60,
                    measurement='Diagnostic instruction counts; includes benchmark parity checks and both engines; not latency',
                    profiles=rows)
    (args.output.parent / 'B04-profile-summary.json').write_text(
        json.dumps(dict(milestone='B04', profiles=summaries), indent=2) + '\n')
    (args.output.parent / 'B04-profile-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
