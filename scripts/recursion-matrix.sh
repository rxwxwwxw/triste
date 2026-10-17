#!/usr/bin/env bash
# Sequential runs keep diagnostic instrumentation out of timing builds.
set -euo pipefail
cd "$(dirname "$0")/.."
destination=${1:-build/recursion-matrix}
mkdir -p "$destination"
for backend in combinators direct; do
  for memoization in selective full; do
    prefix="$destination/$backend-$memoization"
    PARSER_BACKEND=$backend PARSER_MEMOIZATION=$memoization PARSER_METRICS=0 \
      bash scripts/recursion-scaling.sh > "$prefix.csv"
    cp build/recursion-scaling/metadata.json "$prefix.metadata.json"
    python3 scripts/summarize-recursion.py "$prefix.csv" > "$prefix.summary.csv"
    PARSER_BACKEND=$backend PARSER_MEMOIZATION=$memoization PARSER_METRICS=1 \
      bash scripts/recursion-scaling.sh > "$prefix.metrics.csv"
    cp build/recursion-scaling/metadata.json "$prefix.metrics.metadata.json"
  done
done
