#!/usr/bin/env python3
"""G7 manifest checks: checksums, labels, size policy, and that large entries are not committed."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / 'performance/corpora/manifest.json').read_text())
COMMITTED_BUDGET = 256 * 1024


class CorpusManifest(unittest.TestCase):
    def test_committed_entries_match_checksums_and_budget(self):
        total = 0
        for entry in MANIFEST['generated']:
            path = ROOT / entry['path']
            if not entry['committed']:
                self.assertEqual(entry['class'], 'large')
                self.assertNotIn('performance/corpora', entry['path'])  # never inside the committed tree
                continue
            data = path.read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), entry['sha256'], entry['name'])
            self.assertEqual(len(data), entry['bytes'])
            total += len(data)
        self.assertLessEqual(total, COMMITTED_BUDGET)

    def test_labels_are_truthful(self):
        for entry in MANIFEST['generated']:
            self.assertIn(entry['label'], ('synthetic', 'adversarial'))
            if entry['label'] == 'synthetic':
                self.assertTrue(entry['provenance'].startswith('synthetic-'))
            self.assertTrue(entry['regenerate'])
        learned = [e for e in MANIFEST['generated'] if 'learned' in e['provenance']]
        self.assertTrue(learned and all('real-json' in e['provenance'] for e in learned))
        for entry in MANIFEST['real']:
            self.assertEqual(entry['label'], 'real')
            self.assertTrue(entry['license'] and entry['origin'])

    def test_real_corpus_checksums(self):
        for entry in MANIFEST['real']:
            data = (ROOT / entry['path']).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), entry['sha256'], entry['name'])

    def test_valid_and_invalid_mix_and_families(self):
        committed = [e for e in MANIFEST['generated'] if e['committed']]
        for family in ('json', 'arithmetic', 'csv'):
            kinds = {(e['class'], e['valid']) for e in committed if e['family'] == family}
            self.assertIn(('small', True), kinds)
            self.assertIn(('small', False), kinds)
            self.assertIn(('medium', True), kinds)
            self.assertIn(('adversarial', True), kinds)

    def test_a1_fixture_list_is_preserved(self):
        self.assertTrue(MANIFEST['corpora'])


if __name__ == '__main__':
    unittest.main()
