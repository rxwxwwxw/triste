# R06 complete timing matrix

Ratios below 1 favor the enabled candidate. All timing builds exclude metrics.

| Backend | Memo | Grammar / case | Candidate/reference | Control/reference | Three run ratios |
|---|---|---|---:|---:|---|
| combinators | full | CSV control 12 | 1.072 | 1.097 | 1.089/1.055/1.108 |
| combinators | full | DirectChain flat 2048 | 0.434 | 0.994 | 0.427/0.430/0.439 |
| combinators | full | IndirectChain flat 2048 | 0.424 | 0.987 | 0.418/0.426/0.431 |
| combinators | full | JSON control 27 | 1.246 | 1.238 | 1.272/1.212/1.254 |
| combinators | full | NestedChain siblings 16 | 1.113 | 1.077 | 1.120/1.106/1.112 |
| combinators | full | NestedChain siblings 32 | 1.088 | 1.026 | 1.108/1.090/1.095 |
| combinators | full | NestedChain siblings 512 | 0.292 | 0.973 | 0.311/0.286/0.298 |
| combinators | full | PEG control 12 | 1.065 | 1.067 | 1.078/1.038/1.088 |
| combinators | selective | CSV control 12 | 1.102 | 1.070 | 1.129/1.058/1.107 |
| combinators | selective | DirectChain flat 2048 | 0.388 | 1.004 | 0.383/0.387/0.405 |
| combinators | selective | IndirectChain flat 2048 | 0.404 | 1.012 | 0.397/0.404/0.421 |
| combinators | selective | JSON control 27 | 1.188 | 1.124 | 1.197/1.152/1.190 |
| combinators | selective | NestedChain siblings 16 | 1.029 | 0.982 | 1.028/1.028/1.029 |
| combinators | selective | NestedChain siblings 32 | 0.997 | 0.978 | 0.995/1.026/1.026 |
| combinators | selective | NestedChain siblings 512 | 0.255 | 1.005 | 0.254/0.254/0.267 |
| combinators | selective | PEG control 12 | 1.152 | 1.110 | 1.147/1.146/1.147 |
| direct | full | CSV control 12 | 1.086 | 1.048 | 0.958/1.107/1.099 |
| direct | full | DirectChain flat 2048 | 0.436 | 0.986 | 0.448/0.430/0.440 |
| direct | full | IndirectChain flat 2048 | 0.426 | 0.957 | 0.436/0.430/0.425 |
| direct | full | JSON control 27 | 1.220 | 1.226 | 1.206/1.248/1.251 |
| direct | full | NestedChain siblings 16 | 1.038 | 1.019 | 1.044/1.044/1.020 |
| direct | full | NestedChain siblings 32 | 1.019 | 1.025 | 1.056/1.005/0.977 |
| direct | full | NestedChain siblings 512 | 0.293 | 0.985 | 0.305/0.287/0.295 |
| direct | full | PEG control 12 | 1.096 | 1.107 | 1.063/1.107/1.131 |
| direct | selective | CSV control 12 | 1.069 | 1.095 | 1.087/1.056/1.045 |
| direct | selective | DirectChain flat 2048 | 0.390 | 1.001 | 0.386/0.389/0.408 |
| direct | selective | IndirectChain flat 2048 | 0.400 | 0.973 | 0.399/0.395/0.428 |
| direct | selective | JSON control 27 | 1.050 | 1.070 | 1.029/1.039/1.075 |
| direct | selective | NestedChain siblings 16 | 1.099 | 1.064 | 1.084/1.113/1.087 |
| direct | selective | NestedChain siblings 32 | 1.050 | 1.014 | 1.027/1.087/1.047 |
| direct | selective | NestedChain siblings 512 | 0.264 | 1.006 | 0.258/0.262/0.279 |
| direct | selective | PEG control 12 | 1.092 | 1.114 | 1.090/1.079/1.097 |

## Worst measured cases

- direct/full/all IndirectChain flat 16 valid=0: 1.601× reference, 0.824× compiled-off control.
- direct/full/all IndirectChain flat 16 valid=1: 1.546× reference, 0.819× compiled-off control.
- direct/full/all DirectChain flat 16 valid=0: 1.546× reference, 0.806× compiled-off control.
- direct/full/all DirectChain flat 32 valid=1: 1.517× reference, 0.816× compiled-off control.
- direct/selective/all DirectChain flat 32 valid=0: 1.485× reference, 1.429× compiled-off control.
- direct/selective/all IndirectChain flat 32 valid=1: 1.437× reference, 1.073× compiled-off control.
- combinators/full/root DirectChain flat 16 valid=1: 1.399× reference, 1.235× compiled-off control.
- direct/selective/all DirectChain flat 32 valid=1: 1.358× reference, 1.055× compiled-off control.
- combinators/full/all DirectChain flat 32 valid=0: 1.334× reference, 0.956× compiled-off control.
- direct/full/all DirectChain flat 16 valid=1: 1.284× reference, 0.809× compiled-off control.
- direct/selective/all IndirectChain flat 16 valid=0: 1.267× reference, 1.064× compiled-off control.
- combinators/selective/root JSON control 27 valid=0: 1.264× reference, 0.988× compiled-off control.

## Large-range scaling

Exponents from 512 to 2048 terms; 1 is linear and 2 is quadratic.

| Backend/memo | Grammar | Policy | Snapshot | Replay | Retained | Time |
|---|---|---|---:|---:|---:|---:|
| combinators/selective | DirectChain | reference | 2.00 | 2.00 | 1.99 | 1.89 |
| combinators/selective | DirectChain | candidate | 0.34 | 2.00 | 0.81 | 1.99 |
| combinators/selective | IndirectChain | reference | 2.00 | 2.00 | 1.99 | 1.88 |
| combinators/selective | IndirectChain | candidate | 0.37 | 2.00 | 0.82 | 2.04 |
| combinators/full | DirectChain | reference | 2.00 | 2.00 | 1.98 | 1.89 |
| combinators/full | DirectChain | candidate | 0.34 | 2.00 | 0.83 | 2.00 |
| combinators/full | IndirectChain | reference | 2.00 | 2.00 | 1.99 | 1.90 |
| combinators/full | IndirectChain | candidate | 0.37 | 2.00 | 0.83 | 2.05 |
| direct/selective | DirectChain | reference | 2.00 | 2.00 | 1.99 | 1.91 |
| direct/selective | DirectChain | candidate | 0.34 | 2.00 | 0.81 | 1.98 |
| direct/selective | IndirectChain | reference | 2.00 | 2.00 | 1.99 | 1.91 |
| direct/selective | IndirectChain | candidate | 0.37 | 2.00 | 0.82 | 2.04 |
| direct/full | DirectChain | reference | 2.00 | 2.00 | 1.98 | 1.89 |
| direct/full | DirectChain | candidate | 0.34 | 2.00 | 0.83 | 2.01 |
| direct/full | IndirectChain | reference | 2.00 | 2.00 | 1.99 | 1.91 |
| direct/full | IndirectChain | candidate | 0.37 | 2.00 | 0.83 | 2.06 |
