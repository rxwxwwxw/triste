#!/usr/bin/env bash
# Differential gate first, then timed gate, then record. Usage: run.sh --baseline | --milestone ID [notes]
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH=/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH
DC=${DC:-ldc2} bash scripts/differential.sh
DC=${DC:-ldc2} python3 scripts/performance_gate.py --output build/performance-run.json || true
python3 performance/scripts/record.py build/performance-run.json "$@"
