#!/usr/bin/env python3
"""R04 diagnostic cohorts and standalone logarithmic plots."""
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def bounded():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3, 4 * 1024**3))


def main():
    os.chdir(ROOT)
    destination = Path(sys.argv[1] if len(sys.argv)>1 else 'build/record-copying').resolve()
    destination.mkdir(parents=True, exist_ok=True)
    sources = sorted(Path('src').rglob('*.d')) + [Path('benchmark/diagnostics/record_copying.d')]
    pins = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[Path(__file__).relative_to(ROOT)]}
    all_rows = []
    for backend in ('combinators','direct'):
        for memo in ('selective','full'):
            for selector in ('root','all'):
                name = f'{backend}-{memo}-{selector}'
                binary = destination / f'{name}.runner'
                flags = ['-Isrc','-defaultlib=druntime-ldc','-fno-exceptions','-O3','-release','-w','-de','-checkaction=halt','-d-version=NPeggedMetrics']
                if backend=='direct': flags += ['-d-version=NPeggedDirect']
                if memo=='full': flags += ['-d-version=NPeggedFullMemo']
                if selector=='root': flags += ['-d-version=RootOnly']
                command = ['ldc2',*flags,*map(str,sources),f'-of={binary}']
                subprocess.run(command,check=True,timeout=300,preexec_fn=bounded)
                path = destination / f'{name}.csv'
                with path.open('w') as stream:
                    subprocess.run(['timeout','--kill-after=2s','60s',str(binary)],stdout=stream,check=True,timeout=65,preexec_fn=bounded)
                rows = list(csv.DictReader(path.open()))
                expected = {(g,str(n),str(v)) for g in ('DirectChain','IndirectChain') for n in (16,32,64,128,256,512,1024,2048) for v in (0,1)}
                assert len(rows)==len(expected) and {tuple(r[k] for k in ('grammar','terms','valid')) for r in rows}==expected
                for row in rows:
                    assert int(row['logical_bytes'])==int(row['output_nodes'])*32
                    if selector=='root': assert int(row['output_nodes'])==int(row['valid'])
                    all_rows.append(dict(backend=backend,memo=memo,selector=selector,**row))
                metadata = dict(command=command,sourceHashes=pins,rawSha256=hashlib.sha256(path.read_bytes()).hexdigest(),compiler=subprocess.check_output(['ldc2','--version'],text=True),platform=platform.platform(),cpu=Path('/proc/cpuinfo').read_text(),timeoutSeconds=60,memoryLimitBytes=4*1024**3)
                (destination/f'{name}.metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
                binary.unlink()
                binary.with_suffix('.o').unlink(missing_ok=True)
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in pins.items())
    with (destination/'summary.csv').open('w') as stream:
        writer=csv.DictWriter(stream,fieldnames=all_rows[0].keys());writer.writeheader();writer.writerows(all_rows)
    # Each line has its own units: cumulative copying is work, not live memory.
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    for backend in ('combinators','direct'):
        fig,axes=plt.subplots(2,4,figsize=(17,8),layout='constrained')
        for column,(grammar,memo) in enumerate((g,m) for g in ('DirectChain','IndirectChain') for m in ('selective','full')):
            for index,selector in enumerate(('root','all')):
                ax=axes[index,column]
                rows=[r for r in all_rows if r['backend']==backend and r['grammar']==grammar and r['memo']==memo and r['selector']==selector and r['valid']=='1']
                x=[int(r['terms']) for r in rows]
                series={'logical output': [int(r['logical_bytes']) for r in rows],
                        'requested payload': [int(r['parse_requested'])+int(r['output_requested']) for r in rows],
                        'peak retained': [int(r['parse_peak'])+int(r['output_peak']) for r in rows],
                        'snapshot copies': [int(r['snapshot_bytes']) for r in rows],
                        'restore copies': [int(r['restore_bytes']) for r in rows],
                        'buffer growth copies': [int(r['growth_copy_bytes']) for r in rows]}
                for label,y in series.items():
                    if any(y): ax.plot(x,y,marker='.',label=label)
                ax.set_xscale('log',base=2);ax.set_yscale('log',base=2)
                ax.set_title(f'{grammar} / {memo} / {selector}');ax.set_xlabel('terms');ax.set_ylabel('bytes');ax.grid(alpha=.2)
        handles,labels=axes[1,0].get_legend_handles_labels()
        fig.legend(handles,labels,loc='outside lower center',ncol=3)
        fig.suptitle(f'R04 {backend}: cumulative copy work versus output and memory')
        fig.savefig(destination/f'{backend}.svg');plt.close(fig)


if __name__=='__main__': main()
