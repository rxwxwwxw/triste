#!/usr/bin/env python3
"""Exercise installer idempotency, hook chaining, and staged snapshot isolation."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent

def run(directory, *args, check=True):
    return subprocess.run(args, cwd=directory, check=check, capture_output=True, text=True)

with tempfile.TemporaryDirectory(prefix='npegged-hooks-') as temporary:
    checkout = Path(temporary)
    (checkout / 'scripts').mkdir()
    (checkout / 'hooks').mkdir()
    shutil.copy2(root / 'scripts/install-hooks.sh', checkout / 'scripts')
    shutil.copy2(root / 'hooks/pre-commit', checkout / 'hooks')
    run(checkout, 'git', 'init', '-q')
    previous = checkout / '.git/hooks/pre-commit'
    previous.write_text('#!/bin/sh\nprintf "chained\\n"\n')
    previous.chmod(0o755)
    run(checkout, 'bash', 'scripts/install-hooks.sh')
    run(checkout, 'bash', 'scripts/install-hooks.sh')
    assert os.access(previous, os.X_OK)
    assert previous.with_name('pre-commit.previous').read_text().endswith('printf "chained\\n"\n')
    (checkout / 'scripts/validate.sh').write_text('#!/bin/sh\nset -eu\ntest "$(cat staged.txt)" = staged\ntest ! -e unstaged.txt\n')
    (checkout / 'staged.txt').write_text('staged')
    run(checkout, 'git', 'add', 'scripts', 'hooks', 'staged.txt')
    (checkout / 'staged.txt').write_text('unstaged')
    (checkout / 'unstaged.txt').write_text('untracked')
    output = run(checkout, 'bash', '.git/hooks/pre-commit')
    assert 'chained' in output.stdout
    run(checkout, 'git', 'config', 'core.hooksPath', 'custom-hooks')
    rejected = run(checkout, 'bash', 'scripts/install-hooks.sh', check=False)
    assert rejected.returncode != 0 and 'core.hooksPath' in rejected.stderr
print('Hook installation, chaining, and staged snapshot tests passed.')
