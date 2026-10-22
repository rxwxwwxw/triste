"""Benchmark limits must constrain children without changing the test runner."""
import importlib.util
import os
from pathlib import Path
import resource
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/benchmark_limit.py'
spec = importlib.util.spec_from_file_location('benchmark_limit', SCRIPT)
limiter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(limiter)


class BenchmarkLimitTests(unittest.TestCase):
    def test_memory_sizes(self):
        for text, expected in [('1', 1), ('64K', 65536), ('128m', 128 * 1024**2),
                               ('2G', 2 * 1024**3), ('1T', 1024**4)]:
            self.assertEqual(limiter.memory_bytes(text), expected)
        for text in ('0', '-1', '2GB', 'unlimited', '2.5G', ''):
            with self.assertRaises(ValueError):
                limiter.memory_bytes(text)

    def test_systemd_limits_entire_child_tree(self):
        with patch.dict(os.environ, {'MEMORY_LIMIT': '2G'}), \
                patch.object(sys, 'argv', ['benchmark_limit.py', '/bin/true']), \
                patch.object(limiter.shutil, 'which', return_value='/usr/bin/systemd-run'), \
                patch.object(limiter.subprocess, 'run') as probe, \
                patch.object(limiter.os, 'execvp', side_effect=SystemExit) as execute, \
                patch.object(limiter.resource, 'setrlimit') as setlimit:
            probe.return_value.returncode = 0
            with self.assertRaises(SystemExit):
                limiter.main()
            args = execute.call_args.args[1]
            self.assertIn('MemoryMax=2147483648', args)
            self.assertIn('MemorySwapMax=0', args)
            self.assertEqual(args[-2:], ['--', '/bin/true'])
            setlimit.assert_not_called()

    def test_fallback_limits_child_and_preserves_parent(self):
        before = resource.getrlimit(resource.RLIMIT_AS)
        environment = dict(os.environ, PATH='', MEMORY_LIMIT='128M')
        code = """
import resource
assert resource.getrlimit(resource.RLIMIT_AS) == (134217728, 134217728)
try:
    bytearray(256 * 1024**2)
except MemoryError:
    pass
else:
    raise AssertionError('allocation escaped limit')
"""
        result = subprocess.run([sys.executable, str(SCRIPT), sys.executable, '-c', code],
                                env=environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(resource.getrlimit(resource.RLIMIT_AS), before)


if __name__ == '__main__':
    unittest.main()
