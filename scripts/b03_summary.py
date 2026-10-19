#!/usr/bin/env python3
"""Summarize the B03 paired experiment without reclassifying noisy gate failures."""
import itertools
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]


def main():
    raw = json.loads((ROOT / 'performance/phase3/B03-interleaved.json').read_text())
    baseline = json.loads((ROOT / 'performance/phase3/B03-before-gate.json').read_text())
    failed = {(r['suite'], r['output'], r['name']) for r in baseline['ratios']
              if r['ratio'] > 1.5}
    observations = {}
    for measurement in raw['measurements']:
        for row in measurement['report']['benchmarks']:
            key = (measurement['suite'], measurement['output'], row['name'], row['engine'])
            observations.setdefault(key, {}).setdefault(measurement['run'], {})[
                measurement['policy']] = row
    cases = []
    for key, runs in sorted(observations.items()):
        changes = [r['after']['meanMs'] / r['before']['meanMs'] for _, r in sorted(runs.items())]
        # Exhaustive bootstrap of five paired run ratios; uncertainty is across
        # invocation batches, not 35 falsely independent inner timing samples.
        boot = sorted(statistics.median(sample) for sample in itertools.product(changes, repeat=5))
        lower, upper = boot[int(.025 * len(boot))], boot[int(.975 * len(boot))]
        cases.append(dict(suite=key[0], output=key[1], name=key[2], engine=key[3],
                          failedBefore=key[:3] in failed, afterOverBefore=changes,
                          median=statistics.median(changes), bootstrap95=[lower, upper],
                          improved=upper < 1 and statistics.median(changes) < .97,
                          regressed=lower > 1 and statistics.median(changes) > 1.03))
    groups = {}
    for engine in ('NPegged', 'Handwritten'):
        for mode in ('validation', 'spans', 'tree'):
            group = [r for r in cases if r['engine'] == engine and r['output'] == mode]
            groups[f'{engine}/{mode}'] = dict(cases=len(group), improved=sum(r['improved'] for r in group),
                regressed=sum(r['regressed'] for r in group),
                medianAfterOverBefore=statistics.median(r['median'] for r in group))
    result = dict(schemaVersion=1, milestone='B03',
                  interpretation='Ratios below one favor candidate; bootstrap intervals are exploratory and unadjusted for multiple comparisons. Improved/regressed requires entire interval beyond one and median change exceeding 3%.',
                  groups=groups, cases=cases)
    (ROOT / 'performance/phase3/B03-summary.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(groups, indent=2))


if __name__ == '__main__':
    main()
