#!/usr/bin/env python3
"""R03: compare an isolated opt-in prototype with the retained production parser."""
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import subprocess
import sys
from collections import defaultdict
import statistics

ROOT=Path(__file__).resolve().parents[1]


def bounded():resource.setrlimit(resource.RLIMIT_AS,(4*1024**3,4*1024**3))


def main():
    candidate=Path(sys.argv[1]).resolve()
    destination=Path(sys.argv[2] if len(sys.argv)>2 else ROOT/'build/narrow-invalidation').resolve()
    destination.mkdir(parents=True,exist_ok=True)
    summaries={}
    signatures={}
    driver_hash=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    for backend in ('combinators','direct'):
        for policy in ('reference','control','candidate'):
            source=ROOT if policy=='reference' else candidate
            files=[*sorted(Path('src').rglob('*.d'))] if source==Path.cwd() else sorted(p.relative_to(source) for p in (source/'src').rglob('*.d'))
            files += [Path('benchmark/measurement.d'),Path('benchmark/diagnostics/narrow_invalidation.d')]
            hashes={str(p):hashlib.sha256((source/p).read_bytes()).hexdigest() for p in files}
            for diagnostic in (False,True):
                prefix=destination/f'{backend}-{policy}-{"metrics" if diagnostic else "timing"}'
                flags=['-Isrc','-I.','-defaultlib=druntime-ldc','-fno-exceptions','-O3','-release','-w','-de','-checkaction=halt']
                if backend=='direct':flags+=['-d-version=NPeggedDirect']
                if policy!='reference':flags+=['-d-version=NPeggedNarrowInvalidation']
                if policy=='candidate':flags+=['-d-version=NPeggedNarrowOptIn']
                if diagnostic:flags+=['-d-version=NPeggedMetrics']
                command=['ldc2',*flags,*map(str,files),f'-of={prefix}.runner']
                subprocess.run(command,cwd=source,timeout=300,preexec_fn=bounded,check=True)
                groups=defaultdict(list)
                for run in range(1,2 if diagnostic else 4):
                    path=Path(f'{prefix}-run{run}.csv')
                    with path.open('w') as stream:
                        subprocess.run(['timeout','--kill-after=2s','60s',str(prefix)+'.runner'],stdout=stream,
                                       timeout=65,preexec_fn=bounded,check=True)
                    with path.open() as stream:rows=list(csv.DictReader(stream))
                    expected={(str(shape),str(size),str(sample))
                              for shape,sizes in ((0,(16,32,64,128,256,512,1024,2048,4096,8192)),
                                                  (1,(16,32,64,128,256,512)),(2,range(9)))
                              for size in sizes for sample in range(1 if diagnostic else 7)}
                    assert len(rows)==len(expected) and {tuple(r[k] for k in ('shape','size','sample')) for r in rows}==expected
                    for row in rows:
                        key=(row['shape'],row['size'])
                        sig=(row['end'],row['fail_end'])
                        if (backend,key) in signatures:assert signatures[backend,key]==sig,(backend,policy,key,'semantic delta')
                        else:signatures[backend,key]=sig
                        groups[key].append(row)
                assert all(hashlib.sha256((source/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
                metadata=dict(command=command,sourceRoot=str(source),sourceHashes=hashes,driverSha256=driver_hash,
                              compiler=subprocess.check_output(['ldc2','--version'],text=True),
                              platform=platform.platform(),cpu=Path('/proc/cpuinfo').read_text(),
                              revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip(),
                              diagnostic=diagnostic,runs=1 if diagnostic else 3,samples=1 if diagnostic else 7,
                              iterations=1 if diagnostic else 32,timeoutSeconds=60,memoryLimitBytes=4*1024**3)
                Path(f'{prefix}.metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
                if not diagnostic:
                    summaries[f'{backend}-{policy}']={f'{k[0]}/{k[1]}':statistics.median(int(r['ns'])/int(r['iterations']) for r in rows) for k,rows in groups.items()}
                Path(f'{prefix}.runner').unlink()
                Path(f'{prefix}.o').unlink(missing_ok=True)
    (destination/'summary.json').write_text(json.dumps(summaries,indent=2)+'\n')


if __name__=='__main__':main()
