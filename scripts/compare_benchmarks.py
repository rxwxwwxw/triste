#!/usr/bin/env python3
"""Build once, verify common outputs, and report local D/chumsky measurements."""
import argparse
import json
import hashlib
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(command, *, env=None, timeout=300):
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True,
                            text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(map(str, command))}\n"
                           f"{result.stderr}\n{result.stdout}")
    return result


def positive(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError('must be positive')
    return number


def verify_groups(d_rows, rust_rows):
    """Reject a mismatched acceptance, corpus, or output before reporting ratios."""
    d_cases = {}
    for row in d_rows:
        d_cases.setdefault(row['name'], []).append(row)
    if len(rust_rows) != len(d_cases) or set(d_cases) != {row['name'] for row in rust_rows}:
        raise ValueError('D and chumsky benchmark case sets differ')
    for rust in rust_rows:
        group = [*d_cases[rust['name']], rust]
        for key in ('inputBytes', 'iterations', 'samples', 'output', 'expectedAccepted',
                    'outputHash', 'outputNodes'):
            if any(row[key] != group[0][key] for row in group):
                raise ValueError(f"Comparison mismatch: {rust['name']} field={key}")
        if len(group) != 4 or {row['engine'] for row in group} != {'Pegged', 'NPegged', 'Handwritten', 'Chumsky'}:
            raise ValueError(f"Missing/duplicate comparison engine: {rust['name']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iterations', type=positive, default=20)
    parser.add_argument('--samples', type=positive, default=5)
    parser.add_argument('--filter', default='')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    environment = os.environ.copy()
    environment.setdefault('CARGO_HOME', str(ROOT / 'build/cargo-home'))
    environment.setdefault('CARGO_TARGET_DIR', str(ROOT / 'build/chumsky'))
    compiler = Path(environment.get('DC', 'ldc2')).name
    build = run(['bash', 'scripts/benchmark.sh', '--export-corpus'], env=environment)
    corpus = json.loads(build.stdout)
    timed_cases = [case for case in corpus if case['timed'] and args.filter in case['name']]
    if not timed_cases:
        raise ValueError('No benchmark cases matched filter')
    # All acceptance-gate cases remain enabled even with a benchmark filter.
    corpus = [case for case in corpus if not case['timed'] or case in timed_cases]
    manifest = 'benchmark/chumsky/Cargo.toml'
    rust_build = run(['cargo', 'build', '--release', '--locked', '--manifest-path', manifest],
                     env=environment)
    rust_binary = str(Path(environment['CARGO_TARGET_DIR']) / 'release/triste-chumsky-benchmark')
    d_binary = str(ROOT / 'build' / compiler / 'benchmark_runner')
    rows = []
    checksums = {}
    with tempfile.TemporaryDirectory(prefix='triste-comparison-') as temporary:
        corpus_path = Path(temporary) / 'corpus.json'
        corpus_path.write_text(json.dumps(corpus))
        for mode in ('validation', 'spans', 'tree'):
            d_report = json.loads(run([d_binary, f'--iterations={args.iterations}',
                                      f'--samples={args.samples}', f'--filter={args.filter}',
                                      f'--mode={mode}', '--json', '--memory'], timeout=120).stdout)
            rust_report = json.loads(run([rust_binary, str(corpus_path), mode,
                                          str(args.iterations), str(args.samples)], timeout=120).stdout)
            verify_groups(d_report['benchmarks'], rust_report['benchmarks'])
            rows.extend(d_report['benchmarks'])
            rows.extend(rust_report['benchmarks'])
            checksums[mode] = {'D': d_report['checksum'], 'Chumsky': rust_report['checksum']}
    cpu = platform.processor()
    if Path('/proc/cpuinfo').is_file():
        cpu = next((line.split(':', 1)[1].strip()
                    for line in Path('/proc/cpuinfo').read_text().splitlines()
                    if line.startswith('model name')), cpu)
    result = {
        'schemaVersion': 2,
        'metadata': {
            'cpu': cpu, 'platform': platform.platform(),
            'dCompiler': compiler, 'dBuildLog': build.stderr,
            'rustCompiler': run(['rustc', '--version']).stdout.strip(),
            'chumskyVersion': '0.13.0',
            'rustProfile': 'release: opt-level=3, lto=true, codegen-units=1, panic=abort',
            'rustBuildLog': rust_build.stderr,
            'sourceHashes': {
                str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                for directory in ('src', 'benchmark', 'scripts')
                for path in sorted((ROOT / directory).rglob('*'))
                if path.is_file() and path.suffix in ('.d', '.rs', '.toml', '.lock', '.py', '.sh')
            },
            'revision': run(['git', 'rev-parse', 'HEAD']).stdout.strip(),
            'worktreeDirty': bool(run(['git', 'status', '--porcelain']).stdout),
            'iterations': args.iterations, 'samples': args.samples,
            'inputOwnership': 'caller retains immutable input; engine copies included where required',
            'timingIncludes': 'parse, output construction/projection, fingerprint, checksum, result disposal',
        },
        'benchmarks': rows,
        'checksums': checksums,
    }
    serialized = json.dumps(result, indent=2, allow_nan=False) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(serialized)
        print(f"Wrote {len(rows)} verified comparison rows to {args.output}", file=sys.stderr)
    else:
        print(serialized, end='')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
