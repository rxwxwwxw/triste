# Q2 — Corpora and missing families in the timing runner — COMPLETE

Wired: `benchmark/corpus_index.d` (index parser, strict UTF-8 check, file reader; colocated tests, in
`benchmark/unit_tests.d`), `benchmark/runner.d` (`--corpus-index=PATH`, `--families`), `benchmark/options.d`,
`scripts/performance_gate.py --q2`, `performance/scripts/corpus_index.py` + `performance/corpora/index.tsv`,
`performance/scripts/record.py` (family/label classification, `families.csv`, dashboard table), tests in
`tests/test_corpora.py` and `tests/test_performance_record.py`.

Families added with equal-output handwritten twins (outputs verified across NPegged, handwritten and Pegged before timing):
`JSON.family.lex_utf8.{Multibyte,TruncatedTail,RawInvalidBytes}`, `JSON.family.failure.{FirstByte,LastByte}`,
`JSON.family.pathological.WhitespaceThenError`. `nested_expr`, `pathological` (Ambiguous.*), and `failure` also cover
existing fixtures through name-based classification. Corpora: 45-entry index (4 labels); the 26 near-duplicate
per-milestone real snapshots are excluded, large entries are timed with iterations divided by 16.
A workload without a twin would report `N/A` and be counted as `no_twin` (tested).

Run: `20261020T220009Z-547430000-38e6e00b1` in this directory (LDC 1.43, Apple M1, direct backend, 264 workloads).
On the original 171 workload ids: within 1.5x 99 -> 103 (S2b baseline vs this tree incl. S4, O2, O3), p90 2.04 -> 1.95,
geomean 1.316 -> 1.298, worst 2.71 -> 2.79 (Numbers.ScientificEmpty; the tiny-input cluster is noise-limited).
New families/labels (see families.csv): adversarial JSON is the weakest corpus group (0/3 within target, geomean 1.61), CSV
synthetic 4/12 (geomean 1.31, worst 1.87), real JSON 18/18 (geomean 0.99).
Large (about 260 KB) corpora were present in `build/corpora-large` for this run. DMD: not run (segfaults here).
