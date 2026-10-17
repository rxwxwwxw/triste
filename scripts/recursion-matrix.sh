#!/usr/bin/env bash
# Separate timing and diagnostic binaries; independent executions reuse each build.
set -euo pipefail
cd "$(dirname "$0")/.."
destination=${1:-build/recursion-matrix}
mkdir -p "$destination"
ulimit -v 4194304
for backend in combinators direct; do
  for memoization in selective full; do
    prefix="$destination/$backend-$memoization"
    PARSER_BACKEND=$backend PARSER_MEMOIZATION=$memoization PARSER_METRICS=0 \
      bash scripts/recursion-scaling.sh > "$prefix-run1.csv" 2> "$prefix-build.log"
    for run in 1 2 3; do
      if ((run > 1)); then
        timeout --preserve-status --kill-after=2s 60s build/recursion-scaling/runner > "$prefix-run$run.csv"
      fi
      cp build/recursion-scaling/metadata.json "$prefix-run$run.metadata.json"
      python3 scripts/summarize-recursion.py "$prefix-run$run.csv" > "$prefix-run$run.summary.csv"
    done
    PARSER_BACKEND=$backend PARSER_MEMOIZATION=$memoization PARSER_METRICS=1 \
      bash scripts/recursion-scaling.sh > "$prefix.metrics.csv" 2> "$prefix-metrics-build.log"
    cp build/recursion-scaling/metadata.json "$prefix.metrics.metadata.json"
  done
done
