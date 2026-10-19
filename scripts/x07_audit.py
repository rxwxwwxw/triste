#!/usr/bin/env python3
"""X07 exact comparator and applicability audit; reject performance on unequal output."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'performance/phase3/X07'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    os.chdir(ROOT);DEST.mkdir(parents=True,exist_ok=True)
    sources=sorted(Path('src').rglob('*.d'))+[Path('tests/test_recursive_ascent.d'),Path('scripts/recursive-ascent-check.sh'),Path(__file__).relative_to(ROOT),Path('benchmark/workload_grammars.d'),Path('benchmark/workload_output.d')]
    pins={str(p):sha(p) for p in sources}
    command=['bash','scripts/recursive-ascent-check.sh']
    result=subprocess.run(command,capture_output=True,text=True,timeout=720,env=dict(os.environ,COMPILERS="dmd ldc2"))
    (DEST/'runner.log').write_text(result.stdout+result.stderr);result.check_returncode()
    reports=[]
    for compiler in ('dmd','ldc2'):
        raw=Path(f'build/X03/{compiler}.txt').read_text();(DEST/f'{compiler}.txt').write_text(raw)
        lines=raw.splitlines();assert lines[-1]=='recursive ascent oracle passed'
        data=json.loads('\n'.join(lines[:-1]));assert data['comparisonCount']==273
        assert {r['repeat'] for r in data['cases']}==set(range(1,8))
        assert data['generalEquivalent'] is False and data['completeParityFailures']>0
        compiler_command=json.loads(Path(f'build/X03/{compiler}.command.json').read_text())
        reports.append(dict(compiler=compiler,command=compiler_command,compilerVersion=subprocess.check_output([compiler,'--version'],text=True),
            binarySha256=sha(Path(f'build/X03/{compiler}.runner')),outputSha256=sha(DEST/f'{compiler}.txt'),
            cases=data['comparisonCount'],completeParityFailures=data['completeParityFailures'],
            topStatusDifferences=sum(r['reference'][0]!=r['candidate'][0] for r in data['cases'])))
    assert (DEST/'dmd.txt').read_bytes()==(DEST/'ldc2.txt').read_bytes()
    data=json.loads('\n'.join((DEST/'ldc2.txt').read_text().splitlines()[:-1]))
    by_family={family:dict(cases=sum(r['family']==family for r in data['cases']),
        completeParityFailures=sum(r['family']==family and not r['completeEqual'] for r in data['cases']),
        statusDifferences=sum(r['family']==family and r['reference'][0]!=r['candidate'][0] for r in data['cases']))
        for family in sorted({r['family'] for r in data['cases']})}
    assert all(sha(Path(p))==h for p,h in pins.items())
    result=dict(milestone='X07',disposition='NO_PROMOTION_SPECIALIZED_MANUAL_ONLY',productionParserChanges=False,
        sourceHashes=pins,command=command,timeoutSeconds=60,memoryLimitBytes=4294967296,
        repetitions=7,comparisonCountPerCompiler=273,builds=reports,byFamily=by_family,
        performanceDisposition='NOT_RUN: exact full-tree oracle fails; no equal-output latency claim is valid',
        gateApplicability='Arithmetic gate tree mode uses compact concrete-rule intervals with iterative Term/Factor; manual nested Expr ParseTree is a different output contract',
        scope='Complete tree compares name,input,status,span,matches,failEnd,children and failedChild; all public resource errors checked through parse result status')
    Path('performance/phase3/X07-decision.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(by_family,indent=2))


if __name__=='__main__':main()
