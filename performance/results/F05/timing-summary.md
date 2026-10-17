| Backend / memo | Input | Median ns/parse | Setup % | Body % | Teardown % |
|---|---|---:|---:|---:|---:|
| combinators/selective | Permissive | 149.6 | 11.61 | 77.60 | 10.80 |
| combinators/selective | Truncated | 181.6 | 9.69 | 80.54 | 9.76 |
| combinators/selective | Trailing | 157.9 | 11.21 | 78.02 | 10.77 |
| combinators/selective | Deep | 5457.5 | 0.49 | 99.10 | 0.41 |
| combinators/full | Permissive | 460.7 | 5.18 | 89.30 | 5.52 |
| combinators/full | Truncated | 552.2 | 4.49 | 90.72 | 4.79 |
| combinators/full | Trailing | 520.5 | 4.75 | 90.22 | 5.04 |
| combinators/full | Deep | 15855.1 | 0.17 | 99.18 | 0.65 |
| direct/selective | Permissive | 141.9 | 12.92 | 75.00 | 12.08 |
| direct/selective | Truncated | 148.4 | 12.22 | 76.23 | 11.55 |
| direct/selective | Trailing | 150.9 | 12.17 | 76.17 | 11.66 |
| direct/selective | Deep | 4144.6 | 0.65 | 98.75 | 0.61 |
| direct/full | Permissive | 480.2 | 4.72 | 90.35 | 4.94 |
| direct/full | Truncated | 566.4 | 3.96 | 91.74 | 4.30 |
| direct/full | Trailing | 541.7 | 4.14 | 91.26 | 4.60 |
| direct/full | Deep | 16109.5 | 0.16 | 99.26 | 0.59 |
