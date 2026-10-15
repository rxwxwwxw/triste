#!/usr/bin/env python3
"""Exercise the coverage gate's src-only scope through its CLI."""
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

VERIFIER = Path(__file__).with_name('verify_coverage.py').resolve()


class CoverageScopeTests(unittest.TestCase):
    def run_gate(self, hits=None, missing=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'src/module.d'
            source.parent.mkdir()
            source.write_text('module module;\nint value() { return 1; }\n')
            coverage = root / 'build/coverage'
            (coverage / 'lines').mkdir(parents=True)
            (coverage / 'branches').mkdir()
            manifest = {'src/module.d': hashlib.sha256(source.read_bytes()).hexdigest()}
            for folder in ('tests', 'examples', 'benchmark', 'scripts'):
                excluded = root / folder / 'excluded.d'
                excluded.parent.mkdir()
                excluded.write_text('module excluded;\n')
                # Old manifests may include excluded files with stale hashes.
                manifest[f'{folder}/excluded.d'] = 'stale'
                (coverage / 'lines' / f'{folder}.lst').write_text(
                    f'0|uncovered\n{folder}/excluded.d is 0% covered\n')
            (coverage / 'sources.json').write_text(json.dumps(manifest))
            (coverage / 'branches/fixture.profile').write_text('')
            if not missing:
                counts = hits if hits is not None else [1]
                (coverage / 'lines/module.lst').write_text(
                    ''.join(f'{hit}|code\n' for hit in counts)
                    + 'src/module.d is 100% covered\n')
                with gzip.open(coverage / 'branches/fixture.gcov.json.gz', 'wt') as stream:
                    json.dump({'files': [{'file': 'src/module.d', 'lines': []}]}, stream)
            return subprocess.run([sys.executable, str(VERIFIER)], cwd=root,
                                  capture_output=True, text=True, timeout=10)

    def test_excluded_files_do_not_fail_gate(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_src_at_threshold_fails(self):
        result = self.run_gate([1] * 9 + [0])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('src/module.d: line coverage 90.00%', result.stderr)

    def test_missing_src_reports_fail(self):
        result = self.run_gate(missing=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('src/module.d: missing line coverage', result.stderr)
        self.assertIn('src/module.d: missing branch coverage', result.stderr)


if __name__ == '__main__':
    unittest.main()
