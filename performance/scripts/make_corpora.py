#!/usr/bin/env python3
"""G7: regenerate the benchmark corpora and their manifest.

Builds performance/scripts/make_corpora.d with LDC, runs it, and writes
  performance/corpora/synthetic/<family>/*.txt   small, medium and adversarial entries (committed)
  build/corpora-large/*.txt                      large entries (NOT committed; checksum recorded, regenerate with this script)
  performance/corpora/manifest.json              keeps the A1 `corpora` list; adds `generated` and `real`
Everything is a pure function of the repository sources, the seeds and the real corpus snapshot.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parents[2]
SYNTHETIC = ROOT / 'performance/corpora/synthetic'
LARGE = ROOT / 'build/corpora-large'
COMMITTED_CLASSES = {'small', 'medium', 'adversarial'}
BUDGET_COMMITTED_BYTES = 256 * 1024


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_tool(out):
    sources = sorted(str(p) for p in (ROOT / 'src').rglob('*.d'))
    command = ['ldc2', '-O1', '-I.', '-Isrc', '-Iperformance/scripts', '-defaultlib=druntime-ldc', *sources,
               'performance/scripts/corpus_lib.d', 'performance/scripts/make_corpora.d',
               'benchmark/json_grammar.d', 'benchmark/json_output.d', 'benchmark/workload_grammars.d',
               *sorted(str(p) for p in (ROOT / 'benchmark/handwritten').glob('*.d')), f'-of={out}']
    subprocess.run(command, cwd=ROOT, check=True)


def main():
    tool = ROOT / 'build/make_corpora'
    scratch = ROOT / 'build/corpora-scratch'
    scratch.mkdir(parents=True, exist_ok=True)
    LARGE.mkdir(parents=True, exist_ok=True)
    build_tool(tool)
    for old in scratch.glob('*.txt'):
        old.unlink()
    described = json.loads(subprocess.run([str(tool), str(scratch)], cwd=ROOT, check=True, capture_output=True,
                                          text=True).stdout)
    generated, committed_bytes = [], 0
    for entry in described:
        source = scratch / f"{entry['name']}.txt"
        data = source.read_bytes()
        assert len(data) == entry['bytes']
        committed = entry['class'] in COMMITTED_CLASSES
        if committed:
            target_dir = SYNTHETIC / entry['family']
            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / source.name
            committed_bytes += len(data)
        else:
            target = LARGE / source.name
        target.write_bytes(data)
        generated.append(dict(entry, label='synthetic' if entry['class'] != 'adversarial' else 'adversarial',
                              sha256=hashlib.sha256(data).hexdigest(), committed=committed,
                              path=str(target.relative_to(ROOT)),
                              regenerate='python3 performance/scripts/make_corpora.py'))
    if committed_bytes > BUDGET_COMMITTED_BYTES:
        sys.exit(f'committed corpus size {committed_bytes} exceeds the budget {BUDGET_COMMITTED_BYTES}')
    real_dir = ROOT / 'performance/corpora/real/json'
    real = []
    for name in (real_dir / 'INDEX.txt').read_text().split():
        path = real_dir / name
        real.append(dict(name=name, family='json', label='real', bytes=path.stat().st_size, sha256=sha256(path),
                         path=str(path.relative_to(ROOT)),
                         origin="this repository's own recorded benchmark metadata, workload registry and test fixtures",
                         license='same as the repository (see LICENSE); no personal data beyond host descriptions'))
    manifest_path = ROOT / 'performance/corpora/manifest.json'
    manifest = json.loads(manifest_path.read_text())
    manifest.update(schema=2, generated=generated, real=real,
                    notes='labels: real | synthetic (default or learned weights, see provenance) | adversarial; '
                          'large entries are not committed: regenerate and compare sha256; '
                          f'committed synthetic budget {BUDGET_COMMITTED_BYTES} bytes')
    manifest_path.write_text(json.dumps(manifest, indent=1) + '\n')
    import corpus_index
    corpus_index.main()
    print(f'{len(generated)} generated entries ({committed_bytes} bytes committed), {len(real)} real files')


if __name__ == '__main__':
    main()
