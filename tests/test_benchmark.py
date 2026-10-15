"""Release-runner integration checks; every subprocess has a deadline."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest


class BenchmarkRunnerTests(unittest.TestCase):
    runner = sys.argv[1] if len(sys.argv) > 1 else 'build/ldc2/benchmark_runner'

    def run_runner(self, *args):
        result = subprocess.run([self.runner, *args], capture_output=True,
                                text=True, timeout=30, cwd=os.environ.get('BENCH_RUN_CWD'))
        capture = os.environ.get('BENCH_COVERAGE_CAPTURE')
        if capture:
            root = Path(capture)
            root.mkdir(parents=True, exist_ok=True)
            destination = root / f'run-{len(list(root.iterdir()))}'
            destination.mkdir()
            for report in Path(os.environ['BENCH_RUN_CWD']).glob('*.lst'):
                shutil.copy2(report, destination / report.name)
        return result

    def test_measurements(self):
        result = self.run_runner('--iterations=2', '--samples=2', '--json', '--memory')
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['schemaVersion'], 2)
        self.assertEqual(len(report['benchmarks']), 63)
        self.assertNotEqual(report['checksum'], 0)
        for row in report['benchmarks']:
            self.assertEqual(row['iterations'], 2)
            self.assertEqual(row['samples'], 2)
            self.assertEqual(len(row['sampleMs']), 2)
            self.assertAlmostEqual(sum(row['sampleMs']) / 2, row['meanMs'], places=8)
            self.assertLessEqual(row['minMs'], row['meanMs'])
            self.assertLessEqual(row['meanMs'], row['maxMs'])
            self.assertGreaterEqual(row['MBps'], 0)
            if row['meanMs'] > 0:
                self.assertGreater(row['MBps'], 0)
            expected = 'validation' if row['engine'] == 'Handwritten' else 'full-tree'
            self.assertEqual(row['output'], expected)

    def test_filter_and_memory(self):
        result = self.run_runner('--filter=JSON.Small', '--iterations=1',
                                 '--samples=1', '--memory', '--json')
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = json.loads(result.stdout)['benchmarks']
        self.assertEqual(len(rows), 3)
        np = rows[1]
        self.assertGreater(np['allocatorCallsPerOp'], 0)
        self.assertGreater(np['payloadBytesPerOp'], 0)
        self.assertGreater(np['reservedBytesPerOp'], np['payloadBytesPerOp'])
        self.assertEqual(np['reservedBytesPerOp'], np['arenaCumulativeBytes'])
        self.assertTrue(np['arenaMeasured'])
        self.assertEqual(np['gcBytesPerOp'], 0)
        self.assertFalse(rows[0]['arenaMeasured'])

    def test_equal_output_modes(self):
        for mode in ('validation', 'spans', 'tree'):
            with self.subTest(mode=mode):
                result = self.run_runner('--iterations=2', '--samples=2', '--memory',
                                         '--json', '--mode=' + mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                rows = json.loads(result.stdout)['benchmarks']
                self.assertEqual(len(rows), 39)
                for offset in range(0, len(rows), 3):
                    group = rows[offset:offset + 3]
                    self.assertEqual(len({r['outputHash'] for r in group}), 1)
                    self.assertEqual(len({r['outputNodes'] for r in group}), 1)
                    self.assertTrue(all(r['output'] == mode for r in group))
                    self.assertTrue(group[1]['arenaMeasured'])
                    self.assertTrue(group[2]['arenaMeasured'])
                    if mode == 'validation':
                        self.assertEqual(group[2]['allocatorCallsPerOp'], 0)
                    if not group[0]['expectedAccepted']:
                        self.assertEqual(group[0]['outputNodes'], 0)

    def test_legacy_aliases_and_help(self):
        result = self.run_runner('-n', '2', '--samples', '2', '-f', 'JSON.Small', '-m', '--json')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(result.stdout)['benchmarks']), 3)
        substring = self.run_runner('--filter=SON.Small', '-n', '1', '--samples=1', '--json')
        self.assertEqual(substring.returncode, 0, substring.stderr)
        self.assertEqual(len(json.loads(substring.stdout)['benchmarks']), 3)
        for flag in ('--help', '-h'):
            result = self.run_runner(flag)
            self.assertEqual(result.returncode, 0)
            self.assertIn('Usage:', result.stdout)

    def test_human_output(self):
        result = self.run_runner('--filter=JSON.Small', '--iterations=1', '--samples=1', '--memory')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Checksum:', result.stdout)
        self.assertIn('allocator calls=', result.stdout)
        self.assertIn('NPegged', result.stdout)

    def test_invalid_options(self):
        for option in ('--iterations=0', '--samples=0', '--iterations=x',
                       '--samples=999999999999999999999999999', '--mode=nope', '--unknown'):
            with self.subTest(option=option):
                self.assertEqual(self.run_runner(option).returncode, 2)
        self.assertEqual(self.run_runner('--filter=does-not-exist').returncode, 1)


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0]])
