#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
folder=${1:-performance/results/H05}
mkdir -p "$folder" build/H05
python3 - "$folder" <<'PY'
import hashlib,json,sys
from pathlib import Path
sources=sorted(Path('src').rglob('*.d'))+[Path(p) for p in ('tests/empty_scanner.d','benchmark/diagnostics/empty_sp.d','benchmark/measurement.d','scripts/empty-scanner-probe.sh')]
(Path(sys.argv[1])/'sources.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},indent=2)+'\n')
PY
mapfile -t library < <(rg --files src -g '*.d' | sort)
flags=(-Isrc -I. -defaultlib=druntime-ldc -fno-exceptions -O3 -release -w)
start=$SECONDS
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" "${library[@]}" benchmark/measurement.d benchmark/diagnostics/empty_sp.d -of=build/H05/baseline.runner
compile_seconds=$((SECONDS-start))
objdump -Cd build/H05/baseline.runner > build/H05/baseline.assembly.txt
for run in 1 2 3; do
 prlimit --as=4294967296 -- timeout --kill-after=2s 60s build/H05/baseline.runner > "$folder/baseline-run$run.csv"
done
python3 - "$folder" "$compile_seconds" "${flags[@]}" <<'PY'
import csv,hashlib,json,platform,subprocess,sys,statistics,re
from pathlib import Path
root=Path(sys.argv[1]);pins=json.loads((root/'sources.json').read_text())
for name,h in pins.items():assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==h,name
raw={};samples={}
for run in range(1,4):
 p=root/f'baseline-run{run}.csv';raw[p.name]=hashlib.sha256(p.read_bytes()).hexdigest()
 rows=list(csv.DictReader(p.open()));assert len(rows)==42
 for r in rows:samples.setdefault(int(r['case']),[]).append(int(r['ns'])/int(r['iterations']))
assembly=Path('build/H05/baseline.assembly.txt').read_text();match=re.search(r'^([0-9a-f]+) <[^\n]*EmptySP\._cursor_Sp[^\n]*>:\n',assembly,re.M);assert match
rest=assembly[match.start():];next_symbol=re.search(r'^\w+ <',rest[rest.index('\n')+1:],re.M)
end=rest.index('\n')+1+next_symbol.start() if next_symbol else len(rest)
section=rest[:end];(root/'Sp.assembly.txt').write_text('\n'.join(x.rstrip() for x in section.splitlines())+'\n')
metadata=dict(sourceHead=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),sourceHashes=pins,rawHashes=raw,compiler=subprocess.check_output(['ldc2','--version'],text=True),flags=sys.argv[3:],compileWallSeconds=int(sys.argv[2]),compilationConcurrency=1,platform=platform.platform(),cpu=next(l for l in Path('/proc/cpuinfo').read_text().splitlines() if l.startswith('model name')),timeoutSeconds=60,memoryLimitBytes=4294967296,samplesPerCase=21,iterations=100000,warmup=1000,binarySha256=hashlib.sha256(Path('build/H05/baseline.runner').read_bytes()).hexdigest(),assemblySha256=hashlib.sha256(assembly.encode()).hexdigest(),cursorStaticCalls=len(re.findall(r'\bcall\b',section)),cursorStaticInstructions=sum(bool(re.match(r'^\s*[0-9a-f]+:\s',l)) for l in section.splitlines()),caseInputs=['x','',' ','#','#comment\n',' \t#one\n#two\n x'],mediansNs={str(k):statistics.median(v) for k,v in samples.items()})
(root/'baseline.metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
print('Source-pinned baseline and optimized Sp evidence recorded')
PY
