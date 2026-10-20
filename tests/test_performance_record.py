#!/usr/bin/env python3
"""A1 recorder: equal-output pair, unequal rejected, missing baseline N/A, stable schema."""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'performance/scripts'))
import record


def bench(engine, ms, digest=7, name='Case'):
    return dict(name=name, engine=engine, output='validation', inputBytes=100, iterations=10,
                samples=3, expectedAccepted=True, outputHash=digest, sampleMs=[ms, ms, ms * 1.1])


def report(rows):
    return dict(targetRatio=1.5, corpora={'s': [dict(name='Case', input='x', grammar='g',
                                                    expectedAccepted=True, timed=True)]},
                metadata=dict(compiler='ldc2', revision='abc' * 13, worktreeDirty=False, cpu='arm',
                              backend='combinators', runs=1, samples=3, iterations=10,
                              binaryBytes=1, textBytes=1, buildAndExportSeconds=1.0),
                measurements=[dict(run=1, suite='s', output='validation', report=dict(benchmarks=rows))])


class RecordTests(unittest.TestCase):
    def test_equal_pair_ratio(self):
        raw, summary, ok = record.build_tables(report([bench('NPegged', 2), bench('Handwritten', 1)]), 'r')
        self.assertTrue(ok['ok'])
        self.assertEqual(len(raw), 6)
        np = [r for r in summary if r['implementation'] == 'npegged'][0]
        self.assertEqual(float(np['slowdown_ratio']), 2.0)
        self.assertEqual(list(raw[0]), record.RAW_COLUMNS)
        self.assertEqual(list(summary[0]), record.SUMMARY_COLUMNS)

    def test_unequal_output_flagged(self):
        _, summary, ok = record.build_tables(
            report([bench('NPegged', 2, digest=1), bench('Handwritten', 1, digest=2)]), 'r')
        self.assertFalse(ok['ok'])
        self.assertIsNone(record.dashboard_stats(summary))

    def test_missing_baseline_is_na(self):
        _, summary, _ = record.build_tables(report([bench('NPegged', 2)]), 'r')
        self.assertEqual(summary[0]['slowdown_ratio'], 'N/A')
        self.assertEqual(summary[0]['handwritten_median_ns'], 'N/A')

    def test_missing_samples_rejected(self):
        row = bench('NPegged', 2)
        del row['sampleMs']
        with self.assertRaises(ValueError):
            record.build_tables(report([row]), 'r')

    def test_repeat_preserves_schema_and_refuses_overwrite(self):
        rep = report([bench('NPegged', 2), bench('Handwritten', 1)])
        with tempfile.TemporaryDirectory() as tmp:
            old = (record.PERF, )
            record.PERF = Path(tmp)
            try:
                a = record.record(rep, Path(tmp) / 'b', 'r1', 'baseline', '')
                b = record.record(copy.deepcopy(rep), Path(tmp) / 'b', 'r2', 'baseline', '')
                self.assertEqual((a / 'raw.csv').read_text().splitlines()[0],
                                 (b / 'raw.csv').read_text().splitlines()[0])
                self.assertEqual(json.loads((a / 'metadata.json').read_text())['corpus_checksums'],
                                 json.loads((b / 'metadata.json').read_text())['corpus_checksums'])
                with self.assertRaises(ValueError):
                    record.record(rep, Path(tmp) / 'b', 'r1', 'baseline', '')
                self.assertEqual(len((Path(tmp) / 'trends.csv').read_text().splitlines()), 3)
                self.assertIn('No comparable prior run', (Path(tmp) / 'latest.md').read_text())
            finally:
                record.PERF = old[0]


class ComparisonProvenance(unittest.TestCase):
    def setUp(self):
        self.metadata = dict(host='machine', architecture='x86_64', cpu='CPU', os='Linux',
                             compiler='ldc2', ldc='1.43', flags='-O3', backend='direct',
                             workloads_revision='revision', corpus_checksums={'case': 'digest'},
                             cpu_pinning='none', iterations_per_sample=2000, warmups=1,
                             sanitizers='none')

    def test_same_environment_is_comparable(self):
        self.assertTrue(record.comparable(self.metadata, dict(self.metadata)))

    def test_cross_host_backend_build_and_corpus_deltas_are_rejected(self):
        for key in self.metadata:
            other = dict(self.metadata)
            other[key] = {'case': 'different'} if key == 'corpus_checksums' else 'different'
            self.assertFalse(record.comparable(self.metadata, other), key)

    def test_unknown_flags_or_toolchain_are_not_proof(self):
        for key in ('flags', 'ldc'):
            other = dict(self.metadata, **{key: 'unknown'})
            self.assertFalse(record.comparable(other, dict(other)))

    def test_missing_historical_provenance_is_not_a_comparison(self):
        self.assertFalse(record.comparable({}, {}))
        for key in self.metadata:
            other = dict(self.metadata)
            del other[key]
            self.assertFalse(record.comparable(self.metadata, other), key)



if __name__ == '__main__':
    unittest.main()
