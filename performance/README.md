# performance/

Evidence for the ≤1.5× handwritten-D target. Built on the existing equal-output gate
(`scripts/performance_gate.py`, `benchmark/`), which verifies output hashes before timing.

## Run

```bash
export PATH=/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH   # macOS: GNU timeout
DC=ldc2 python3 scripts/performance_gate.py --output build/run.json   # 3 runs x 7 samples
python3 performance/scripts/record.py build/run.json --baseline        # or --milestone ID
python3 -m unittest tests/test_performance_record.py                   # recorder tests
performance/scripts/run.sh --milestone ID --notes TEXT              # differential gate, timing, record
```

`record.py` writes `baselines/<run-id>/` or `milestones/<ID>/<run-id>/` (never overwrites),
appends `trends.csv`, and regenerates `latest.md`. Progress notes go in `progress.md`.

## Backends

`PARSER_BACKEND` (default `combinators`; also `direct`, `ll1`) selects the NPegged backend for the benchmark build. Runs recorded with a
non-default backend carry it in the `kind` column (for example `baseline[direct]`); compare only runs of the same backend.
The current reference is the `direct` baseline.

## Reading results

- `raw.csv`: every sample, ns per parse. `summary.csv`: median/p95 over all pooled samples (21).
- `slowdown_ratio` = npegged median / handwritten median for the same workload+mode; `N/A` when
  no handwritten twin exists (handwritten rows are always `N/A`).
- `correctness.json`: output-digest re-comparison; mismatching workloads are excluded from stats.
- Different output modes (validation/spans/tree) are different workloads.

## Limitations (A1)

Only LDC is baselined (DMD supported via `DC=dmd` but not yet recorded). No peak RSS, no
generated-source/compile-time accounting (A5), no allocation/backtrack metrics (A2).
`workloads.json` family labels are approximate; lex_utf8, failure, pathological and nested_expr
families are not yet covered.
