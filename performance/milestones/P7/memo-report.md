### Arithmetic (n=1793, accepted=1)

| rule | calls | memo hits | hit rate | left-recursive | selective memoizes | recommendation |
|---|---|---|---|---|---|---|
| BenchArithmetic.Space | 1026 | 0 | 0.0% | no | no | leave unmemoized |
| BenchArithmetic.Number | 385 | 0 | 0.0% | no | no | leave unmemoized |
| BenchArithmetic.Primary | 513 | 0 | 0.0% | no | no | leave unmemoized |
| BenchArithmetic.Factor | 385 | 0 | 0.0% | no | no | leave unmemoized |
| BenchArithmetic.Term | 129 | 0 | 0.0% | no | no | leave unmemoized |
| BenchArithmetic.Root | 1 | 0 | 0.0% | no | no | leave unmemoized |

| policy | verdict | arena bytes | work units |
|---|---|---|---|
| no | 1 | 0 | 5901 |
| selective | 1 | 0 | 5901 |
| yes | 1 | 262236 | 5901 |

### LeftExpr (n=33, accepted=1)

| rule | calls | memo hits | hit rate | left-recursive | selective memoizes | recommendation |
|---|---|---|---|---|---|---|
| BenchLeftExpr.Space | 15 | 0 | 0.0% | no | no | leave unmemoized |
| BenchLeftExpr.Expr | 18 | 14 | 77.8% | yes | yes | memoize (required by seed growth) |
| BenchLeftExpr.Term | 44 | 30 | 68.2% | yes | yes | memoize (required by seed growth) |
| BenchLeftExpr.Primary | 30 | 0 | 0.0% | no | no | leave unmemoized |
| BenchLeftExpr.Root | 1 | 0 | 0.0% | no | no | leave unmemoized |

| policy | verdict | arena bytes | work units |
|---|---|---|---|
| no | 0 | 0 | 18446744073709551615 |
| selective | 1 | 4096 | 234 |
| yes | 1 | 8192 | 234 |

### CSV (n=17, accepted=1)

| rule | calls | memo hits | hit rate | left-recursive | selective memoizes | recommendation |
|---|---|---|---|---|---|---|
| BenchCSV.Root | 1 | 0 | 0.0% | no | no | leave unmemoized |

| policy | verdict | arena bytes | work units |
|---|---|---|---|
| no | 1 | 0 | 19 |
| selective | 1 | 0 | 19 |
| yes | 1 | 4096 | 19 |

### JSON (n=47, accepted=1)

| rule | calls | memo hits | hit rate | left-recursive | selective memoizes | recommendation |
|---|---|---|---|---|---|---|
| JSON.Spacing | 27 | 3 | 11.1% | no | no | memoize: repeated (rule, position) calls |
| JSON.String | 5 | 0 | 0.0% | no | no | leave unmemoized |
| JSON.Number | 2 | 0 | 0.0% | no | no | leave unmemoized |
| JSON.Value | 8 | 0 | 0.0% | no | no | leave unmemoized |
| JSON.Null | 1 | 0 | 0.0% | no | no | leave unmemoized |
| JSON.Pair | 4 | 0 | 0.0% | no | no | leave unmemoized |
| JSON.Object | 2 | 0 | 0.0% | no | no | leave unmemoized |
| JSON.Array | 1 | 0 | 0.0% | no | no | leave unmemoized |
| JSON.True | 1 | 0 | 0.0% | no | no | leave unmemoized |
| JSON.Document | 1 | 0 | 0.0% | no | no | leave unmemoized |

| policy | verdict | arena bytes | work units |
|---|---|---|---|
| no | 1 | 0 | 121 |
| selective | 1 | 0 | 121 |
| yes | 1 | 8192 | 118 |

