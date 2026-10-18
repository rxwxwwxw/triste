#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
folder=${1:-performance/results/H05/peg}
mkdir -p "$folder" build/H05/peg
python3 - "$folder" <<'PY'
import hashlib,json,sys
from pathlib import Path
sources=sorted(Path('src').rglob('*.d'))+[Path(p) for p in ('benchmark/workload_grammars.d','benchmark/diagnostics/peg_probe.d','benchmark/measurement.d','scripts/empty-scanner-peg-probe.sh')]
(Path(sys.argv[1])/'sources.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},indent=2)+'\n')
PY
mapfile -t library < <(rg --files src -g '*.d' | sort)
flags=(-Isrc -I. -J. -defaultlib=druntime-ldc -fno-exceptions -O3 -release -boundscheck=off -w -checkaction=halt -d-version=NPeggedDirect)
prlimit --as=4294967296 -- timeout --kill-after=2s 300s ldc2 "${flags[@]}" "${library[@]}" benchmark/measurement.d benchmark/diagnostics/peg_probe.d -of=build/H05/peg/direct-selective.runner
for run in 1 2 3; do
 prlimit --as=4294967296 -- timeout --kill-after=2s 60s build/H05/peg/direct-selective.runner > "$folder/run$run.csv" 2> "$folder/run$run.trace.csv"
done
objdump -Cd build/H05/peg/direct-selective.runner > build/H05/peg/assembly.txt
python3 - "$folder" "${flags[@]}" <<'PY'
import csv,hashlib,json,re,subprocess,sys
from pathlib import Path
root=Path(sys.argv[1]);pins=json.loads((root/'sources.json').read_text())
for name,digest in pins.items():assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,name
text=Path('build/H05/peg/assembly.txt').read_text();match=re.search(r'^([0-9a-f]+) <[^\n]*BenchPEG\._cursor_Sp[^\n]*>:\n',text,re.M);assert match
rest=text[match.start():];offset=rest.index('\n')+1;end=re.search(r'^\w+ <',rest[offset:],re.M);section=rest[:offset+end.start()] if end else rest
(root/'Sp.assembly.txt').write_text('\n'.join(x.rstrip() for x in section.splitlines())+'\n')
raw={}
for p in sorted(root.glob('run*.csv')):
 raw[p.name]=hashlib.sha256(p.read_bytes()).hexdigest()
 if not p.name.endswith('.trace.csv'):assert len(list(csv.DictReader(p.open())))==56
(root/'metadata.json').write_text(json.dumps(dict(compiler=subprocess.check_output(['ldc2','--version'],text=True),flags=sys.argv[2:],sourceHashes=pins,rawHashes=raw,sourceHead=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),binarySha256=hashlib.sha256(Path('build/H05/peg/direct-selective.runner').read_bytes()).hexdigest(),assemblySha256=hashlib.sha256(text.encode()).hexdigest(),cursorStaticCalls=len(re.findall(r'\bcall\b',section)),timeoutSeconds=60,memoryLimitBytes=4294967296,stageTiming='diagnostic probes, not performance gate times'),indent=2)+'\n')
PY
