"""Reject incomplete focused measurements before reporting percentages."""
import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'peg_probe_summary', Path(__file__).resolve().parents[1] / 'scripts/summarize-peg-probe.py')
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class ProbeSummaryTests(unittest.TestCase):
    def cohort(self, root):
        paths = []
        for run in range(3):
            path = root / f'{run}.csv'
            with path.open('w') as stream:
                writer = csv.writer(stream)
                writer.writerow(('case', 'cohort', 'sample', 'iterations', 'total_ns'))
                for case in summary.CASES:
                    for cohort in ('end-to-end', 'stages'):
                        for sample in range(7):
                            writer.writerow((case, cohort, sample, 2000, 100))
            paths.append(path)
        return paths

    def test_complete_and_missing_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = self.cohort(Path(directory))
            groups = summary.measurements(paths)
            self.assertTrue(all(len(rows) == 21 for rows in groups.values()))
            with self.assertRaisesRegex(ValueError, 'three independent'):
                summary.measurements(paths[:2])

    def test_missing_and_duplicate_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = self.cohort(Path(directory))
            lines = paths[0].read_text().splitlines()
            paths[0].write_text('\n'.join(lines[:-1]))
            with self.assertRaisesRegex(ValueError, 'incomplete or duplicate'):
                summary.measurements(paths)
            lines[-1] = lines[-2]
            paths[0].write_text('\n'.join(lines))
            with self.assertRaisesRegex(ValueError, 'incomplete or duplicate'):
                summary.measurements(paths)

    def test_assembly_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'probe.asm'
            path.write_text('0000000000000010 <benchmark.diagnostics.peg_probe.BenchPEG._Sp!(false, 1)(ref npegged.peg.State!(false, 1).State)>:\n'
                            '  10:\te8 00 00 00 00\tcall 20 <target>\n'
                            '  15:\t75 02\tjne 19 <branch>\n'
                            '  17:\teb 00\tjmp 19 <branch>\n')
            evidence = summary.assembly_evidence(path)
            item = next(iter(evidence['functions'].values()))
            self.assertEqual((item['calls'], item['conditionalBranches'], item['instructions']), (1, 1, 3))


if __name__ == '__main__':
    unittest.main()
