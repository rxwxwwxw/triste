#!/usr/bin/env python3
"""Q1's bounded cross-module check; build executable before invoking."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]

class EntryLadderIntegration(unittest.TestCase):
    def test_observations_and_negative_controls(self):
        result = subprocess.run(
            ['prlimit', '--as=4294967296', 'timeout', '--kill-after=2s', '60s',
             'build/Q1/tests', '--DRT-testmode=test-only'],
            cwd=ROOT, capture_output=True, text=True, timeout=65)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('passed unittests', result.stdout + result.stderr)

if __name__ == '__main__':
    unittest.main()
