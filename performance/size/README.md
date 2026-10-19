# A5 generated-code and compile accounting

Run `python3 performance/scripts/size_account.py performance/size/<name>.csv` (LDC, `-O3 -release`).
Columns: generated source bytes/lines, generation seconds (tool run, min of 2), native compile seconds, object bytes,
peak RSS KiB (`/usr/bin/time`), DFA region count, `deterministic` (two generations hash-equal).
Grammars: tiny, arithmetic (3 DFA regions), json (4), synthetic-large (200 rules, 200 DFA regions).

`ldc2-a5.csv` is the current tree (P6 included). Same script on the pre-P6 commit 07315cd:

| grammar | compile s | object bytes | peak RSS KiB |
|---|---|---|---|
| tiny | 0.32 -> 0.32 | 91008 -> 89384 | 125824 -> 127488 |
| arithmetic | 1.21 -> 1.20 | 363872 -> 353712 | 211408 -> 213440 |
| json | 2.03 -> 2.08 | 575336 -> 568128 | 285712 -> 295776 |
| synthetic-large | 24.52 -> 23.49 | 7303824 -> 6831720 | 2848656 -> 2804320 |

So P6's state-code scanner does not increase compile time or object size here. DMD not measured (host dmd is broken).
Single measurements, not repeated; treat <5% differences as noise.
