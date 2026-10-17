#!/usr/bin/env python3
"""Capture the complete foundation baseline without treating a ratio failure as missing data."""
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    os.chdir(ROOT)
    destination = ROOT / 'performance/results/F01-baseline.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    command = [sys.executable, 'scripts/performance_gate.py', '--output', str(destination)]
    # Bound the entire child process tree, including each benchmark invocation.
    def bounded():
        resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))
    result = subprocess.run(['timeout', '--kill-after=5s', '1800s', *command],
                            preexec_fn=bounded, check=False)
    if not destination.exists():
        return result.returncode or 2
    report = json.loads(destination.read_text())
    hashes = report['metadata']['sourceHashes']
    if any(hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != digest
           for path, digest in hashes.items()):
        raise ValueError('Baseline source mismatch')
    if result.returncode != (0 if report['passed'] else 1):
        raise ValueError('Baseline runner failed independently of the ratio gate')
    manifest = dict(schemaVersion=1, command=command, timeoutSeconds=1800,
                    memoryLimitBytes=4 * 1024**3, platform=platform.platform(),
                    report=str(destination.relative_to(ROOT)),
                    reportSha256=hashlib.sha256(destination.read_bytes()).hexdigest(),
                    metadata=report['metadata'], pairedChecks=len(report['ratios']),
                    failedChecks=len(report['failures']), gatePassed=report['passed'])
    (ROOT / 'performance/baseline-manifest.json').write_text(
        json.dumps(manifest, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
