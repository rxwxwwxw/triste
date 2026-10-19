#!/usr/bin/env python3
"""A5: generated source size, generation time, native compile time, object size, peak RSS.

Usage: size_account.py OUTPUT.csv   (LDC only; DMD not run when unavailable)
Grammars: tiny, arithmetic (non-DFA), json (DFA-heavy), synthetic-large (200 rules).
Generation is run twice and the outputs hashed to verify determinism.
"""
import csv
import hashlib
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB = sorted(str(p) for p in (ROOT / 'src').rglob('*.d'))
FLAGS = ['-O3', '-release', '-boundscheck=off', '-defaultlib=druntime-ldc', '-fno-exceptions']


def grammar_from(path, name):
    text = (ROOT / path).read_text()
    start = text.index(f'enum {name}')
    start = text.index('`', start) + 1
    return text[start:text.index('`', start)]


def synthetic(rules=200):
    body = ['Big:', '    Root <- R0 eoi']
    for i in range(rules):
        nxt = f'R{i + 1}' if i + 1 < rules else "'z'"
        body.append(f"    R{i} <- 'a{i % 7}' {nxt} / [0-9]+ {nxt}" if i % 3 else f"    R{i} <~ [a-z]+ {nxt}")
    return '\n'.join(body) + '\n'


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=kw.pop('text', True), **kw)


def peak_rss(cmd):
    """Run cmd under /usr/bin/time; returns (result, seconds, peak RSS KiB or 'N/A')."""
    if sys.platform == 'darwin':
        wrapped, unit = ['/usr/bin/time', '-l', *cmd], 1024
    else:
        wrapped, unit = ['/usr/bin/time', '-v', *cmd], 1
    started = time.monotonic()
    result = subprocess.run(wrapped, capture_output=True, text=True)
    elapsed = time.monotonic() - started
    match = re.search(r'(\d+)\s+maximum resident set size', result.stderr) or re.search(
        r'Maximum resident set size \(kbytes\): (\d+)', result.stderr)
    rss = int(match.group(1)) // unit if match else 'N/A'
    return result, elapsed, rss


def main(out):
    grammars = {
        'tiny': "Tiny:\n    Root <- 'a'+ eoi\n",
        'arithmetic': grammar_from('benchmark/workload_grammars.d', 'arithmeticGrammar'),
        'json': grammar_from('benchmark/json_grammar.d', 'jsonGrammar'),
        'synthetic-large': synthetic(),
    }
    work = Path(tempfile.mkdtemp(prefix='a5-'))
    tool = work / 'gen_source'
    build = run(['ldc2', *FLAGS, '-O1', '-I' + str(ROOT / 'src'), *LIB,
                 str(ROOT / 'performance/scripts/gen_source.d'), f'-of={tool}'])
    if build.returncode:
        sys.exit(build.stderr)
    rows = []
    for name, text in grammars.items():
        gfile = work / f'{name}.txt'
        gfile.write_text(text)
        runs = []
        for _ in range(2):
            started = time.monotonic()
            gen = subprocess.run([str(tool), str(gfile)], capture_output=True)
            runs.append((time.monotonic() - started, gen))
        a, b = runs[0][1], runs[1][1]
        if a.returncode:
            sys.exit(f'generation failed for {name}')
        deterministic = hashlib.sha256(a.stdout).hexdigest() == hashlib.sha256(b.stdout).hexdigest()
        unit = work / f'{name}_unit.d'
        unit.write_text(f'module unit;\nimport npegged.grammar;\n'
                        f'struct P {{ mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(import("{name}.txt"))); }}\n')
        obj = work / f'{name}.o'
        result, seconds, rss = peak_rss(['ldc2', *FLAGS, '-c', f'-J{work}', '-I' + str(ROOT / 'src'),
                                         str(unit), f'-of={obj}'])
        compiled = result.returncode == 0
        rows.append(dict(grammar=name, grammar_bytes=len(text.encode()), generated_source_bytes=len(a.stdout),
                         generated_source_lines=a.stdout.count(b'\n'),
                         generation_seconds=f'{min(r[0] for r in runs):.4f}',
                         compile_seconds=f'{seconds:.2f}' if compiled else 'FAILED',
                         object_bytes=obj.stat().st_size if compiled else 'N/A',
                         peak_rss_kib=rss if compiled else 'N/A',
                         dfa_regions=len(re.findall(rb'struct _dfa_', a.stdout)),
                         deterministic=str(deterministic).lower(), compiler='ldc2'))
    with open(out, 'w', newline='') as handle:
        writer = csv.DictWriter(handle, list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    for row in rows:
        print(row)


if __name__ == '__main__':
    main(sys.argv[1])
