#!/usr/bin/env python3
"""Reproduce S3 A5 accounting with scoped input ownership and bounded commands."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[4]
os.chdir(ROOT)
sys.path.insert(0, str(ROOT / 'performance/scripts'))
import size_account as accounting

HERE = Path(__file__).resolve().parent
records = []
feature = 'default'

def bounded_run(command, **kwargs):
    old = str(ROOT / 'performance/scripts/gen_source.d')
    source = str(HERE / 'gen_source_scoped.d')
    command = [source if str(arg) == old else str(arg) for arg in command]
    actual = ['prlimit', '--as=4294967296', 'timeout', '--kill-after=2s', '300s', *command]
    started = time.monotonic()
    result = subprocess.run(actual, **kwargs)
    elapsed = time.monotonic() - started
    output = result.stdout or b''
    if isinstance(output, str):
        output = output.encode()
    error = result.stderr or ''
    if isinstance(error, bytes):
        error = error.decode(errors='replace')
    records.append(dict(feature=feature, command=actual, elapsed_seconds=elapsed,
                        returncode=result.returncode, stdout_bytes=len(output),
                        stdout_sha256=hashlib.sha256(output).hexdigest(), stderr=error))
    return result

def measure_native(command):
    # wait4 returns this child's usage, including its waited descendants, so
    # earlier generator builds cannot contaminate a later compiler's peak RSS.
    limit = 17179869184 if any(str(arg).endswith('synthetic-large_unit.d') for arg in command) else 4294967296
    actual = ['prlimit', '--core=0', '--as=' + str(limit), 'timeout', '--kill-after=2s', '300s', *command]
    started = time.monotonic()
    with tempfile.TemporaryFile(mode='w+') as output, tempfile.TemporaryFile(mode='w+') as error:
        with subprocess.Popen(actual, stdout=output, stderr=error, text=True) as child:
            _, status, usage = os.wait4(child.pid, 0)
            child.returncode = os.waitstatus_to_exitcode(status)
            code = child.returncode
        output.seek(0)
        error.seek(0)
        result = subprocess.CompletedProcess(actual, code, output.read(), error.read())
    elapsed = time.monotonic() - started
    rss = usage.ru_maxrss // 1024 if sys.platform == 'darwin' else usage.ru_maxrss
    records.append(dict(feature=feature, command=actual, elapsed_seconds=elapsed,
                        returncode=code, stdout_bytes=len(result.stdout.encode()),
                        stdout_sha256=hashlib.sha256(result.stdout.encode()).hexdigest(),
                        stderr=result.stderr, peak_rss_kib=rss))
    return result, elapsed, rss

accounting.peak_rss = measure_native

accounting.subprocess = SimpleNamespace(run=bounded_run)
base_flags = [*accounting.FLAGS, '-w', '-checkaction=halt']
try:
    for feature in ('default', 'lean'):
        accounting.FLAGS = [*base_flags, *(['-d-version=NPeggedLeanEntry'] if feature == 'lean' else [])]
        accounting.main(str(HERE / (feature + '.csv')))
finally:
    metadata = dict(host=platform.uname()._asdict(),
        compiler=subprocess.check_output(['ldc2', '--version'], text=True),
        git_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        git_dirty=True, sanitizer=False, instrumentation=False,
        comparison='same current production source, compiler, grammar and flags; only NPeggedLeanEntry differs',
        limitations='Two generation samples for determinism, one native compilation per grammar/feature. Retain all commands and wall times; compile timing is not a reproducible speed claim. Full coverage collection may be active.',
        supplementary_source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__).resolve(), HERE / 'gen_source_scoped.d')},
        input_sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in sorted((ROOT / 'src').rglob('*.d'))},
        runs=records)
    (HERE / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
