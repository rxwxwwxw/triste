#!/usr/bin/env python3
"""Audit actual gate grammar memo/recursion policy without changing parser code."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    grammars = []
    for filename, symbols in [
        ('benchmark/workload_grammars.d', ['arithmeticGrammar', 'csvGrammar', 'numbersGrammar', 'pegGrammar']),
        ('benchmark/json_grammar.d', ['jsonGrammar']),
        ('benchmark/ambiguous_npegged.d', ['ambiguousGrammar']),
    ]:
        text = (ROOT / filename).read_text()
        for symbol in symbols:
            match = re.search(r'enum ' + symbol + r' = `([^`]*)`;', text)
            assert match, (filename, symbol)
            grammars.append(dict(file=filename, symbol=symbol, definition=match[1]))
    directory = ROOT / 'build/B04'
    directory.mkdir(parents=True, exist_ok=True)
    source = directory / 'eligibility.d'
    source.write_text('''module b04_eligibility;
import npegged.grammar;
import core.stdc.stdio : printf;
int main() nothrow {
    immutable string[] definitions = [
''' + ',\n'.join(json.dumps(g['definition']) for g in grammars) + '''
    ];
    printf("[");
    foreach (i, definition; definitions) {
        auto result = eligibilityReport!(Memoization.selective)(definition);
        if (result.status != Status.ok) return 2;
        if (i) printf(",");
        printf("%.*s", cast(int)result.report.length, result.report.ptr);
    }
    printf("]\\n");
    return 0;
}
''')
    subprocess.run(['dfmt', '-i', str(source)], check=True)
    sources = sorted((ROOT / 'src').rglob('*.d'))
    binary = directory / 'eligibility'
    command = ['ldc2', '-Isrc', '-defaultlib=druntime-ldc', '-fno-exceptions', '-w',
               *map(str, sources), str(source), f'-of={binary}']
    subprocess.run(['prlimit', '--as=4294967296', '--', 'timeout', '--kill-after=2s', '300s',
                    *command], cwd=ROOT, check=True, timeout=305)
    result = subprocess.run(['prlimit', '--as=4294967296', '--', 'timeout', '--kill-after=2s',
                             '60s', str(binary)], capture_output=True, text=True, check=True,
                            timeout=65)
    reports = json.loads(result.stdout)
    assert len(reports) == len(grammars)
    summary = [dict(grammar=r['grammar'], rules=len(r['rules']),
                    memoized=[rule['name'] for rule in r['rules'] if rule['memoized']],
                    leftRecursive=[rule['name'] for rule in r['rules'] if rule['leftRecursive']],
                    conservative=r['conservative']) for r in reports]
    output = ROOT / 'performance/phase3/B04-eligibility.json'
    output.write_text(json.dumps(dict(milestone='B04', command=command, grammars=grammars,
        generatedSource=source.read_text(), summary=summary, reports=reports,
        sourceHashes={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in [*sources, *(ROOT / g['file'] for g in grammars)]}), indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
