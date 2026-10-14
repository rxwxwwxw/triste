#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
git rev-parse --show-toplevel >/dev/null || {
 echo 'Hook installation requires a writable Git checkout; this workspace exposes no Git metadata.' >&2
 exit 2
}
configured=$(git config --get core.hooksPath || true)
if [[ -n "$configured" ]]; then
 echo "core.hooksPath is set to '$configured'; refusing to silently replace the existing hook configuration." >&2
 exit 2
fi
target=$(git rev-parse --git-path hooks/pre-commit)
mkdir -p "$(dirname "$target")"
if [[ -f "$target" ]] && ! cmp -s hooks/pre-commit "$target"; then
 [[ ! -e "$target.previous" ]] || { echo 'Existing hook backup already exists' >&2; exit 2; }
 mv "$target" "$target.previous"
fi
install -m 755 hooks/pre-commit "$target"
echo "Installed $target"
