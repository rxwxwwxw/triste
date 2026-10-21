#!/usr/bin/env bash
# P8 follow-up: directly left-recursive rules run as loops in check mode.
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a compilers <<< "${COMPILERS:-dmd ldc2}"
library=()
while IFS= read -r -d '' f; do library+=("$f"); done < <(find src -name '*.d' -print0 | sort -z)
if ! command -v timeout >/dev/null 2>&1 && [[ -d /opt/homebrew/opt/coreutils/libexec/gnubin ]]; then export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"; fi
mkdir -p build/P8lr
for compiler in "${compilers[@]}"; do
 flags=(-Isrc -I. -w -checkaction=halt)
 case "$compiler" in
  dmd) flags+=(-defaultlib=druntime -nothrow);;
  ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions);;
  *) echo "Unsupported compiler: $compiler" >&2; exit 2;;
 esac
 ulimit -v 4194304 2>/dev/null || true
 timeout --kill-after=2s 600s "$compiler" "${flags[@]}" "${library[@]}" tests/left_recursion.d "-of=build/P8lr/$compiler.runner"
 timeout --kill-after=2s 300s "build/P8lr/$compiler.runner" --DRT-testmode=run-main | tee "build/P8lr/$compiler.txt"
done
