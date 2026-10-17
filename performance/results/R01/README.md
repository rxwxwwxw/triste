# R01 — recognition scaling

Command: `python3 scripts/recognition-scaling.py performance/results/R01`.

All four backend/memo combinations completed sizes 16–8192, valid and invalid suffixes. There are 3360 timed samples (64 parses each, 21 samples/case across three runs), 160 independent counter samples, and eight source-matched manifests. DMD also compiles and runs the complete fixture without warnings. Each optimized runner has a 60-second deadline and 4 GiB address-space limit. Counter builds are not timing baselines. Shared-machine timing is diagnostic, not promotion evidence.

## Answer

**No measured work counter is superlinear at any tested size.** Invalidation visits, retired entries, lookup/unlink work and successful seed growth are linear; bucket creation occurs once and no existing entry is rehashed. Recognition snapshot bytes are exactly zero in every row. Retained scratch arena bytes are at most linear (constant for direct/selective), subject to slab rounding. This contradicts the historical superlinear recognition diagnosis for these current chain fixtures; it does not establish that arbitrary recursive grammars have linear invalidation. Nested/overlapping heads need R02 evidence.

In these specific grammars, every Expr seed-loop evaluation performs exactly one active Expr lookup (through Sum in the indirect grammar), with no completed memo hits. Thus measured memo_hits = n+1 is also the number of Expr head iterations; all 160 diagnostic rows satisfy that identity. This is a source-derived identity for this fixture, not a generic interpretation of memo_hits. seed_growths counts all successful memo seed improvements, including ordinary rules under full memo; it excludes failed or non-improving terminal iterations.

## Valid-input endpoints

| Backend/memo | Grammar | Terms | Median ns/parse | Visits | Retired | Head iterations | Bucket / unlink visits | Rehashes / entries | Retained bytes |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| combinators/selective | DirectChain | 16 | 481.4 | 16 | 0 | 17 | 17 / 0 | 1 / 0 | 4096 |
| combinators/selective | DirectChain | 1024 | 16845.5 | 1024 | 0 | 1025 | 1025 / 0 | 1 / 0 | 4096 |
| combinators/selective | DirectChain | 8192 | 133365.6 | 8192 | 0 | 8193 | 8193 / 0 | 1 / 0 | 4096 |
| combinators/selective | IndirectChain | 16 | 545.6 | 32 | 16 | 17 | 17 / 16 | 1 / 0 | 4096 |
| combinators/selective | IndirectChain | 1024 | 31305.2 | 2048 | 1024 | 1025 | 1025 / 1024 | 1 / 0 | 86016 |
| combinators/selective | IndirectChain | 8192 | 742920.2 | 16384 | 8192 | 8193 | 8193 / 8192 | 1 / 0 | 659456 |
| combinators/full | DirectChain | 16 | 876.6 | 48 | 16 | 17 | 18 / 16 | 1 / 0 | 4096 |
| combinators/full | DirectChain | 1024 | 32726.9 | 3072 | 1024 | 1025 | 1057 / 1024 | 1 / 0 | 86016 |
| combinators/full | DirectChain | 8192 | 742783.3 | 24576 | 8192 | 8193 | 8449 / 8192 | 1 / 0 | 659456 |
| combinators/full | IndirectChain | 16 | 904.5 | 64 | 32 | 17 | 17 / 32 | 1 / 0 | 4096 |
| combinators/full | IndirectChain | 1024 | 130895.9 | 4096 | 2048 | 1025 | 1057 / 2048 | 1 / 0 | 167936 |
| combinators/full | IndirectChain | 8192 | 1502550.4 | 32768 | 16384 | 8193 | 8449 / 16384 | 1 / 0 | 1318912 |
| direct/selective | DirectChain | 16 | 393.1 | 16 | 0 | 17 | 17 / 0 | 1 / 0 | 4096 |
| direct/selective | DirectChain | 1024 | 17107.4 | 1024 | 0 | 1025 | 1025 / 0 | 1 / 0 | 4096 |
| direct/selective | DirectChain | 8192 | 135935.4 | 8192 | 0 | 8193 | 8193 / 0 | 1 / 0 | 4096 |
| direct/selective | IndirectChain | 16 | 576.7 | 32 | 16 | 17 | 17 / 16 | 1 / 0 | 4096 |
| direct/selective | IndirectChain | 1024 | 32445.4 | 2048 | 1024 | 1025 | 1025 / 1024 | 1 / 0 | 86016 |
| direct/selective | IndirectChain | 8192 | 732007.0 | 16384 | 8192 | 8193 | 8193 / 8192 | 1 / 0 | 659456 |
| direct/full | DirectChain | 16 | 876.8 | 48 | 16 | 17 | 18 / 16 | 1 / 0 | 4096 |
| direct/full | DirectChain | 1024 | 32376.9 | 3072 | 1024 | 1025 | 1057 / 1024 | 1 / 0 | 86016 |
| direct/full | DirectChain | 8192 | 755332.7 | 24576 | 8192 | 8193 | 8449 / 8192 | 1 / 0 | 659456 |
| direct/full | IndirectChain | 16 | 879.2 | 64 | 32 | 17 | 17 / 32 | 1 / 0 | 4096 |
| direct/full | IndirectChain | 1024 | 129698.7 | 4096 | 2048 | 1025 | 1057 / 2048 | 1 / 0 | 167936 |
| direct/full | IndirectChain | 8192 | 1500365.4 | 32768 | 16384 | 8193 | 8449 / 16384 | 1 / 0 | 1318912 |

`summary.csv` retains all lengths, validity cases, requested bytes, allocation counts and other work counters. arena_used is retained malloc-backed scratch arena storage at parse completion (its peak because it never frees mid-parse), not process RSS. All retained output/snapshot costs are absent.

R01 changes no runtime code. The prior uncommitted handwritten benchmark changes are excluded from this milestone and from its commit. Historical F03/F04 artifacts remain untouched. Continue to R02; these chains alone offer no superlinear invalidation penalty to remove.
