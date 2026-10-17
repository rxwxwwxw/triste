#!/usr/bin/env python3
"""R02: collect and analyze bounded dependency traces without changing invalidation."""
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

ROOT = Path(__file__).resolve().parents[1]


def analyze(rows):
    """Conservative transitive read sets; retain all iterations, including failed probes."""
    active, heads, retired = set(), set(), set()
    parents, names, positions, dependencies, direct = {}, {}, {}, {}, {}
    edges, cache_edges, retirements = set(), [], []
    max_heads = 0
    same_position = distinct_positions = False
    finished = False

    def propagate(caller, reads):
        while caller:
            dependencies[caller].update(reads)
            edges.update((caller, seed) for seed in reads)
            caller = parents[caller]

    for sequence, row in enumerate(rows):
        if finished or int(row['sequence']) != sequence:
            raise ValueError('discontinuous or trailing events')
        kind, caller, entry, position = (int(row[k]) for k in ('kind','caller','entry','position'))
        if kind == 7:
            if active or entry or caller:
                raise ValueError('incomplete trace at case terminator')
            finished = True
            continue
        if kind == 0:
            if entry != len(parents)+1 or entry in parents or caller and caller not in active:
                raise ValueError('unstable entry identity or inactive caller')
            parents[entry], names[entry], positions[entry] = caller, row['rule'], position
            dependencies[entry], direct[entry] = set(), set()
            active.add(entry)
        elif entry not in parents or entry in retired:
            raise ValueError('event names an absent or retired entry')
        elif kind == 2:
            if entry not in active or caller not in active:
                raise ValueError('active seed read outside evaluation')
            heads.add(entry)
            direct[caller].add(entry)
            propagate(caller, dependencies[entry] | {entry})
        elif kind == 3:
            if entry in active or caller and caller not in active:
                raise ValueError('completed hit has active target or inactive caller')
            cache_edges.append((caller,entry,sorted(dependencies[entry])))
            propagate(caller, dependencies[entry])
        elif kind == 4:
            if entry not in active: raise ValueError('inactive seed growth')
        elif kind == 5:
            if entry in active or caller not in active:
                raise ValueError('retired active seed or inactive growing head')
            retirements.append(dict(head=caller,entry=entry,rule=names[entry],position=position,
                                    depends=caller in dependencies[entry],
                                    directlyReadsHead=caller in direct[entry]))
            retired.add(entry)
        elif kind == 6:
            if entry not in active: raise ValueError('duplicate completion')
            active.remove(entry)
            propagate(parents[entry], dependencies[entry])
        elif kind == 1:
            if entry not in active or caller != entry: raise ValueError('iteration outside its evaluation')
        else:
            raise ValueError('unknown trace event')
        live_heads = active & heads
        max_heads = max(max_heads,len(live_heads))
        for a in live_heads:
            for b in live_heads:
                if a < b:
                    same_position |= positions[a] == positions[b]
                    distinct_positions |= positions[a] != positions[b]
    if not finished: raise ValueError('missing case terminator; dependency conclusions rejected')
    return dict(entries=len(parents),edges=sorted(edges),cachedReads=cache_edges,
                retirements=retirements, maxActiveHeads=max_heads,
                samePositionHeads=same_position,distinctPositionHeads=distinct_positions,
                broadRetirements=len(retirements),
                dependentRetirements=sum(r['depends'] for r in retirements),
                directOnlyMisses=sum(r['depends'] and not r['directlyReadsHead'] for r in retirements))


def bounded():
    resource.setrlimit(resource.RLIMIT_AS,(4*1024**3,4*1024**3))


def main():
    os.chdir(ROOT)
    destination = Path(sys.argv[1] if len(sys.argv)>1 else 'build/memo-dependencies').resolve()
    destination.mkdir(parents=True,exist_ok=True)
    sources = [*sorted(Path('src').rglob('*.d')),Path('tests/memo_dependency.d')]
    hashes = {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources,Path('scripts/memo-dependencies.py')]}
    summaries = {}
    for backend in ('combinators','direct'):
        for memo in ('full','selective'):
            prefix = destination/f'{backend}-{memo}'
            flags = ['-Isrc','-I.','-d-version=NPeggedDependencyTrace','-defaultlib=druntime-ldc',
                     '-fno-exceptions','-w','-checkaction=halt']
            if backend=='direct': flags+=['-d-version=NPeggedDirect']
            if memo=='selective': flags+=['-d-version=NPeggedSelectiveMemo']
            command=['ldc2',*flags,*map(str,sources),f'-of={prefix}.runner']
            subprocess.run(command,timeout=300,preexec_fn=bounded,check=True)
            path=Path(f'{prefix}.csv')
            with path.open('w') as output:
                subprocess.run(['timeout','--kill-after=2s','60s',str(prefix)+'.runner'],stdout=output,
                               timeout=65,preexec_fn=bounded,check=True)
            groups=defaultdict(list)
            with path.open() as stream:
                for row in csv.DictReader(stream):groups[row['grammar'],row['input']].append(row)
            if len(groups)!=112:raise ValueError('missing regression cases')
            result=[dict(grammar=g,input=i,**analyze(rows)) for (g,i),rows in groups.items()]
            assert any(r['samePositionHeads'] for r in result)
            assert any(r['distinctPositionHeads'] for r in result)
            assert any(r['directOnlyMisses'] and r['cachedReads'] for r in result)
            Path(f'{prefix}.analysis.json').write_text(json.dumps(result,indent=2)+'\n')
            summaries[f'{backend}-{memo}']=dict(cases=len(result),events=sum(len(v) for v in groups.values()),
                broadRetirements=sum(r['broadRetirements'] for r in result),
                dependentRetirements=sum(r['dependentRetirements'] for r in result),
                directOnlyMisses=sum(r['directOnlyMisses'] for r in result))
            metadata=dict(command=command,compiler=subprocess.check_output(['ldc2','--version'],text=True),
                platform=platform.platform(),cpu=Path('/proc/cpuinfo').read_text(),
                revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),sourceHashes=hashes,
                traceCapacity=8192,timeoutSeconds=60,memoryLimitBytes=4*1024**3,
                traceSha256=hashlib.sha256(path.read_bytes()).hexdigest())
            Path(f'{prefix}.metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
            Path(f'{prefix}.runner').unlink()
            Path(f'{prefix}.o').unlink(missing_ok=True)
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
    (destination/'summary.json').write_text(json.dumps(summaries,indent=2)+'\n')


if __name__=='__main__':main()
