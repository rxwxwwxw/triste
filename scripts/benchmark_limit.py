"""Run the benchmark tree in a separate cgroup, or with an address-space cap."""
import os
import re
import resource
import shutil
import subprocess
import sys


def memory_bytes(value):
    match = re.fullmatch(r'([1-9][0-9]*)([KMGT]?)', value, re.IGNORECASE)
    if not match:
        raise ValueError('memory limit must be a positive integer with optional K/M/G/T suffix')
    return int(match[1]) * 1024 ** ('KMGT'.index(match[2].upper()) + 1 if match[2] else 0)


def main():
    limit = os.environ.get('MEMORY_LIMIT', '2G')
    try:
        size = memory_bytes(limit)
    except ValueError as error:
        sys.exit(str(error))
    command = sys.argv[1:]
    if not command:
        sys.exit('missing benchmark command')
    systemd = shutil.which('systemd-run')
    if systemd:
        try:
            probe = subprocess.run(
                [systemd, '--user', '--scope', '-q', 'true'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        except subprocess.TimeoutExpired:
            probe = None
        if probe is not None and probe.returncode == 0:
            os.execvp(systemd, [systemd, '--user', '--scope', '-q',
                               '-p', f'MemoryMax={size}', '-p', 'MemorySwapMax=0',
                               '--', *command])
    # This process is already a child of make/the shell. Its hard limit is
    # inherited by the compiler and runner, without changing the parent's limit.
    _, hard = resource.getrlimit(resource.RLIMIT_AS)
    if hard != resource.RLIM_INFINITY:
        size = min(size, hard)
    print(f'systemd unavailable; limiting benchmark address space to {size} bytes',
          file=sys.stderr)
    resource.setrlimit(resource.RLIMIT_AS, (size, size))
    os.execvp(command[0], command)


if __name__ == '__main__':
    main()
