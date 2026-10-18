#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/R06
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
read -r -a backends <<< "${BACKENDS:-combinators direct}"
read -r -a memos <<< "${MEMOS:-selective full}"
read -r -a projections <<< "${PROJECTIONS:-all root leaf}"
mapfile -t library < <(rg --files src -g '*.d' | sort)
for compiler in "${compilers[@]}"; do
 for backend in "${backends[@]}"; do
  for memo in "${memos[@]}"; do
   for projection in "${projections[@]}"; do
    case "$backend" in combinators|direct) ;; *) exit 2;; esac
    case "$memo" in selective|full) ;; *) exit 2;; esac
    case "$projection" in all|root|leaf) ;; *) exit 2;; esac
    name="$compiler-$backend-$memo-$projection"
    if [[ "${METRICS:-1}" == 0 ]]; then name+="-uninstrumented"; fi
    for policy in reference candidate; do
        flags=(-Isrc -w -unittest -checkaction=halt)
        versions=()
        if [[ "${METRICS:-1}" == 1 ]]; then versions+=(NPeggedMetrics); fi
        if [[ "$policy" == candidate ]]; then versions+=(NPeggedSharedOutput); fi
        if [[ "$backend" == direct ]]; then versions+=(NPeggedDirect); fi
        if [[ "$memo" == full ]]; then versions+=(NPeggedFullMemo); fi
        if [[ "$projection" == root ]]; then versions+=(RootOnly); fi
        if [[ "$projection" == leaf ]]; then versions+=(LeafOnly); fi
        case "$compiler" in
            dmd)
                flags+=(-defaultlib=druntime -nothrow)
                for version in "${versions[@]}"; do flags+=("-version=$version"); done;;
            ldc2)
                flags+=(-defaultlib=druntime-ldc -fno-exceptions)
                for version in "${versions[@]}"; do flags+=("-d-version=$version"); done;;
            *) exit 2;;
        esac
        prefix="build/R06/$name-$policy"
        prlimit --as=4294967296 -- timeout --kill-after=2s 300s "$compiler" "${flags[@]}" "${library[@]}" tests/shared_output.d "-of=$prefix.runner"
        prlimit --as=4294967296 -- timeout --kill-after=2s 60s "$prefix.runner" --DRT-testmode=run-main > "$prefix.txt" 2> "$prefix.diagnostic.log"
        if [[ "$(tail -1 "$prefix.txt")" != 'shared output oracle passed' ]]; then exit 1; fi
    done
    cmp "build/R06/$name-reference.txt" "build/R06/$name-candidate.txt"
    echo "$name: exact cross-build record/status/effect/resource transcript passed"
   done
  done
 done
done
