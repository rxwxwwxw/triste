#!/usr/bin/env python3
"""Verify C01/C02 and close C03 only when shared replay has no gate coverage."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify_sources(manifest):
    for name, digest in manifest['sourceHashes'].items():
        assert sha(name) == digest, f'Stale evidence: {name}'


def main():
    os.chdir(ROOT)
    eligibility = json.loads(Path('performance/phase3/B04-eligibility.json').read_text())
    verify_sources(eligibility)
    assert len(eligibility['summary']) == 6
    assert all(not row['leftRecursive'] for row in eligibility['summary'])
    gate = json.loads(Path('performance/phase3/B03-before-gate.json').read_text())
    rows = gate['ratios']
    assert len(rows) == 513
    changed = [name for name, digest in gate['metadata']['sourceHashes'].items()
               if name.startswith(('src/', 'benchmark/')) and sha(name) != digest]
    assert set(changed) == {'benchmark/diagnostics/shared_output.d',
                            'benchmark/p09_crossover.d', 'benchmark/p13_tuning.d',
                            'benchmark/diagnostics/pure_islands.d'}, changed
    build = Path('scripts/benchmark.sh').read_text()
    assert all(name not in build for name in changed)
    c01 = json.loads(Path('performance/phase3/C01/manifest.json').read_text())
    verify_sources(c01)
    assert len(c01['measurements']) == 72
    for measurement in c01['measurements']:
        prefix = Path('performance/phase3/C01') / measurement['name']
        assert sha(str(prefix) + '.csv') == measurement['csvSha256']
        assert sha(str(prefix) + '.tuples.txt') == measurement['tupleSha256']
    c02 = json.loads(Path('performance/phase3/C02/validation.json').read_text())
    verify_sources(c02)
    assert c02['decision'] == 'NO_GO_GENERAL_FINITE_ACTIVATION' and c02['status'] == 'PASS'
    c02_manifest = json.loads(Path('performance/phase3/C02/manifest.json').read_text())
    verify_sources(c02_manifest)
    for binary in c02_manifest['builds']:
        assert sha(Path('performance/phase3/C02') / (binary['name'] + '.csv')) == binary['transcriptSha256']
    counts = []
    for mode in ('validation', 'spans', 'tree'):
        group = [row for row in rows if row['output'] == mode]
        counts.append(dict(output=mode, observations=len(group),
                           aboveTarget=sum(row['ratio'] > 1.5 for row in group),
                           sharedEligible=0, activeSharedOperationsProvenAbsent=True))
    artifacts = ['performance/phase3/B04-eligibility.json', 'performance/phase3/B03-before-gate.json',
        'performance/phase3/C01/manifest.json', 'performance/phase3/C01/summary.json',
        'performance/phase3/C02/manifest.json', 'performance/phase3/C02/validation.json',
        'src/npegged/grammar.d', 'src/npegged/peg.d', 'scripts/c03_decision.py']
    result = dict(milestone='C03', disposition='DEFERRED_GATE_IRRELEVANT', conditionalBranchClosed=True,
        revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        objective='Shared-output optimization only if gate-relevant', productionChanges=False,
        gate=dict(dataset='B03-before-gate.json', targetRatio=1.5, observations=len(rows),
            aboveTarget=sum(row['ratio'] > 1.5 for row in rows),
            uniqueCaseOutputs=len({(row['name'], row['suite'], row['output']) for row in rows}),
            eligibleObservations=0, eligibleFailures=0, byOutput=counts),
        activationEvidence='Statically excluded by API/emitted eligibility; no new instrumented gate measurement',
        eligibility=eligibility['summary'], c02Decision=c02['decision'],
        amdahl=dict(affectedGateLatencyFraction=0, maximumGateLatencyReduction=0, maximumGateSpeedup=1.0),
        retainedPolicy='R06 opt-in; all trace/step/depth/memory/output guards and 4096-byte snapshot threshold unchanged',
        evidenceSha256={name: sha(name) for name in artifacts},
        provenanceNote='Core and timed gate adapters match the saved baseline. Four changed diagnostic benchmark files are not compiled by scripts/benchmark.sh; no new full gate is claimed.',
        conditionsForReopening=[
            'A maintained gate/workload with selected left-recursive output and measured nonzero shared operations',
            'A demonstrated remaining materialization cost in those gate failures',
            'Bounded semantics proven for any wider activation; otherwise preserve unlimited opt-in policy',
            'Matched oracle, budgets, ownership, parents, active timing and guarded controls'])
    Path('performance/phase3/C03-decision.json').write_text(json.dumps(result, indent=2) + '\n')
    print('C03 deferred: shared replay covers 0/513 gate observations and 0/424 saved failures')


if __name__ == '__main__':
    main()
