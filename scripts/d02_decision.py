#!/usr/bin/env python3
"""D02 source-verified deployment decision and documentation/legacy checks."""
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'performance/phase3/D02'
BUILD=ROOT/'build/D02'


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def bounded(): resource.setrlimit(resource.RLIMIT_AS,(4*1024**3,4*1024**3))


def main():
    os.chdir(ROOT);DEST.mkdir(parents=True,exist_ok=True);BUILD.mkdir(parents=True,exist_ok=True)
    manifest=json.loads(Path('performance/phase3/D01/manifest.json').read_text())
    validation=json.loads(Path('performance/phase3/D01/validation.json').read_text())
    for group in [manifest,validation]:
        for name,digest in group['sourceHashes'].items(): assert sha(Path(name))==digest,name
    assert validation['status']=='PASS'
    for row in manifest['measurements']:
        assert sha(Path('performance/phase3/D01')/(row['name']+'.csv'))==row['csvSha256']
    summary=json.loads(Path('performance/phase3/D01/summary.json').read_text())
    assert summary['activeCases']==132 and summary['defaultPolicyEligibleFraction']==0
    assert all(r['entries']==0 for r in summary['comparisons'] if r['guarded'])
    text=Path('docs/PURE_ISLAND_POLICY.md').read_text()
    sample=re.findall(r'```d\n(.*?)```',text,re.S);assert len(sample)==1
    source=BUILD/'usage.d';source.write_text(sample[0]);subprocess.run(['dfmt','-i',str(source)],check=True)
    sources=sorted(Path('src').rglob('*.d'))
    checked=[Path('docs/PURE_ISLAND_POLICY.md'),Path('tests/pure_islands_budget.d'),Path('tests/pure_islands_audit.d'),Path('tests/pure_islands_perf.d'),Path(__file__).relative_to(ROOT),*sources]
    pins={str(p):sha(p) for p in checked}
    builds=[]
    for compiler in ['dmd','ldc2']:
        compiler_version=subprocess.check_output([compiler,'--version'],text=True)
        for fixture in [source,Path('tests/pure_islands_budget.d'),Path('tests/pure_islands_audit.d'),Path('tests/pure_islands_perf.d')]:
            name=f'{compiler}-{fixture.stem}';binary=BUILD/name
            flags=['-Isrc','-w','-de','-checkaction=halt']
            if compiler=='dmd':flags+=['-defaultlib=druntime','-nothrow','-version=NPeggedPureIslands','-version=NPeggedMetrics']
            else:flags+=['-defaultlib=druntime-ldc','-fno-exceptions','-d-version=NPeggedPureIslands','-d-version=NPeggedMetrics']
            command=[compiler,*flags,*map(str,sources),str(fixture),f'-of={binary}']
            result=subprocess.run(command,capture_output=True,text=True,timeout=300,preexec_fn=bounded)
            (DEST/(name+'.build.log')).write_text(result.stdout+result.stderr);result.check_returncode()
            result=subprocess.run([str(binary)],capture_output=True,text=True,timeout=45,preexec_fn=bounded)
            path=DEST/(name+'.txt');path.write_text(result.stdout)
            (DEST/(name+'.log')).write_text(result.stderr);result.check_returncode();assert not result.stderr
            if fixture==source:assert result.stdout=='pure-island specialized mode passed\n'
            builds.append(dict(name=name,command=command,compilerVersion=compiler_version,outputSha256=sha(path),binarySha256=sha(binary)))
            print(name,'passed',flush=True)
    assert all(sha(Path(p))==h for p,h in pins.items())
    Path('performance/phase3/D02-decision.json').write_text(json.dumps(dict(milestone='D02',
        disposition='KEEP_SPECIALIZED_OPT_IN',broaderPolicy='NO_GO',finiteBudgetVariant='Not established; reference-equivalent accounting required before a separate proposal',
        productionChanges=False,defaultPolicyEligibleFraction=0,activeLabConfigurations=132,
        finiteUntracedConfigurations=234,tracedConfigurations=486,sourceHashes=pins,builds=builds,
        d01EvidenceSha256={str(p):sha(p) for p in [Path('performance/phase3/D01/manifest.json'),Path('performance/phase3/D01/summary.json'),Path('performance/phase3/D01/validation.json')]},
        timeoutSeconds=45,memoryLimitBytes=4*1024**3,
        legacyClockScope='Legacy perf output retained as diagnostics only; no timing conclusions use these single-batch values',
        modeContract='docs/PURE_ISLAND_POLICY.md'),indent=2)+'\n')


if __name__=='__main__':main()
