#!/usr/bin/env python3
"""D01 native ratios, activation assertions and guarded-control accounting."""
import csv
import json
from pathlib import Path
import statistics
from d01_pure_islands import inactive

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'performance/phase3/D01'


def main():
    rows=list(csv.DictReader((DEST/'observations.csv').open()))
    fields=('selector','case','mode','size','valid','finite','tracing')
    timed, metrics={},{}
    for row in rows:
        key=tuple(row[k] for k in fields)
        if row['diagnostic']=='True': metrics[(*key,row['feature'])]=row
        else: timed.setdefault((*key,row['feature']),{}).setdefault(int(row['run']),[]).append(int(row['ns'])/int(row['iterations']))
    comparisons=[]
    for identity, samples in sorted(timed.items()):
        if identity[-1]!='True': continue
        key=identity[:-1]; base=timed[(*key,'False')]
        assert sorted(samples)==sorted(base)==[1,2,3]
        ratios=[statistics.median(samples[r])/statistics.median(base[r]) for r in sorted(samples)]
        m=metrics[(*key,'True')]
        guarded=inactive(m,key[0],key[-1]=='1')
        entries=int(m['island_entries'])
        assert (entries==0) if guarded else (entries>0),('activation mismatch',key,entries)
        comparisons.append(dict(zip(fields,key)) | dict(
            guarded=guarded,entries=entries,fallbacks=int(m['island_fallbacks']),
            medianOnOverOff=statistics.median(ratios),runRatios=ratios,runRatioRange=[min(ratios),max(ratios)],
            runRatioStdDev=statistics.stdev(ratios),
            perRunOffNs=[statistics.median(base[r]) for r in sorted(base)],
            perRunOnNs=[statistics.median(samples[r]) for r in sorted(samples)],
            medianOffNs=statistics.median(statistics.median(v) for v in base.values()),
            medianOnNs=statistics.median(statistics.median(v) for v in samples.values()),
            nodes=int(m['nodes']),actions=int(m['actions']),traceEvents=int(m['trace_events'])))
    assert len(comparisons)==972
    finite=[r for r in comparisons if r['finite']=='1' and r['tracing']=='0']
    traced=[r for r in comparisons if r['tracing']=='1']
    assert len(finite)==234 and len(traced)==486
    assert all(r['entries']==0 for r in finite+traced)
    result=dict(milestone='D01',comparisons=comparisons,
        activeCases=sum(not r['guarded'] for r in comparisons),
        finiteUntracedCases=len(finite),tracedCases=len(traced),defaultPolicyEligibleFraction=0,
        confidence='Three independent paired invocation ratios; ranges, not confidence intervals. Inner seven samples are not independent trials.')
    (DEST/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axes=plt.subplots(1,3,figsize=(12,4),layout='constrained')
    for axis,(case,mode) in zip(axes,[('Identifier','0'),('Root','0'),('Root','2')]):
        for selector in ['all','root','leaf']:
            data=sorted((r for r in comparisons if r['case']==case and r['mode']==mode and r['selector']==selector
                and r['finite']=='0' and r['tracing']=='0' and r['valid']=='1'),key=lambda r:int(r['size']))
            axis.plot([int(r['size']) for r in data],[r['medianOnOverOff'] for r in data],marker='.',label=selector)
        axis.axhline(1,color='black',linewidth=.7);axis.set_xscale('log',base=2);axis.set_yscale('log')
        axis.set_title(f'{case}, mode {mode}');axis.set_xlabel('Input bytes / words');axis.grid(alpha=.2)
    axes[0].set_ylabel('Opt-in / reference latency (lower is faster)');axes[-1].legend()
    fig.suptitle('D01: unlimited, no tracing; Root records with all selection is guarded fallback')
    fig.savefig(DEST/'active-ratios.svg');plt.close(fig)
    print('Active cases:',result['activeCases'],'finite controls:',len(finite),'traced controls:',len(traced))
    for r in comparisons:
        if r['selector']=='all' and r['valid']=='1' and r['size']=='128' and r['case'] in ['Root','ActRoot']:
            print(r['case'],r['mode'],'finite',r['finite'],'trace',r['tracing'],round(r['medianOnOverOff'],4),r['entries'])


if __name__=='__main__': main()
