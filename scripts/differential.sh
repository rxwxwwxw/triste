#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
compiler=${DC:-ldc2}
mkdir -p build/differential
library=()
while IFS= read -r -d '' f; do library+=("$f"); done < <(find src -name '*.d' -print0 | sort -z)
if ! command -v timeout >/dev/null 2>&1 && [[ -d /opt/homebrew/opt/coreutils/libexec/gnubin ]]; then export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"; fi
flags=(-Isrc -I. -unittest -w -checkaction=halt)
case $(basename "$compiler") in
  dmd) flags+=(-defaultlib=druntime -nothrow);;
  ldc2) flags+=(-defaultlib=druntime-ldc -fno-exceptions);;
  *) echo 'Unsupported compiler' >&2; exit 2;;
esac
ulimit -v 4194304 2>/dev/null || true
"$compiler" "${flags[@]}" "$@" "${library[@]}" tests/differential.d -of=build/differential/runner
timeout --preserve-status --kill-after=2s 240s build/differential/runner --DRT-testmode=run-main
