"""Review H03 timings separately from work counters and guarded-off controls."""
import csv,hashlib,json,statistics,sys
from pathlib import Path
folder=Path(sys.argv[1] if len(sys.argv)>1 else Path(__file__).parent/'matrix')
metadata=sorted(folder.glob('*.metadata.json'))
assert len(metadata)==24,len(metadata)
raw={};counters={};pins=None
for p in metadata:
 d=json.loads(p.read_text());name=p.name.removesuffix('.metadata.json')
 memo,projection,policy,kind=name.split('-')
 if pins is None: pins=d['sourceHashes']
 assert pins==d['sourceHashes']
 for filename,digest in d['rawHashes'].items():
  path=folder/filename
  assert hashlib.sha256(path.read_bytes()).hexdigest()==digest,filename
  rows=list(csv.DictReader(path.open()));assert len(rows)==(126 if kind=='metrics' else 882)
  for row in rows:
   case=tuple(row[k] for k in ('case','mode','size','valid','finite'))
   key=(memo,projection,policy,case)
   if kind=='metrics':
    assert key not in counters;counters[key]=row
   else: raw.setdefault(key,[]).append(int(row['ns'])/int(row['iterations']))
ratios=[]
for (memo,projection,policy,case),values in raw.items():
 assert len(values)==21
 if policy!='candidate': continue
 reference=raw[memo,projection,'reference',case]
 ratios.append(dict(memo=memo,projection=projection,case=case[0],mode=int(case[1]),size=int(case[2]),valid=int(case[3]),finite=int(case[4]),ratio=statistics.median(values)/statistics.median(reference),candidate_ns=statistics.median(values),reference_ns=statistics.median(reference),runs=[statistics.median(values[i:i+7])/statistics.median(reference[i:i+7]) for i in (0,7,14)]))
ratios.sort(key=lambda r:r['ratio'],reverse=True)
root=folder.parent
with (root/'ratios.csv').open('w') as stream:
 writer=csv.DictWriter(stream,fieldnames=ratios[0].keys(),lineterminator='\n');writer.writeheader();writer.writerows(ratios)
analysis=dict(decision='retain explicit experiment; no default promotion: finite-budget small-case regression',timingSamples=sum(map(len,raw.values())),counterSamples=len(counters),cohorts=len(metadata),sourceHashes=pins,worstCases=ratios[:30])
(root/'analysis.json').write_text(json.dumps(analysis,indent=2)+'\n')
lines=['# H03 complete timing matrix','','Ratios below 1 favor the opt-in build. Timings exclude metrics; every median uses 3 runs × 7 samples.','',
'| Memo | Projection | Case | Mode | Size | Ratio | Three run ratios |','|---|---|---|---:|---:|---:|---|']
for row in sorted(ratios,key=lambda r:(r['memo'],r['projection'],r['case'],r['mode'],r['size'])):
 if not row['valid'] or row['finite']: continue
 if row['case'] in ('Identifier','Whitespace'):
  if row['size'] not in (16,1024,256) or row['mode'] not in (0,2): continue
 elif row['case']=='Root':
  if row['size']!=128 or row['mode'] not in (0,2,3): continue
 elif row['case']=='ActRoot':
  if row['size']!=128: continue
 lines.append(f"| {row['memo']} | {row['projection']} | {row['case']} | {row['mode']} | {row['size']} | {row['ratio']:.3f} | "+'/'.join(f'{r:.3f}' for r in row['runs'])+' |')
lines+=['','## Worst cases','']
for row in ratios[:15]: lines.append(f"- {row['memo']}/{row['projection']} {row['case']} mode={row['mode']} size={row['size']} valid={row['valid']} finite={row['finite']}: {row['ratio']:.3f}×; runs "+'/'.join(f'{r:.3f}' for r in row['runs'])+'.')
(root/'timing-summary.md').write_text('\n'.join(lines)+'\n')
import matplotlib
matplotlib.use('Agg');matplotlib.rcParams['svg.hashsalt']='H03'
import matplotlib.pyplot as plt
fig,axes=plt.subplots(2,3,figsize=(13,7),layout='constrained')
for col,case in enumerate(('Identifier','Whitespace','Root')):
 for row,mode in enumerate((0,2)):
  ax=axes[row,col]
  for memo in ('selective','full'):
   for projection in ('all','root','leaf'):
    selected=sorted((r for r in ratios if r['case']==case and r['mode']==mode and r['valid'] and not r['finite'] and r['memo']==memo and r['projection']==projection),key=lambda r:r['size'])
    ax.plot([r['size'] for r in selected],[r['ratio'] for r in selected],marker='.',label=memo+'/'+projection)
  ax.axhline(1,color='black',linewidth=.7);ax.set_title(case+(' check' if mode==0 else ' owned records'));ax.set_xlabel('input size / Root words');ax.set_ylabel('candidate/reference time');ax.grid(alpha=.2)
fig.legend(*axes[0,0].get_legend_handles_labels(),loc='outside lower center',ncol=3)
fig.suptitle('H03 pure-entry timing ratios; Root/all records retain legacy projection')
path=root/'timing-ratios.svg';fig.savefig(path,metadata={'Date':None});path.write_text('\n'.join(line.rstrip() for line in path.read_text().splitlines())+'\n')
