#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/recursion-scaling
ulimit -v 4194304
mapfile -t library < <(rg --files src -g '*.d' | sort)
flags=(-Isrc -I. -defaultlib=druntime-ldc -fno-exceptions -O3 -release -w -checkaction=halt)
case ${PARSER_BACKEND:-combinators} in
  combinators) ;;
  direct) flags+=(-d-version=NPeggedDirect);;
  *) echo 'Unsupported PARSER_BACKEND' >&2; exit 2;;
esac
case ${PARSER_MEMOIZATION:-selective} in
  selective) ;;
  full) flags+=(-d-version=NPeggedFullMemo);;
  *) echo 'Unsupported PARSER_MEMOIZATION' >&2; exit 2;;
esac
if [[ ${PARSER_METRICS:-0} == 1 ]]; then flags+=(-d-version=NPeggedMetrics); fi
python3 - "${PARSER_BACKEND:-combinators}" "${PARSER_MEMOIZATION:-selective}" "${flags[@]}" <<'META'
import hashlib, json, platform, subprocess, sys
from pathlib import Path
sources = sorted(Path('src').rglob('*.d')) + [Path('benchmark/recursion_scaling.d'), Path('benchmark/measurement.d'), Path('scripts/recursion-scaling.sh')]
metadata = dict(backend=sys.argv[1], memoization=sys.argv[2], samples=1 if '-d-version=NPeggedMetrics' in sys.argv else 7,
                compiler=subprocess.check_output(['ldc2', '--version'], text=True),
                flags=sys.argv[3:], platform=platform.platform(), revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                timeoutSeconds=60, memoryLimitBytes=4 * 1024**3,
                cpu=Path('/proc/cpuinfo').read_text() if Path('/proc/cpuinfo').exists() else '',
                sources={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
Path('build/recursion-scaling/metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
META
ldc2 "${flags[@]}" "${library[@]}" benchmark/measurement.d benchmark/recursion_scaling.d \
  -of=build/recursion-scaling/runner
timeout --preserve-status --kill-after=2s 60s build/recursion-scaling/runner
