#!/usr/bin/env python3
"""R06 source-pinned bounded reference/control/shared-output cohorts."""
from concurrent.futures import ThreadPoolExecutor
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import time
import statistics
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
MEMORY=4*1024**3

def compile_bounded(command):
    start=time.monotonic()
    subprocess.run(['prlimit',f'--as={MEMORY}','--','timeout','--kill-after=2s','300s',*command],check=True,timeout=305)
    return time.monotonic()-start

def main():
    os.chdir(ROOT)
    destination=Path(sys.argv[1] if len(sys.argv)>1 else 'build/R06-scaling').resolve()
    destination.mkdir(parents=True,exist_ok=True)
    quick='--quick' in sys.argv
    imports=Path('build/R06/imports/npegged')
    imports.mkdir(parents=True,exist_ok=True)
    link=imports/'examples'
    if not link.exists(): link.symlink_to(ROOT/'examples',target_is_directory=True)
    assert link.resolve()==ROOT/'examples'
    sources=sorted(Path('src').rglob('*.d'))+[Path(p) for p in ('examples/json.d','examples/csv.d','examples/PEG.d','benchmark/measurement.d','benchmark/diagnostics/shared_output.d')]
    pins={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[Path(__file__).relative_to(ROOT)]}
    signatures={}
    memory_signatures={}
    summaries=[]
    jobs=[]
    for backend in (('combinators',) if quick else ('combinators','direct')):
      for memo in (('selective',) if quick else ('selective','full')):
       for selector in (('all',) if quick else ('all','root')):
        for diagnostic in (False,True):
         for policy in ('reference','control','candidate'):
            prefix=destination/f'{backend}-{memo}-{selector}-{policy}-{"metrics" if diagnostic else "timing"}'
            binary=destination/f'{backend}-{memo}-{selector}-{"reference" if policy=="reference" else "compiled"}-{"metrics" if diagnostic else "timing"}.runner'
            flags=['-Isrc','-I.','-Ibuild/R06/imports','-defaultlib=druntime-ldc','-fno-exceptions','-O3','-release','-w','-de','-checkaction=halt']
            if backend=='direct': flags+=['-d-version=NPeggedDirect']
            if memo=='full': flags+=['-d-version=NPeggedFullMemo']
            if selector=='root': flags+=['-d-version=RootOnly']
            if diagnostic: flags+=['-d-version=NPeggedMetrics']
            if policy!='reference': flags+=['-d-version=NPeggedSharedOutput']
            command=['ldc2',*flags,*map(str,sources),f'-of={binary}']
            jobs.append((backend,memo,selector,diagnostic,policy,prefix,binary,command))
    # Independent compilations can overlap; all timed runs start after this barrier.
    def verify_sources():
        for path,digest in pins.items():
            assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,('source changed',path)
    def build(command):
        verify_sources()
        seconds=compile_bounded(command)
        verify_sources()
        return seconds
    unique_commands={str(job[-2]):job[-1] for job in jobs}
    with ThreadPoolExecutor(max_workers=2) as workers:
        durations=list(workers.map(build,unique_commands.values()))
    compile_seconds=dict(zip(unique_commands,durations))
    compiler=subprocess.check_output(['ldc2','--version'],text=True)
    for job in jobs:
            backend,memo,selector,diagnostic,policy,prefix,binary,command=job
            seconds=compile_seconds[str(binary)]
            run_environment={"NPEGGED_SHARED_OUTPUT":"1" if policy=="candidate" else "0"}
            binary_hash=hashlib.sha256(binary.read_bytes()).hexdigest()
            verify_sources()
            by_case={}
            raw_hashes={}
            for run in range(1,2 if diagnostic else 4):
                path=Path(f'{prefix}-run{run}.csv')
                with path.open('w') as output:
                    subprocess.run(['prlimit',f'--as={MEMORY}','--','timeout','--kill-after=2s','60s',str(binary)],stdout=output,check=True,timeout=65,env={**os.environ,**run_environment})
                with path.open() as source: rows=list(csv.DictReader(source))
                expected={(g,'flat',str(n),str(v),str(s)) for g in ('DirectChain','IndirectChain') for n in (16,32,64,128,256,512,1024,2048) for v in (0,1) for s in range(1 if diagnostic else 7)}
                expected|={('NestedChain',shape,str(n),str(v),str(s)) for shape,ns in [('siblings',(16,32,64,128,256,512)),('depth',range(9))] for n in ns for v in (0,1) for s in range(1 if diagnostic else 7)}
                expected|={(g,'control',str(len(text)),str(v),str(sample))
                           for g,text in [('JSON','{"a":[1,true,null],"b":"x"}'),('CSV','a,b,c\n1,2,3\n'),('PEG',"Start <- 'a'")]
                           for v in (0,1) for sample in range(1 if diagnostic else 7)}
                assert len(rows)==len(expected) and {tuple(r[k] for k in ('grammar','shape','size','valid','sample')) for r in rows}==expected
                raw_hashes[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
                for row in rows:
                    assert int(row['ns'])>0
                    if diagnostic and row['shape']=='control': assert int(row['shared_snapshots'])==0
                    key=tuple(row[k] for k in ('grammar','shape','size','valid'))
                    signature=tuple(row[k] for k in ('nodes','end','fail_end','hash'))
                    identity=(backend,memo,selector,key)
                    assert signatures.setdefault(identity,signature)==signature,(policy,key)
                    memory_key=(backend,memo,selector,diagnostic,key)
                    footprint=tuple(row[k] for k in ('peak','requested','allocations'))
                    if policy=='reference': memory_signatures[memory_key]=footprint
                    elif policy=='control' or selector=='root' or row['shape']=='control':
                        assert memory_signatures[memory_key]==footprint,('inactive memory drift',policy,key)
                    if diagnostic and policy=='candidate' and selector=='all' and row['shape']=='flat' and row['size']=='2048':
                        assert int(row['shared_snapshots'])>0 and int(row['reused_nodes'])>0
                    by_case.setdefault(key,[]).append(int(row['ns'])/int(row['iterations']))
            if not diagnostic:
                for key,values in by_case.items(): summaries.append(dict(backend=backend,memo=memo,selector=selector,policy=policy,grammar=key[0],shape=key[1],size=key[2],valid=key[3],median_ns=statistics.median(values)))
            metadata=dict(command=command,runEnvironment=run_environment,binarySha256=binary_hash,sourceHashes=pins,rawHashes=raw_hashes,compiler=compiler,compileWallSeconds=seconds,compilationConcurrency=2,normalControlModes='repository examples: full memo/combinator, eoi wrapper, matching selector',ownership='owned',platform=platform.platform(),cpu=next(l for l in Path('/proc/cpuinfo').read_text().splitlines() if l.startswith('model name')),diagnostic=diagnostic,timeoutSeconds=60,memoryLimitBytes=4*1024**3)
            Path(f'{prefix}.metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
            if policy!='control':
                binary.unlink();binary.with_suffix('.o').unlink(missing_ok=True)
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==v for p,v in pins.items())
    with (destination/'summary.csv').open('w') as out:
        writer=csv.DictWriter(out,fieldnames=summaries[0].keys());writer.writeheader();writer.writerows(summaries)
if __name__=='__main__': main()
