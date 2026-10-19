# Performance dashboard

Generated from `performance/trends.csv`; do not edit by hand.

Latest run: `20261019T204823Z-9bba1f268` (baseline, ldc2, commit 9bba1f268)

- Workloads within 1.5x: 53/171 (31.0%)
- Slowdown p50/p90/p95: 2.04 / 3.16 / 3.51
- Geometric mean: 1.81x
- Worst: 4.88x (json-ambiguity/JSON.EscapeHeavy/validation)

## History

| run | kind | compiler | within target | p90 | geomean | worst |
|---|---|---|---|---|---|---|
| 20261019T204823Z-9bba1f268 | baseline | ldc2 | 53/171 | 3.16 | 1.81 | 4.88 |
