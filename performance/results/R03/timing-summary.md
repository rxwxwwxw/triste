| Backend | Workload | Size | Reference ns/parse | Control ns/parse | Candidate ns/parse | Candidate/reference |
|---|---|---:|---:|---:|---:|---:|
| combinators | flat chain | 8192 | 114259.72 | 115761.28 | 117816.94 | 1.031 |
| combinators | siblings | 16 | 1263.31 | 1358.81 | 1573.91 | 1.246 |
| combinators | siblings | 128 | 9420.56 | 10101.53 | 26858.91 | 2.851 |
| combinators | siblings | 512 | 37143.44 | 39232.06 | 420268.59 | 11.315 |
| combinators | nesting | 8 | 29858.16 | 31369.12 | 687.53 | 0.023 |
| direct | flat chain | 8192 | 120433.50 | 122304.91 | 130542.00 | 1.084 |
| direct | siblings | 16 | 1263.31 | 1244.84 | 1479.34 | 1.171 |
| direct | siblings | 128 | 8805.28 | 9204.50 | 27228.72 | 3.092 |
| direct | siblings | 512 | 34585.00 | 36884.97 | 418189.12 | 12.092 |
| direct | nesting | 8 | 26877.69 | 29635.41 | 662.19 | 0.025 |
