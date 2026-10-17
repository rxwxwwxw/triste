#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination=${1:-build/peg-probe}
mkdir -p "$destination"
ulimit -v 4194304
mapfile -t library < <(rg --files src -g '*.d' | sort)
for backend in combinators direct; do
  for memoization in selective full; do
    flags=(-Isrc -I. -J. -defaultlib=druntime-ldc -fno-exceptions -O3 -release -boundscheck=off -w -checkaction=halt)
    if [[ $backend == direct ]]; then flags+=(-d-version=NPeggedDirect); fi
    if [[ $memoization == full ]]; then flags+=(-d-version=NPeggedFullMemo); fi
    prefix="$destination/$backend-$memoization"
    ldc2 "${flags[@]}" "${library[@]}" benchmark/measurement.d benchmark/diagnostics/peg_probe.d -of="$prefix.runner"
    for run in 1 2 3; do
      timeout --preserve-status --kill-after=2s 60s "$prefix.runner" > "$prefix-run$run.csv" 2> "$prefix-run$run.trace.csv"
    done
    objdump -Cd "$prefix.runner" > "$prefix.assembly.txt"
    python3 - "$prefix" "${flags[@]}" <<'META'
import hashlib,json,platform,subprocess,sys
from pathlib import Path
sources = [*Path('src').rglob('*.d'), *Path('benchmark').rglob('*.d'), Path('scripts/peg-probe.sh')]
Path(sys.argv[1] + '.metadata.json').write_text(json.dumps(dict(
    compiler=subprocess.check_output(['ldc2','--version'],text=True), flags=sys.argv[2:],
    revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    platform=platform.platform(),cpu=Path('/proc/cpuinfo').read_text(),
    timeoutSeconds=60,memoryLimitBytes=4*1024**3,runs=3,samples=7,iterations=2000,
    stageTiming='diagnostic clock probes; includes clock overhead; no subtraction',
    sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}),indent=2)+'\n')
META
  done
done
