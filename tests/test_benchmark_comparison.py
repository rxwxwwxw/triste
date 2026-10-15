"""Cross-language benchmark contract tests; subprocesses always have deadlines."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('compare_benchmarks', ROOT / 'scripts/compare_benchmarks.py')
compare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compare)


class ComparisonContractTests(unittest.TestCase):
    d_runner = ROOT / 'build/ldc2/benchmark_runner'
    rust_runner = ROOT / 'build/chumsky/release/triste-chumsky-benchmark'

    @classmethod
    def setUpClass(cls):
        result = subprocess.run([cls.d_runner, '--export-corpus'], capture_output=True,
                                text=True, timeout=30, check=True)
        cls.corpus = json.loads(result.stdout)

    def rust(self, corpus, mode):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'corpus.json'
            path.write_text(json.dumps(corpus))
            return subprocess.run([self.rust_runner, path, mode, '2', '2'],
                                  capture_output=True, text=True, timeout=30)

    def test_all_modes_match(self):
        for mode in ('validation', 'spans', 'tree'):
            with self.subTest(mode=mode):
                d = subprocess.run([self.d_runner, '--json', '--memory', '--iterations=2',
                                    '--samples=2', '--mode=' + mode], capture_output=True,
                                   text=True, timeout=30, check=True)
                rust = self.rust(self.corpus, mode)
                self.assertEqual(rust.returncode, 0, rust.stderr)
                d_rows = json.loads(d.stdout)['benchmarks']
                rust_rows = json.loads(rust.stdout)['benchmarks']
                self.assertEqual(len(rust_rows), 13)
                compare.verify_groups(d_rows, rust_rows)
                for row in rust_rows:
                    self.assertTrue(row['allocatorMeasured'])
                    self.assertIsNone(row['reservedBytesPerOp'])
                    self.assertGreaterEqual(row['allocatorCallsPerOp'], 0)

    def test_reject_acceptance_and_record_mismatches(self):
        case = copy.deepcopy(self.corpus[0])
        case['expectedAccepted'] = not case['expectedAccepted']
        result = self.rust([case], 'tree')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Acceptance mismatch', result.stderr)
        case = copy.deepcopy(self.corpus[0])
        case['expectedTree'][0][1] += 1
        result = self.rust([case], 'tree')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Output record mismatch', result.stderr)

    def test_group_verifier(self):
        base = dict(name='case', inputBytes=1, iterations=2, samples=2,
                    output='tree', expectedAccepted=True, outputHash=42, outputNodes=1)
        d = [dict(base, engine=engine) for engine in ('Pegged', 'NPegged', 'Handwritten')]
        rust = [dict(base, engine='Chumsky')]
        compare.verify_groups(d, rust)
        for key in ('inputBytes', 'iterations', 'samples', 'output', 'expectedAccepted',
                    'outputHash', 'outputNodes'):
            changed = copy.deepcopy(rust)
            changed[0][key] = None
            with self.subTest(key=key), self.assertRaises(ValueError):
                compare.verify_groups(d, changed)
        with self.assertRaises(ValueError):
            compare.verify_groups(d, [])
        with self.assertRaises(ValueError):
            compare.verify_groups(d[:2], rust)
        with self.assertRaises(ValueError):
            compare.verify_groups(d, rust * 2)


if __name__ == '__main__':
    unittest.main()
