# Recursion foundation matrix

New cohort: input sizes 16,32,64,128,256,512,1024; two recursion shapes;
valid/invalid suffixes; recognition, borrowed records, owned records and full trees;
combinator/direct; full/selective memoization. Each timing group has seven samples
in each of three independent executions. Instrumentation is in separate binaries
and CSV files. Metadata includes exact flags, compiler version, CPU, source hashes,
revision, 60-second runner timeout and 4 GiB address-space limit.

`requested_bytes` and `reserved_bytes` are parser scratch arena payload requests and
retained allocator bytes (`arena.used`). `output_requested_bytes` and
`output_reserved_bytes` are measured independently from the compact output arena;
recognition and tree modes have no separate compact output arena. Allocation calls
include both arenas. Values are captured before disposal; timing includes disposal.
This is retained arena memory, not process RSS. The input fixture is allocated
outside the timed region; owned modes still copy input within parsing.

Historical size-8/512 summaries were not reused as current measurements. Current
CSV and metadata are the source of truth. No optimization or speedup is claimed.

## Current timing summary (valid input)

Each cell is the median of 21 samples across three runs; units are ns/parse.

| Backend / memo | Grammar | Mode | 16 terms | 128 terms | 1024 terms |
|---|---|---|---:|---:|---:|
| combinators/selective | LeftChain | validation | 421 | 2184 | 16681 |
| combinators/selective | LeftChain | records | 2275 | 474162 | 19065249 |
| combinators/selective | LeftChain | owned-records | 1823 | 464654 | 19506348 |
| combinators/selective | LeftChain | tree | 2454 | 828779 | 24535955 |
| combinators/selective | IndirectChain | validation | 621 | 4258 | 31038 |
| combinators/selective | IndirectChain | records | 3967 | 738709 | 57239229 |
| combinators/selective | IndirectChain | owned-records | 3888 | 707380 | 57597464 |
| combinators/selective | IndirectChain | tree | 2525 | 350038 | 25019716 |
| combinators/full | LeftChain | validation | 781 | 4268 | 33463 |
| combinators/full | LeftChain | records | 3216 | 510851 | 19842180 |
| combinators/full | LeftChain | owned-records | 3036 | 503648 | 19949751 |
| combinators/full | LeftChain | tree | 3166 | 896135 | 25560193 |
| combinators/full | IndirectChain | validation | 992 | 6973 | 54753 |
| combinators/full | IndirectChain | records | 4719 | 803822 | 59055240 |
| combinators/full | IndirectChain | owned-records | 4639 | 752735 | 57941715 |
| combinators/full | IndirectChain | tree | 2835 | 374404 | 24547960 |
| direct/selective | LeftChain | validation | 421 | 2165 | 17092 |
| direct/selective | LeftChain | records | 2295 | 476576 | 18773496 |
| direct/selective | LeftChain | owned-records | 2204 | 466127 | 18479553 |
| direct/selective | LeftChain | tree | 2715 | 831685 | 23881144 |
| direct/selective | IndirectChain | validation | 581 | 4108 | 31921 |
| direct/selective | IndirectChain | records | 4178 | 722479 | 56944571 |
| direct/selective | IndirectChain | owned-records | 3937 | 684858 | 56043577 |
| direct/selective | IndirectChain | tree | 2695 | 342895 | 24318236 |
| direct/full | LeftChain | validation | 752 | 4138 | 32822 |
| direct/full | LeftChain | records | 2745 | 500522 | 17940224 |
| direct/full | LeftChain | owned-records | 2716 | 483720 | 17757931 |
| direct/full | LeftChain | tree | 2725 | 856852 | 23749043 |
| direct/full | IndirectChain | validation | 972 | 6873 | 52218 |
| direct/full | IndirectChain | records | 4479 | 774738 | 57118967 |
| direct/full | IndirectChain | owned-records | 4378 | 716599 | 57118386 |
| direct/full | IndirectChain | tree | 2655 | 351241 | 24786324 |

All 9,408 timed rows and 448 diagnostic rows completed without timeout or resource failure.
Timing ran on a shared machine during validation activity; use these measurements for
scaling diagnosis, not optimization promotion. No CPU isolation or frequency pinning was applied.
