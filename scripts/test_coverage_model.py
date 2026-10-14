#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path
from coverage_model import read_cfg, source_edges, unittest_lines

class CoverageTests(unittest.TestCase):
    def test_contracts_and_template_merging(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'sample.cfg'
            path.write_text(''';; Function check (check, funcdef_no=1)
  <bb 2> :
  [sample.d:10:8] if (value < limit)
    goto <bb 3>;
  else
    goto <bb 4>;
  <bb 3> :
  [sample.d:10:8] __builtin_trap ();
  <bb 4> :
  [sample.d:11:8] if (success)
    goto <bb 5>;
  else
    goto <bb 6>;
  <bb 5> :
  return 0;
  <bb 6> :
  return 1;
''')
            cfg = read_cfg([path])
            line = {'line_number': 11, 'function_name': 'check', 'branches': [
                {'source_block_id': 2, 'destination_block_id': 3, 'count': 0},
                {'source_block_id': 2, 'destination_block_id': 4, 'count': 1},
                {'source_block_id': 4, 'destination_block_id': 5, 'count': 1},
                {'source_block_id': 4, 'destination_block_id': 6, 'count': 0}]}
            edges = source_edges({'lines': [line]}, cfg, set())
            self.assertEqual(len(edges), 2)
            self.assertEqual(sum(edges.values()), 1)
            other = dict(line)
            other['branches'] = [dict(item, count=1) for item in line['branches']]
            merged = source_edges({'lines': [line, other]}, cfg, set())
            self.assertEqual(sum(merged.values()), 2)
            self.assertEqual(source_edges({'lines': [line]}, cfg, {11}), {})

    def test_unseen_edges_are_not_excluded(self):
        edges = source_edges({'lines': [{'line_number': 1, 'branches': [{'count': 0}, {'count': 1}]}]}, {}, set())
        self.assertEqual(len(edges), 2)
        self.assertEqual(sum(edges.values()), 1)

    def test_test_code_ranges(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source.d'
            path.write_text('void run() {}\n@nogc nothrow unittest {\n    assert(true);\n}\nvoid after() {}\n')
            self.assertEqual(unittest_lines(path), {2, 3, 4})

if __name__ == '__main__': unittest.main()
