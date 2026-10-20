#!/usr/bin/env python3
"""Collect DMD/GDC coverage from the maintained standalone integration workflows.

Only their main symbol is renamed in a temporary copy so the unchanged test
bodies can run together. Original files and thresholds remain unchanged.
"""
import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CASES = ('prefix_discrimination', 'next_bites', 'diagnostics', 'll_regions', 'll_export',
         'generator', 'acceptance_oracle', 'coverage_generation', 'policy_generation',
         'learning', 'fuzz_differential', 'corpus_generation', 'differential', 'entry')

def run(command, timeout=900):
    subprocess.run(command, cwd=ROOT, check=True, timeout=timeout)

def main():
    build = ROOT / 'build/coverage-workflows'
    (build / 'tests').mkdir(parents=True, exist_ok=True)
    for case in CASES:
        original = (ROOT / 'tests' / (case + '.d')).read_text()
        transformed, count = re.subn(r'\bint main\(', 'int coverageMain(', original)
        if count != 1:
            raise ValueError(f'{case}: expected exactly one standalone main')
        (build / 'tests' / (case + '.d')).write_text(transformed)
    driver = 'module coverage_workflows;\n'
    for case in CASES:
        driver += f'import tests.{case};\n'
    driver += 'int main() {\n'
    for case in CASES:
        driver += f'    if (tests.{case}.coverageMain() != 0) return 1;\n'
    driver += '    return 0;\n}\n'
    (build / 'driver.d').write_text(driver)
    library = [str(p.relative_to(ROOT)) for p in sorted((ROOT / 'src').rglob('*.d'))]
    tests = ['build/coverage-workflows/tests/' + case + '.d' for case in CASES]
    for compiler in ('dmd', 'gdc'):
        binary = 'build/coverage-workflows/' + compiler + '-workflows'
        common = ['-Isrc', '-Ibuild/coverage-workflows', '-I.', '-Iperformance/scripts']
        if compiler == 'dmd':
            flags = ['-defaultlib=druntime', '-nothrow', '-w', '-unittest', '-cov', '-checkaction=halt', '-version=NPeggedDFAEdgeCoverage', '-version=NPeggedLeanEntry']
            output = ['-of=' + binary]
        else:
            flags = ['-nophoboslib', '-fno-exceptions', '-fno-unwind-tables',
                     '-fno-asynchronous-unwind-tables', '-fcheckaction=context', '-g', '-Wall', '-Werror',
                     '-funittest', '-fversion=NPeggedDFAEdgeCoverage', '-fversion=NPeggedLeanEntry', '--coverage', '-fprofile-abs-path',
                     '-fdump-ipa-profile-details-blocks-lineno']
            output = ['-o', binary, '-lgdruntime']
        run(['prlimit', '--as=4294967296', 'timeout', '--kill-after=2s', '900s',
             compiler, *common, *flags, *library, 'performance/scripts/corpus_lib.d', *tests, 'build/coverage-workflows/driver.d', *output], 910)
        run(['prlimit', '--as=4294967296', 'timeout', '--kill-after=2s', '240s',
             binary, '--DRT-testmode=run-main'], 245)
        run(['bash', 'scripts/collect_coverage.sh', 'build/coverage', binary, compiler + '-workflows'])

if __name__ == '__main__':
    main()
