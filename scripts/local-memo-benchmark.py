#!/usr/bin/env python3
"""H04 source-pinned build barrier and equal-output warm/batched measurements."""
from concurrent.futures import ThreadPoolExecutor
import csv, hashlib, json, os, platform, subprocess, sys, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
folder=Path(sys.argv[1] if len(sys.argv)>1 else 'build/H04/matrix').resolve()
folder.mkdir(parents=True,exist_ok=True)
imports=Path('build/H04/imports/npegged');imports.mkdir(parents=True,exist_ok=True)
link=imports/'examples'
if not link.exists(): link.symlink_to(ROOT/'examples',target_is_directory=True)
assert link.resolve()==ROOT/'examples'
sources=sorted(Path('src').rglob('*.d'))+[Path(p) for p in ('examples/json.d','examples/csv.d','examples/PEG.d','benchmark/measurement.d','tests/local_memo.d','benchmark/diagnostics/local_memo.d')]
pins={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[Path(__file__).relative_to(ROOT)]}
def verify():
    for p,h in pins.items(): assert hashlib.sha256(Path(p).read_bytes()).hexdigest()==h,('source drift',p)
jobs=[]
for backend in ("direct","combinators"):
 for diagnostic in (False,True):
  for policy in ('reference','candidate'):
   name=f'{backend}-{policy}-{"metrics" if diagnostic else "timing"}'
   binary=folder/(name+'.runner')
   flags=['-Isrc','-I.','-Ibuild/H04/imports','-defaultlib=druntime-ldc','-fno-exceptions','-O3','-release','-w','-de','-d-version=LocalMemoBenchmark']
   if diagnostic: flags+=['-d-version=NPeggedMetrics']
   if backend=='combinators': flags+=['-d-version=Combinators']
   if policy=='candidate': flags+=['-d-version=NPeggedLocalMemo']
   jobs.append((name,binary,['ldc2',*flags,*map(str,sources),f'-of={binary}'],diagnostic,policy,backend))
def build(job):
    verify();start=time.monotonic()
    subprocess.run(['prlimit','--as=4294967296','--','timeout','--kill-after=2s','300s',*job[2]],check=True,timeout=305)
    verify();return time.monotonic()-start
with ThreadPoolExecutor(max_workers=2) as pool: durations=list(pool.map(build,jobs))
gate=os.environ.get('H04_TIMING_GATE')
while gate and not Path(gate).exists(): time.sleep(1)
verify()
signatures={};memory={};reference_counters={}
for job,compile_seconds in zip(jobs,durations):
 name,binary,command,diagnostic,policy,backend=job
 verify();raw={};row_count=None
 for run in range(1,2 if diagnostic else 4):
  path=folder/f'{name}-run{run}.csv'
  with path.open('w') as output:
   subprocess.run(['prlimit','--as=4294967296','--','timeout','--kill-after=2s','60s',str(binary)],stdout=output,check=True,timeout=65)
  rows=list(csv.DictReader(path.open()));assert len(rows)==(102 if diagnostic else 714),len(rows)
  for row in rows:
   case=tuple(row[k] for k in ('case','mode','size','valid','finite'))
   key=(backend,case)
   value=tuple(row[k] for k in ('nodes','end','fail_end','hash','actions'))
   assert signatures.setdefault(key,value)==value,('output',name,case)
   footprint=tuple(row[k] for k in ('peak','requested','allocations'))
   inactive=row['finite']=='1' or row['case'] in ('Action','ActionGrammar','JSON','CSV','PEG') or row['mode']=='3'
   if policy=='reference': memory[key]=footprint
   elif inactive: assert memory[key]==footprint,('inactive memory',name,case)
   if diagnostic and policy=='candidate':
    if inactive: assert reference_counters[key]==tuple(row[k] for k in ('memo_calls','memo_hits','invalidation_visits')),(name,case)
    elif row['case']=='Root': assert int(row['memo_calls'])<int(reference_counters[key][0]),(name,case)
   elif diagnostic: reference_counters[key]=tuple(row[k] for k in ('memo_calls','memo_hits','invalidation_visits'))
  row_count=len(rows);raw[path.name]=hashlib.sha256(path.read_bytes()).hexdigest()
 metadata=dict(command=command,compiler=subprocess.check_output(['ldc2','--version'],text=True),sourceHead=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),sourceHashes=pins,rawHashes=raw,binarySha256=hashlib.sha256(binary.read_bytes()).hexdigest(),binaryBytes=binary.stat().st_size,compileWallSeconds=compile_seconds,compilationConcurrency=2,diagnostic=diagnostic,rowsPerRun=row_count,timeoutSeconds=60,memoryLimitBytes=4294967296,cpu=next(l for l in Path('/proc/cpuinfo').read_text().splitlines() if l.startswith('model name')),platform=platform.platform(),ownership='check borrowed; records borrowed/owned; tree owned; destruction inside clock',normalControls='repository JSON/CSV/PEG full/combinator, eoi wrapper')
 (folder/f'{name}.metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
 binary.unlink();binary.with_suffix('.o').unlink(missing_ok=True)
verify()
