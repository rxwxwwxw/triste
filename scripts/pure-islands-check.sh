#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/H03
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
read -r -a memos <<< "${MEMOS:-selective full none}"
read -r -a projections <<< "${PROJECTIONS:-all root leaf}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
for compiler in "${compilers[@]}"; do
 for memo in "${memos[@]}"; do
  for projection in "${projections[@]}"; do
   name="$compiler-$memo-$projection"
   for policy in reference candidate; do
    versions=(NPeggedMetrics)
    if [[ "$policy" == candidate ]]; then versions+=(NPeggedPureIslands); fi
    case "$memo" in full) versions+=(NPeggedFullMemo);; none) versions+=(NoMemo);; selective) ;; *) exit 2;; esac
    case "$projection" in root) versions+=(RootOnly);; leaf) versions+=(LeafOnly);; all) ;; *) exit 2;; esac
    flags=(-Isrc -w -unittest -checkaction=halt)
    case "$compiler" in
     dmd) flags+=(-defaultlib=druntime -nothrow); for version in "${versions[@]}"; do flags+=("-version=$version"); done;;
     ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions); for version in "${versions[@]}"; do flags+=("-d-version=$version"); done;;
     *) exit 2;;
    esac
    prefix="build/H03/$name-$policy"
    prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/pure_islands.d "-of=$prefix.runner"
    prlimit --as=4294967296 -- timeout --kill-after=2s 60s "$prefix.runner" --DRT-testmode=run-main > "$prefix.txt" 2> "$prefix.log"
    test "$(tail -1 "$prefix.txt")" = 'pure islands oracle passed'
   done
   cmp "build/H03/$name-reference.txt" "build/H03/$name-candidate.txt"
   echo "$name: exact pure-island oracle passed"
  done
 done
done
