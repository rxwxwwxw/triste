#!/usr/bin/env bash
# Counter attribution and a separate, explicitly instrumented overhead experiment.
set -euo pipefail
cd "$(dirname "$0")/.."
destination=${1:-build/recursion-metrics}
mkdir -p "$destination"
ulimit -v 4194304
for backend in combinators direct; do
  for memo in selective full; do
    prefix="$destination/$backend-$memo"
    PARSER_BACKEND=$backend PARSER_MEMOIZATION=$memo PARSER_METRICS=1 \
      bash scripts/recursion-scaling.sh > "$prefix.metrics.csv"
    cp build/recursion-scaling/metadata.json "$prefix.metadata.json"
  done
done
for instrumentation in 0 1; do
  prefix="$destination/overhead-$instrumentation"
  PARSER_BACKEND=direct PARSER_MEMOIZATION=selective PARSER_METRICS=$instrumentation PARSER_METRICS_TIMING=1 \
    bash scripts/recursion-scaling.sh > "$prefix-run1.csv"
  cp build/recursion-scaling/metadata.json "$prefix.metadata.json"
  for run in 2 3; do
    timeout --preserve-status --kill-after=2s 60s build/recursion-scaling/runner > "$prefix-run$run.csv"
  done
done
