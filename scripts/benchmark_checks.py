#!/usr/bin/env python3
"""Verify benchmark unit/integration behavior and per-module D coverage."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'build/benchmark-checks'
COVERAGE = ROOT / 'build/benchmark-coverage'


def run(command, *, cwd=ROOT, env=None, timeout=300):
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True,
                            text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"Failed ({result.returncode}): {' '.join(map(str, command))}\n"
                           f"{result.stdout}\n{result.stderr}")
    return result


def main():
    run([sys.executable, str(ROOT / 'tests/test_performance_gate.py')], timeout=30)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Keep each fresh collection isolated from core coverage and older benchmark runs.
    if COVERAGE.exists():
        shutil.rmtree(COVERAGE)
    for pattern in ('units-gdc-*.gcda', 'root-units-gdc-*.gcda', 'runner-gdc-*.gcda'):
        for report in OUTPUT.glob(pattern):
            report.unlink()
    (COVERAGE / 'lines').mkdir(parents=True)
    (COVERAGE / 'branches').mkdir()
    standalone = ('recursion_scaling.d', 'dfa_scanning.d', 'p09_crossover.d', 'p11_flat_bench.d', 'p13_tuning.d')
    sources = [path for path in sorted((ROOT / 'benchmark').rglob('*.d'))
               if ('handwritten' not in path.parts or path.name == 'json.d') and path.name not in standalone]
    (COVERAGE / 'sources.json').write_text(json.dumps({
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sources
    }))
    includes = [f'-I{ROOT}', f'-I{ROOT / "src"}', f'-I{ROOT / "third-party/Pegged"}',
                f'-I{ROOT / "third-party/Pegged/examples/arithmetic/src"}',
                f'-I{ROOT / "third-party/Pegged/examples/csv/src"}',
                f'-I{ROOT / "third-party/Pegged/examples/numbers/src"}']
    # GDC below is used separately for branch-coverage collection only.
    for compiler in (('dmd', 'ldc2', 'gdc') if os.environ.get('BENCH_BRANCH_COVERAGE') == '1'
                     else ('dmd', 'ldc2')):
        print(f'Checking benchmark units with {compiler}...', flush=True)
        flags = ['-i', '-unittest', '-main', '-w', '-de', '-checkaction=halt'] if compiler != 'gdc' else [
            '-finclude-imports', '-funittest', '-fmain', '-Wall', '-Werror', '-fcheckaction=halt']
        if compiler == 'dmd':
            flags += ['-cov']
        elif compiler == 'gdc':
            flags += ['--coverage', '-fprofile-abs-path', '-fdump-ipa-profile-details-blocks-lineno']
        binary = OUTPUT / f'units-{compiler}'
        output = [f'-of={binary}'] if compiler != 'gdc' else ['-o', str(binary)]
        run([compiler, *includes, *flags, str(ROOT / 'benchmark/unit_tests.d'), *output])
        working = OUTPUT / f'run-units-{compiler}'
        working.mkdir(exist_ok=True)
        (working / 'build').mkdir(exist_ok=True)
        run([str(binary)], cwd=working, timeout=30)
        if compiler == 'dmd':
            destination = COVERAGE / 'lines/unit'
            destination.mkdir()
            for report in working.glob('*.lst'):
                shutil.copy2(report, destination / report.name)

    # Root runner integration instrumentation uses its release assertion/bounds settings.
    # Imported code is included explicitly to avoid instrumenting Phobos dependencies.
    maintained = [*sorted((ROOT / 'src').rglob('*.d')),
                  *sorted((ROOT / 'benchmark').glob('*.d')),
                  *sorted((ROOT / 'benchmark/handwritten').glob('*.d'))]
    maintained.remove(ROOT / 'benchmark/unit_tests.d')
    # Standalone diagnostics have their own main and bounded runner scripts.
    for name in standalone:
        if (ROOT / 'benchmark' / name) in maintained:
            maintained.remove(ROOT / 'benchmark' / name)
    pegged = [p for p in sorted((ROOT / 'third-party/Pegged/pegged').rglob('*.d'))
              if len(p.relative_to(ROOT / 'third-party/Pegged/pegged').parts) <= 2
              and not p.name.startswith(('tester', 'tohtml'))]
    examples = [ROOT / f'examples/{name}.d' for name in ('arithmetic', 'csv', 'numbers')]
    examples += [ROOT / f'third-party/Pegged/examples/{name}/src/pegged/examples/{name}.d'
                 for name in ('arithmetic', 'csv', 'numbers')]
    # The root runner uses the benchmark JSON grammar, not the illustrative legacy JSON module.
    runner_sources = [str(p) for p in [*maintained, *pegged, *examples]]
    # GDC below is used separately for branch-coverage collection only.
    for compiler in (('dmd', 'ldc2', 'gdc') if os.environ.get('BENCH_BRANCH_COVERAGE') == '1'
                     else ('dmd', 'ldc2')):
        print(f'Checking runner unit tests with {compiler}...', flush=True)
        binary = OUTPUT / f'root-units-{compiler}'
        flags = ['-i', '-unittest', '-w', '-de', '-checkaction=halt'] if compiler != 'gdc' else ['-finclude-imports', '-funittest', '-Wall', '-Werror', '-fcheckaction=halt']
        if compiler == 'dmd': flags += ['-cov']
        elif compiler == 'gdc': flags += ['--coverage', '-fprofile-abs-path', '-fdump-ipa-profile-details-blocks-lineno']
        output = [f'-of={binary}'] if compiler != 'gdc' else ['-o', str(binary)]
        unit_sources = [str(p) for p in [*maintained, *examples]]
        run([compiler, *includes, *flags, *unit_sources, *output])
        working = OUTPUT / f'run-root-units-{compiler}'
        (working / 'build').mkdir(parents=True, exist_ok=True)
        run([str(binary), '--help'], cwd=working, timeout=30)
        if compiler == 'dmd':
            destination = COVERAGE / 'lines/root-unit'
            destination.mkdir()
            for report in working.glob('*.lst'):
                shutil.copy2(report, destination / report.name)

    for compiler in (('dmd', 'gdc') if os.environ.get('BENCH_BRANCH_COVERAGE') == '1' else ('dmd',)):
        print(f'Collecting benchmark runner coverage with {compiler}...', flush=True)
        binary = OUTPUT / f'runner-{compiler}'
        flags = ['-cov', '-release', '-boundscheck=off', '-w', '-de', '-checkaction=halt'] if compiler == 'dmd' else [
            '--coverage', '-frelease', '-fno-bounds-check', '-fprofile-abs-path', '-fdump-ipa-profile-details-blocks-lineno', '-Wall', '-Werror', '-fcheckaction=halt']
        output = [f'-of={binary}'] if compiler == 'dmd' else ['-o', str(binary)]
        run([compiler, *includes, *flags, *runner_sources, *output])
        working = OUTPUT / f'run-runner-{compiler}'
        working.mkdir(exist_ok=True)
        environment = os.environ.copy()
        environment['BENCH_RUN_CWD'] = str(working)
        if compiler == 'dmd':
            environment['BENCH_COVERAGE_CAPTURE'] = str(COVERAGE / 'lines/integration')
        run([sys.executable, str(ROOT / 'tests/test_benchmark.py'), str(binary)], env=environment, timeout=120)
        run([str(binary), '--export-corpus'], cwd=working, timeout=30)
        if compiler == 'dmd':
            destination = COVERAGE / 'lines/export'
            destination.mkdir()
            for report in working.glob('*.lst'):
                shutil.copy2(report, destination / report.name)

    # Collect diagnostic branch coverage only when explicitly requested.
    # Required compiler compliance above is DMD/LDC; this collector needs GDC/gcov.
    if os.environ.get('BENCH_BRANCH_COVERAGE', '0') != '1':
        print(f'Benchmark checks passed; line coverage: {COVERAGE}; '
              'branch coverage not collected (set BENCH_BRANCH_COVERAGE=1).')
        return

    # Each binary needs its own CFG map; debug units and release runner differ.
    for category, prefix in (('unit', 'units-gdc-'), ('root-unit', 'root-units-gdc-'), ('integration', 'runner-gdc-')):
        destination = COVERAGE / 'branches' / category
        destination.mkdir()
        for pattern in ('*.gcno', '*.gcda', '*.profile'):
            for report in OUTPUT.glob(pattern):
                if report.name.startswith(prefix):
                    shutil.copy2(report, destination / report.name)
        for notes in destination.glob('*.gcno'):
            run(['gcov', '--json-format', '--branch-probabilities', notes.name], cwd=destination)
    print(f'Benchmark checks passed; diagnostic coverage reports: {COVERAGE}')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
