#!/usr/bin/env python3
"""Performance gate must reject unequal work and incomplete measurements."""
import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from performance_gate import paired_ratios


class PerformanceGateTests(unittest.TestCase):
    def setUp(self):
        row = dict(name='Case', output='validation', inputBytes=10, iterations=100,
                   samples=7, expectedAccepted=True, outputHash=12, outputNodes=0, meanMs=2)
        self.report = {'benchmarks': [dict(row, engine='NPegged'),
                                      dict(row, engine='Handwritten', meanMs=0.5)]}

    def test_per_parse_ratio(self):
        result = paired_ratios(self.report, ['Case'], 'validation')[0]
        self.assertEqual(result['ratio'], 4)
        self.assertEqual(result['npNsPerParse'], 20000)
        self.assertEqual(result['handwrittenNsPerParse'], 5000)
        self.report['benchmarks'][0]['meanMs'] = 3
        self.assertGreater(paired_ratios(self.report, ['Case'], 'validation')[0]['ratio'], 5)

    def test_reject_unequal_work(self):
        for key in ('inputBytes', 'iterations', 'samples', 'output', 'expectedAccepted',
                    'outputHash', 'outputNodes'):
            report = copy.deepcopy(self.report)
            report['benchmarks'][1][key] = 'different'
            with self.subTest(key=key), self.assertRaises(ValueError):
                paired_ratios(report, ['Case'], 'validation')
        with self.assertRaises(ValueError):
            paired_ratios(self.report, ['Case'], 'tree')

    def test_reject_missing_duplicate_or_unexpected_engines(self):
        for rows in ([], self.report['benchmarks'][:1], self.report['benchmarks'] * 2,
                     [dict(self.report['benchmarks'][0], engine='Other')]):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                paired_ratios({'benchmarks': rows}, ['Case'], 'validation')
        with self.assertRaises(ValueError):
            paired_ratios(self.report, ['Other'], 'validation')

    def test_reject_unresolved_and_nonfinite_time(self):
        for value in (0, -1, float('inf'), float('nan')):
            self.report['benchmarks'][0]['meanMs'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                paired_ratios(self.report, ['Case'], 'validation')
        for key, value in (('samples', 6), ('iterations', 0)):
            report = copy.deepcopy(self.report)
            for row in report['benchmarks']:
                row[key] = value
                row['meanMs'] = 1
            with self.assertRaises(ValueError):
                paired_ratios(report, ['Case'], 'validation')


if __name__ == '__main__':
    unittest.main()
