#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output_dir=${OUTPUT_DIR:-build/H03/oracle}
mkdir -p "$output_dir"
python3 - "$output_dir/sources.json" <<'PYTHON'
import hashlib,json,sys
from pathlib import Path
sources=sorted(Path('src').rglob('*.d'))+[Path('tests/pure_islands.d'),Path('scripts/pure-islands-check.sh')]
Path(sys.argv[1]).write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},indent=2)+'\n')
PYTHON
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
read -r -a memos <<< "${MEMOS:-selective full none}"
read -r -a projections <<< "${PROJECTIONS:-all root leaf anonymous legacy stage}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
for compiler in "${compilers[@]}"; do
 for memo in "${memos[@]}"; do
  for projection in "${projections[@]}"; do
   name="$compiler-$memo-$projection"
   for policy in reference candidate; do
    versions=()
    if [[ "${METRICS:-1}" == 1 ]]; then versions+=(NPeggedMetrics); fi
    if [[ "$policy" == candidate ]]; then versions+=(NPeggedPureIslands); fi
    case "$memo" in full) versions+=(NPeggedFullMemo);; none) versions+=(NoMemo);; selective) ;; *) exit 2;; esac
    case "$projection" in stage) versions+=(StageProjection);; legacy) versions+=(LegacyProjection);; anonymous) versions+=(AnonymousSelected);; root) versions+=(RootOnly);; leaf) versions+=(LeafOnly);; all) ;; *) exit 2;; esac
    flags=(-Isrc -w -unittest -checkaction=halt)
    case "$compiler" in
     dmd) flags+=(-defaultlib=druntime -nothrow); for version in "${versions[@]}"; do flags+=("-version=$version"); done;;
     ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions); for version in "${versions[@]}"; do flags+=("-d-version=$version"); done;;
     *) exit 2;;
    esac
    prefix="$output_dir/$name-$policy"
    prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/pure_islands.d "-of=$prefix.runner"
    prlimit --as=4294967296 -- timeout --kill-after=2s 60s "$prefix.runner" --DRT-testmode=run-main > "$prefix.txt" 2> "$prefix.log"
    test "$(tail -1 "$prefix.txt")" = 'pure islands oracle passed'
   done
   cmp "$output_dir/$name-reference.txt" "$output_dir/$name-candidate.txt"
   echo "$name: exact pure-island oracle passed"
  done
 done
done

python3 - "$output_dir/sources.json" <<'PYTHON'
import hashlib,json,sys
from pathlib import Path
for name,digest in json.loads(Path(sys.argv[1]).read_text()).items():
    assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,('source changed during oracle',name)
PYTHON
