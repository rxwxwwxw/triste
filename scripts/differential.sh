#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
compiler=${DC:-ldc2}
mkdir -p build/differential
mapfile -t library < <(rg --files src -g '*.d' | sort)
flags=(-Isrc -I. -unittest -w -checkaction=halt)
case $(basename "$compiler") in
  dmd) flags+=(-defaultlib=druntime -nothrow);;
  ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions);;
  *) echo 'Unsupported compiler' >&2; exit 2;;
esac
ulimit -v 4194304
"$compiler" "${flags[@]}" "${library[@]}" tests/differential.d -of=build/differential/runner
timeout --preserve-status --kill-after=2s 60s build/differential/runner
