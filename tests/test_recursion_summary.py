"""Validate scaling report completeness before interpreting growth."""
import importlib.util
import io
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'recursion_summary', Path(__file__).resolve().parents[1] / 'scripts/summarize-recursion.py')
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class ScalingSummaryTests(unittest.TestCase):
    def corpus(self):
        lines = ['grammar,mode,valid,terms,sample,ns,requested_bytes']
        for grammar in ('LeftChain', 'IndirectChain'):
            for mode in ('validation', 'records', 'tree'):
                for valid in (0, 1):
                    for terms in (8, 16, 32, 64, 128, 256, 512):
                        for sample in range(7):
                            lines.append(f'{grammar},{mode},{valid},{terms},{sample},'
                                         f'{terms * terms + sample - 3},{terms * 32}')
        return lines

    def test_growth(self):
        rows = summary.summarize(io.StringIO('\n'.join(self.corpus())))
        self.assertEqual(len(rows), 84)
        self.assertEqual(rows[0][4:], (64, 256, '', ''))
        self.assertEqual(rows[1][6:], (4, 2))

    def test_missing_sample(self):
        with self.assertRaisesRegex(ValueError, 'incomplete samples'):
            summary.summarize(io.StringIO('\n'.join(self.corpus()[:-1])))

    def test_duplicate_sample(self):
        lines = self.corpus()
        lines[-1] = lines[-2]
        with self.assertRaisesRegex(ValueError, 'incomplete samples'):
            summary.summarize(io.StringIO('\n'.join(lines)))

    def test_missing_group(self):
        with self.assertRaisesRegex(ValueError, 'expected 84'):
            summary.summarize(io.StringIO('\n'.join(self.corpus()[:-7])))


if __name__ == '__main__':
    unittest.main()
