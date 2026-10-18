"""Verify H04 raw measurements and summarize speed and scaling separately."""
import csv, hashlib, json, statistics
from pathlib import Path
root=Path(__file__).parent;folder=root/'matrix'
meta=list(folder.glob('*.metadata.json'));assert len(meta)==8
raw={};metrics={};pins=None
for path in meta:
 data=json.loads(path.read_text());backend,policy,kind=path.name.removesuffix('.metadata.json').split('-')
 if pins is None: pins=data['sourceHashes']
 assert pins==data['sourceHashes']
 for name,digest in data['rawHashes'].items():
  path=folder/name;assert hashlib.sha256(path.read_bytes()).hexdigest()==digest
  rows=list(csv.DictReader(path.open()));assert len(rows)==(102 if kind=='metrics' else 714)
  for row in rows:
   case=tuple(row[k] for k in ('case','mode','size','valid','finite'));key=(backend,policy,case)
   if kind=='metrics': assert key not in metrics;metrics[key]=row
   else: raw.setdefault(key,[]).append(int(row['ns'])/int(row['iterations']))
rows=[]
for (backend,policy,case),values in raw.items():
 assert len(values)==21
 if policy!='candidate':continue
 baseline=raw[backend,'reference',case];m=metrics[backend,policy,case];b=metrics[backend,'reference',case]
 rows.append(dict(backend=backend,case=case[0],mode=int(case[1]),size=int(case[2]),valid=int(case[3]),finite=int(case[4]),ratio=statistics.median(values)/statistics.median(baseline),reference_ns=statistics.median(baseline),candidate_ns=statistics.median(values),runs=[statistics.median(values[i:i+7])/statistics.median(baseline[i:i+7]) for i in (0,7,14)],reference_memo=int(b['memo_calls']),candidate_memo=int(m['memo_calls']),reference_bytes=int(b['requested']),candidate_bytes=int(m['requested'])))
rows.sort(key=lambda r:(r['backend'],r['case'],r['mode'],r['size'],r['valid'],r['finite']))
with (root/'ratios.csv').open('w') as stream:
 writer=csv.DictWriter(stream,fieldnames=rows[0].keys(),lineterminator='\n');writer.writeheader();writer.writerows(rows)
scaling=[]
for backend in ("direct","combinators"):
 for case in ('Root','Overlap','Recursive','Indirect'):
  for mode in (0,2):
   selected=[r for r in rows if r['backend']==backend and r['case']==case and r['mode']==mode and r['valid'] and not r['finite']]
   a,b=selected[0],selected[-1]
   scaling.append(dict(backend=backend,case=case,mode=mode,small=a['size'],large=b['size'],reference_growth=b['reference_ns']/a['reference_ns'],candidate_growth=b['candidate_ns']/a['candidate_ns'],relative_growth=b['ratio']/a['ratio']))
guarded=[]
for backend in ('direct','combinators'):
 for mode,finite in ((3,0),(0,1)):
  selected=[r for r in rows if r['backend']==backend and r['case']=='Root' and r['mode']==mode and r['valid'] and r['finite']==finite]
  a,b=selected[0],selected[-1]
  guarded.append(dict(backend=backend,mode=mode,finite=finite,small=a['size'],large=b['size'],small_ratio=a['ratio'],large_ratio=b['ratio'],relative_growth=b['ratio']/a['ratio']))
analysis=dict(decision='rejected: rollback after repeated large guarded-off regressions and worse growth',timingSamples=sum(map(len,raw.values())),counterSamples=len(metrics),sourceHashes=pins,scaling=scaling,guardedOffGrowth=guarded,worstCases=sorted(rows,key=lambda r:r['ratio'],reverse=True)[:15])
(root/'analysis.json').write_text(json.dumps(analysis,indent=2)+'\n')
lines=['# H04 timing and work','','Each timing ratio uses 3 runs × 7 samples; metrics are separate. Ratios below 1 favor the experiment. Modes: 0 recognition, 1 borrowed records, 2 owned records, 3 full tree.','','| Backend | Case | Mode | Size | Ratio | Three run ratios | Memo calls ref → candidate | Requested bytes ref → candidate |','|---|---|---:|---:|---:|---|---:|---:|']
for r in rows:
 if not r['valid'] or r['finite']:continue
 lines.append(f"| {r['backend']} | {r['case']} | {r['mode']} | {r['size']} | {r['ratio']:.3f} | "+'/'.join(f'{x:.3f}' for x in r['runs'])+f" | {r['reference_memo']} → {r['candidate_memo']} | {r['reference_bytes']} → {r['candidate_bytes']} |")
lines+=['','## Scaling endpoints','','| Backend | Case | Mode | Size range | Reference growth | Candidate growth | Relative growth |','|---|---|---:|---|---:|---:|---:|']
for r in scaling:lines.append(f"| {r['backend']} | {r['case']} | {r['mode']} | {r['small']} → {r['large']} | {r['reference_growth']:.3f} | {r['candidate_growth']:.3f} | {r['relative_growth']:.3f} |")
lines+=['','## Rejection: guarded-off growth','','| Backend | Mode | Finite | Small ratio | Large ratio | Relative growth |','|---|---:|---:|---:|---:|---:|']
for r in guarded:lines.append(f"| {r['backend']} | {r['mode']} | {r['finite']} | {r['small_ratio']:.3f} | {r['large_ratio']:.3f} | {r['relative_growth']:.3f} |")
(root/'timing-summary.md').write_text('\n'.join(lines)+'\n')
import matplotlib
matplotlib.use('Agg');matplotlib.rcParams['svg.hashsalt']='H04'
import matplotlib.pyplot as plt
fig,axes=plt.subplots(2,4,figsize=(13,6),layout='constrained')
for row,backend in enumerate(('direct','combinators')):
 for ax,case in zip(axes[row],('Root','Overlap','Recursive','Indirect')):
  for mode in (0,2):
   selected=[r for r in rows if r['backend']==backend and r['case']==case and r['mode']==mode and r['valid'] and not r['finite']]
   ax.plot([r['size'] for r in selected],[r['ratio'] for r in selected],marker='.',label='recognition' if mode==0 else 'owned records')
  if case=='Root':
   for mode,finite,label in ((3,0,'full tree'),(0,1,'finite recognition')):
    selected=[r for r in rows if r['backend']==backend and r['case']==case and r['mode']==mode and r['valid'] and r['finite']==finite]
    ax.plot([r['size'] for r in selected],[r['ratio'] for r in selected],marker='x',linestyle='--',label=label)
  ax.axhline(1,color='black',linewidth=.7);ax.set_title(backend+'/'+case);ax.set_xlabel('tokens / scan bytes');ax.set_ylabel('candidate/reference time');ax.grid(alpha=.2)
axes[0,0].legend();path=root/'timing-ratios.svg';fig.savefig(path,metadata={'Date':None});path.write_text('\n'.join(x.rstrip() for x in path.read_text().splitlines())+'\n')
