# A03 — Current 1.5× Performance Gate Baseline Report

## 1. Executive Summary & Gate Disposition

- **Milestone:** A03 — Rebuild the current 1.5× gate
- **Gate Status:** **FAIL AT 1.5× TARGET** (93 / 513 observations pass <= 1.5x, 18.1%; 28 / 171 unique cases pass <= 1.5x, 16.4%).
- **Baseline Status at 5.0×:** **PASS AT 5.0×** (512 / 513 observations pass <= 5.0x, 99.8%; 171 / 171 unique cases pass <= 5.0x, 100.0%).
- **Current Median Ratio:** **2.102x** of handwritten D reference (improved from 2.132x in P15 and 2.122x in post-H07).
- **Tail Ratios:** P90 = **3.491x**, P95 = **4.129x**, Worst = **5.182x** (PEGGrammar.Permissive validation run 3 at 5.182x; candidate was 173.8 ns vs reference 33.5 ns).
- **Semantic & Output Parity:** **100% PASS** (all 513 checks match handwritten D acceptance, tokens, spans, AST structure, and hashes byte-for-byte).

## 2. Historical Gate Comparison

| Gate Dataset | Source Revision | Total Checks | <= 1.5x Checks | <= 5.0x Checks | Median Ratio | P90 Ratio | P95 Ratio | Worst Ratio |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| **Post-H07** | `4726c4e` | 513 | 97 (18.9%) | 513 (100.0%) | 2.122x | 3.416x | 4.185x | 4.816x |
| **P15 Release** | `34f475c` | 513 | 84 (16.4%) | 512 (99.8%) | 2.132x | 3.390x | 4.120x | 5.075x |
| **A03 Current HEAD** | `8e9407b` | 513 | 93 (18.1%) | 512 (99.8%) | 2.102x | 3.491x | 4.129x | 5.182x |

## 3. Ratio Distribution & Output Mode Breakdown

```
Current Ratio Distribution (A03 vs Handwritten D):
  [ <= 1.0x ]     ██████████ (55 checks, 10.7%)
  [ 1.0x - 1.5x ] ███████ (38 checks, 7.4%)
  [ 1.5x - 2.0x ] ███████████████████████████ (141 checks, 27.5%)
  [ 2.0x - 3.0x ] ███████████████████████████████████ (184 checks, 35.9%)
  [ 3.0x - 4.0x ] █████████████ (66 checks, 12.9%)
  [ 4.0x - 5.0x ] █████ (28 checks, 5.5%)
  [ > 5.0x ]      ▏ (1 check, 0.2%)
```

### Breakdown by Output Mode

| Output Mode | Total Paired Checks | <= 1.5x Pass | Range 1.5x - 5.0x | Exceeding 5.0x | Median Ratio | Max Ratio |
|---|---|---|---|---|---|---|
| **`validation`** | 171 | 35 (20.5%) | 135 (78.9%) | 1 (0.6%) | 1.991x | 5.182x |
| **`spans`** | 171 | 28 (16.4%) | 143 (83.6%) | 0 (0.0%) | 2.341x | 4.873x |
| **`tree`** | 171 | 30 (17.5%) | 141 (82.5%) | 0 (0.0%) | 2.026x | 4.633x |
| **Total** | **513** | **93 (18.1%)** | **419 (81.7%)** | **1 (0.2%)** | **2.102x** | **5.182x** |

## 4. Per-Unique-Case Breakdown (171 Unique Cases)

Sorted by median performance ratio (worst to best):

| Case Name | Output Mode | Suite | Median Ratio | 95% CI | Runs (r1, r2, r3) | Candidate Latency | Reference Latency |
|---|---|---|---:|---:|---|---:|---:|
| `PEGGrammar.Trailing` | `validation` | `handwritten-workloads` | **4.850x** | ±0.106 | [4.880x, 4.850x, 4.705x] | 170.6 ns | 35.0 ns |
| `PEGGrammar.Permissive` | `validation` | `handwritten-workloads` | **4.797x** | ±0.373 | [4.527x, 4.797x, 5.182x] | 158.5 ns | 33.5 ns |
| `CSV.MultiLine` | `tree` | `handwritten-workloads` | **4.576x** | ±0.055 | [4.633x, 4.576x, 4.536x] | 2561.8 ns | 556.0 ns |
| `CSV.MultiLine` | `spans` | `handwritten-workloads` | **4.535x** | ±0.233 | [4.873x, 4.535x, 4.501x] | 2558.2 ns | 560.0 ns |
| `PEGGrammar.Truncated` | `validation` | `handwritten-workloads` | **4.339x** | ±0.088 | [4.339x, 4.460x, 4.313x] | 189.6 ns | 43.7 ns |
| `PEGGrammar.ManyRules` | `validation` | `handwritten-workloads` | **4.294x** | ±0.033 | [4.294x, 4.338x, 4.282x] | 13865.6 ns | 3232.0 ns |
| `CSV.Flat` | `tree` | `handwritten-workloads` | **4.221x** | ±0.084 | [4.324x, 4.221x, 4.179x] | 21365.0 ns | 5083.6 ns |
| `CSV.Flat` | `spans` | `handwritten-workloads` | **4.166x** | ±0.028 | [4.176x, 4.129x, 4.166x] | 21379.1 ns | 5132.0 ns |
| `PEGGrammar.ManyRules` | `spans` | `handwritten-workloads` | **4.119x** | ±0.040 | [4.166x, 4.097x, 4.119x] | 23274.1 ns | 5648.1 ns |
| `PEGGrammar.Deep` | `validation` | `handwritten-workloads` | **4.112x** | ±0.579 | [4.112x, 3.522x, 4.541x] | 5007.9 ns | 1216.9 ns |
| `PEGGrammar.Medium` | `validation` | `handwritten-workloads` | **3.844x** | ±0.093 | [3.823x, 3.975x, 3.844x] | 2450.2 ns | 637.5 ns |
| `PEGGrammar.Medium` | `spans` | `handwritten-workloads` | **3.817x** | ±0.073 | [3.894x, 3.765x, 3.817x] | 3819.4 ns | 1003.5 ns |
| `PEGGrammar.Deep` | `spans` | `handwritten-workloads` | **3.768x** | ±0.044 | [3.716x, 3.768x, 3.792x] | 10495.9 ns | 2785.5 ns |
| `PEGGrammar.Small` | `validation` | `handwritten-workloads` | **3.714x** | ±0.205 | [3.898x, 3.714x, 3.536x] | 481.5 ns | 128.2 ns |
| `JSON.EscapeHeavy` | `validation` | `json-ambiguity` | **3.513x** | ±0.020 | [3.491x, 3.513x, 3.527x] | 3256.4 ns | 932.5 ns |
| `CSV.MultilineQuoted` | `tree` | `handwritten-workloads` | **3.510x** | ±0.084 | [3.510x, 3.638x, 3.510x] | 285.1 ns | 79.5 ns |
| `PEGGrammar.Permissive` | `spans` | `handwritten-workloads` | **3.499x** | ±0.293 | [3.499x, 3.112x, 3.603x] | 324.5 ns | 93.4 ns |
| `PEGGrammar.Small` | `spans` | `handwritten-workloads` | **3.468x** | ±0.122 | [3.624x, 3.417x, 3.468x] | 812.6 ns | 234.3 ns |
| `PEGGrammar.Trailing` | `spans` | `handwritten-workloads` | **3.421x** | ±0.342 | [3.421x, 2.903x, 3.433x] | 324.3 ns | 94.5 ns |
| `JSON.InvalidTruncated` | `tree` | `json-ambiguity` | **3.375x** | ±0.022 | [3.343x, 3.375x, 3.378x] | 4834.2 ns | 1433.7 ns |
| `CSV.MultilineQuoted` | `spans` | `handwritten-workloads` | **3.366x** | ±0.142 | [3.550x, 3.310x, 3.366x] | 291.8 ns | 84.3 ns |
| `JSON.EscapeHeavy` | `tree` | `json-ambiguity` | **3.364x** | ±0.048 | [3.366x, 3.292x, 3.364x] | 3303.1 ns | 981.9 ns |
| `CSV.SingleLine` | `tree` | `handwritten-workloads` | **3.356x** | ±0.286 | [3.406x, 3.356x, 2.945x] | 315.6 ns | 93.5 ns |
| `JSON.EscapeHeavy` | `spans` | `json-ambiguity` | **3.352x** | ±0.079 | [3.305x, 3.352x, 3.442x] | 3349.2 ns | 999.6 ns |
| `JSON.InvalidTruncated` | `spans` | `json-ambiguity` | **3.293x** | ±0.084 | [3.293x, 3.330x, 3.187x] | 4269.6 ns | 1300.4 ns |
| `CSV.SingleLine` | `spans` | `handwritten-workloads` | **3.286x** | ±0.219 | [3.430x, 3.286x, 3.046x] | 311.1 ns | 94.7 ns |
| `JSON.DeepNesting` | `spans` | `json-ambiguity` | **3.281x** | ±0.138 | [3.281x, 3.478x, 3.257x] | 4265.3 ns | 1295.6 ns |
| `CSV.EmptyQuoted` | `tree` | `handwritten-workloads` | **3.086x** | ±0.116 | [3.086x, 3.191x, 2.986x] | 194.2 ns | 63.9 ns |
| `PEGGrammar.Medium` | `tree` | `handwritten-workloads` | **3.058x** | ±0.068 | [3.150x, 3.037x, 3.058x] | 4435.6 ns | 1441.2 ns |
| `JSON.DeepNesting` | `tree` | `json-ambiguity` | **3.047x** | ±0.014 | [3.067x, 3.046x, 3.047x] | 5007.6 ns | 1642.8 ns |
| `PEGGrammar.ManyRules` | `tree` | `handwritten-workloads` | **3.032x** | ±0.050 | [3.032x, 3.001x, 3.088x] | 29927.2 ns | 9692.6 ns |
| `JSON.InvalidTrailing` | `spans` | `json-ambiguity` | **3.015x** | ±0.224 | [3.098x, 3.015x, 2.722x] | 109.2 ns | 35.9 ns |
| `CSV.EmptyQuoted` | `spans` | `handwritten-workloads` | **2.993x** | ±0.068 | [3.083x, 2.968x, 2.993x] | 182.5 ns | 61.5 ns |
| `PEGGrammar.Truncated` | `spans` | `handwritten-workloads` | **2.973x** | ±0.084 | [2.849x, 2.981x, 2.973x] | 358.0 ns | 120.1 ns |
| `Arithmetic.Truncated` | `validation` | `handwritten-workloads` | **2.931x** | ±0.094 | [2.892x, 3.052x, 2.931x] | 223.5 ns | 76.2 ns |
| `Arithmetic.Small` | `validation` | `handwritten-workloads` | **2.930x** | ±0.317 | [2.478x, 2.990x, 2.930x] | 267.2 ns | 95.3 ns |
| `PEGGrammar.Small` | `tree` | `handwritten-workloads` | **2.870x** | ±0.027 | [2.887x, 2.841x, 2.870x] | 916.0 ns | 319.7 ns |
| `PEGGrammar.Truncated` | `tree` | `handwritten-workloads` | **2.819x** | ±0.049 | [2.819x, 2.788x, 2.873x] | 395.7 ns | 139.7 ns |
| `Arithmetic.Unary` | `validation` | `handwritten-workloads` | **2.790x** | ±0.238 | [2.790x, 2.841x, 2.455x] | 168.0 ns | 59.9 ns |
| `PEGGrammar.Deep` | `tree` | `handwritten-workloads` | **2.771x** | ±0.032 | [2.771x, 2.731x, 2.786x] | 12475.0 ns | 4559.9 ns |
| `CSV.Truncated` | `tree` | `handwritten-workloads` | **2.706x** | ±0.261 | [2.706x, 3.078x, 2.656x] | 157.5 ns | 52.3 ns |
| `PEGGrammar.Permissive` | `tree` | `handwritten-workloads` | **2.687x** | ±0.074 | [2.719x, 2.593x, 2.687x] | 333.9 ns | 126.9 ns |
| `PEGGrammar.Trailing` | `tree` | `handwritten-workloads` | **2.662x** | ±0.139 | [2.600x, 2.837x, 2.662x] | 335.3 ns | 127.0 ns |
| `JSON.InvalidTruncated` | `validation` | `json-ambiguity` | **2.652x** | ±0.021 | [2.649x, 2.683x, 2.652x] | 3069.6 ns | 1157.4 ns |
| `JSON.DeepNesting` | `validation` | `json-ambiguity` | **2.639x** | ±0.057 | [2.629x, 2.639x, 2.721x] | 3064.2 ns | 1160.0 ns |
| `Arithmetic.Nested` | `spans` | `handwritten-workloads` | **2.619x** | ±0.049 | [2.668x, 2.582x, 2.619x] | 1752.4 ns | 666.7 ns |
| `Arithmetic.Flat` | `validation` | `handwritten-workloads` | **2.593x** | ±0.064 | [2.609x, 2.593x, 2.504x] | 21835.1 ns | 8526.4 ns |
| `PEGGrammar.Empty` | `validation` | `handwritten-workloads` | **2.584x** | ±0.042 | [2.627x, 2.584x, 2.553x] | 46.8 ns | 18.1 ns |
| `Arithmetic.Deep` | `validation` | `handwritten-workloads` | **2.570x** | ±0.164 | [2.800x, 2.570x, 2.533x] | 3155.2 ns | 1214.9 ns |
| `Arithmetic.Nested` | `validation` | `handwritten-workloads` | **2.553x** | ±0.056 | [2.516x, 2.614x, 2.553x] | 1182.4 ns | 462.0 ns |
| `CSV.Truncated` | `spans` | `handwritten-workloads` | **2.549x** | ±0.139 | [2.606x, 2.549x, 2.371x] | 142.5 ns | 56.3 ns |
| `Numbers.BinaryInvalid` | `spans` | `handwritten-workloads` | **2.506x** | ±0.097 | [2.433x, 2.603x, 2.506x] | 41.3 ns | 16.3 ns |
| `Arithmetic.Medium` | `spans` | `handwritten-workloads` | **2.501x** | ±0.010 | [2.508x, 2.501x, 2.491x] | 1083.8 ns | 432.1 ns |
| `Numbers.ScientificEmpty` | `spans` | `handwritten-workloads` | **2.471x** | ±0.193 | [2.525x, 2.471x, 2.206x] | 42.9 ns | 17.1 ns |
| `Numbers.ScientificTruncated` | `spans` | `handwritten-workloads` | **2.453x** | ±0.257 | [2.453x, 2.473x, 2.069x] | 40.8 ns | 17.9 ns |
| `Numbers.ScientificEmpty` | `tree` | `handwritten-workloads` | **2.438x** | ±0.517 | [2.570x, 1.720x, 2.438x] | 45.2 ns | 19.1 ns |
| `Arithmetic.Deep` | `spans` | `handwritten-workloads` | **2.425x** | ±0.086 | [2.494x, 2.343x, 2.425x] | 4911.5 ns | 2047.7 ns |
| `PEGGrammar.Empty` | `spans` | `handwritten-workloads` | **2.415x** | ±0.093 | [2.274x, 2.418x, 2.415x] | 73.3 ns | 30.4 ns |
| `Arithmetic.Empty` | `spans` | `handwritten-workloads` | **2.409x** | ±0.177 | [2.279x, 2.592x, 2.409x] | 76.4 ns | 31.2 ns |
| `Arithmetic.Empty` | `validation` | `handwritten-workloads` | **2.406x** | ±0.056 | [2.334x, 2.429x, 2.406x] | 42.8 ns | 17.8 ns |
| `CSV.Flat` | `validation` | `handwritten-workloads` | **2.398x** | ±0.135 | [2.374x, 2.591x, 2.398x] | 2088.5 ns | 876.6 ns |
| `Numbers.ScientificTrailing` | `spans` | `handwritten-workloads` | **2.395x** | ±0.188 | [2.395x, 2.656x, 2.348x] | 42.8 ns | 17.9 ns |
| `Arithmetic.Medium` | `validation` | `handwritten-workloads` | **2.392x** | ±0.172 | [2.601x, 2.305x, 2.392x] | 733.4 ns | 306.6 ns |
| `JSON.InvalidEscape` | `tree` | `json-ambiguity` | **2.378x** | ±0.035 | [2.331x, 2.378x, 2.390x] | 189.3 ns | 79.6 ns |
| `JSON.InvalidEscape` | `validation` | `json-ambiguity` | **2.364x** | ±0.059 | [2.434x, 2.364x, 2.333x] | 109.2 ns | 46.2 ns |
| `Arithmetic.Flat` | `spans` | `handwritten-workloads` | **2.362x** | ±0.010 | [2.362x, 2.353x, 2.370x] | 33329.5 ns | 14061.7 ns |
| `JSON.InvalidEscape` | `spans` | `json-ambiguity` | **2.353x** | ±0.188 | [2.582x, 2.258x, 2.353x] | 190.0 ns | 79.9 ns |
| `Numbers.BinaryInvalid` | `tree` | `handwritten-workloads` | **2.351x** | ±0.524 | [2.548x, 1.666x, 2.351x] | 42.8 ns | 18.8 ns |
| `JSON.InvalidNumber` | `spans` | `json-ambiguity` | **2.341x** | ±0.136 | [2.480x, 2.241x, 2.341x] | 195.2 ns | 84.5 ns |
| `Arithmetic.Small` | `spans` | `handwritten-workloads` | **2.341x** | ±0.099 | [2.341x, 2.196x, 2.355x] | 394.5 ns | 168.7 ns |
| `Arithmetic.Truncated` | `spans` | `handwritten-workloads` | **2.315x** | ±0.165 | [2.221x, 2.506x, 2.315x] | 340.5 ns | 146.2 ns |
| `Numbers.HexaInvalid` | `spans` | `handwritten-workloads` | **2.310x** | ±0.022 | [2.307x, 2.343x, 2.310x] | 37.3 ns | 16.1 ns |
| `JSON.InvalidTrailing` | `tree` | `json-ambiguity` | **2.294x** | ±0.103 | [2.251x, 2.425x, 2.294x] | 153.7 ns | 67.5 ns |
| `Numbers.ScientificTruncated` | `tree` | `handwritten-workloads` | **2.248x** | ±0.539 | [2.248x, 1.488x, 2.365x] | 42.0 ns | 19.0 ns |
| `Arithmetic.Truncated` | `tree` | `handwritten-workloads` | **2.237x** | ±0.048 | [2.256x, 2.174x, 2.237x] | 379.1 ns | 174.2 ns |
| `JSON.InvalidNumber` | `validation` | `json-ambiguity` | **2.236x** | ±0.115 | [2.098x, 2.236x, 2.296x] | 121.3 ns | 53.3 ns |
| `Numbers.HexaInvalid` | `tree` | `handwritten-workloads` | **2.233x** | ±0.503 | [2.294x, 1.497x, 2.233x] | 37.2 ns | 18.2 ns |
| `JSON.Medium` | `tree` | `json-ambiguity` | **2.188x** | ±0.075 | [2.136x, 2.188x, 2.268x] | 2169.6 ns | 991.8 ns |
| `JSON.Medium` | `spans` | `json-ambiguity` | **2.187x** | ±0.125 | [2.364x, 2.161x, 2.187x] | 2226.9 ns | 966.9 ns |
| `CSV.Trailing` | `tree` | `handwritten-workloads` | **2.181x** | ±0.123 | [2.026x, 2.181x, 2.236x] | 106.8 ns | 48.7 ns |
| `JSON.Small` | `spans` | `json-ambiguity` | **2.180x** | ±0.245 | [2.079x, 2.494x, 2.180x] | 500.4 ns | 229.5 ns |
| `Arithmetic.Trailing` | `validation` | `handwritten-workloads` | **2.173x** | ±0.242 | [2.227x, 1.832x, 2.173x] | 111.3 ns | 50.4 ns |
| `JSON.InvalidNumber` | `tree` | `json-ambiguity` | **2.165x** | ±0.147 | [1.968x, 2.214x, 2.165x] | 219.0 ns | 101.7 ns |
| `JSON.Small` | `validation` | `json-ambiguity` | **2.153x** | ±0.252 | [2.261x, 2.153x, 1.833x] | 356.8 ns | 172.1 ns |
| `Numbers.ScientificTrailing` | `tree` | `handwritten-workloads` | **2.118x** | ±0.530 | [2.118x, 1.591x, 2.524x] | 45.0 ns | 21.2 ns |
| `JSON.Medium` | `validation` | `json-ambiguity` | **2.113x** | ±0.038 | [2.149x, 2.113x, 2.081x] | 1602.7 ns | 764.0 ns |
| `Arithmetic.Deep` | `tree` | `handwritten-workloads` | **2.109x** | ±0.030 | [2.109x, 2.125x, 2.074x] | 6738.3 ns | 3214.9 ns |
| `Arithmetic.Unary` | `spans` | `handwritten-workloads` | **2.107x** | ±0.044 | [2.056x, 2.133x, 2.107x] | 260.7 ns | 122.4 ns |
| `CSV.InvalidSpacing` | `spans` | `handwritten-workloads` | **2.092x** | ±0.226 | [2.200x, 2.092x, 1.814x] | 102.2 ns | 49.4 ns |
| `Arithmetic.Small` | `tree` | `handwritten-workloads` | **2.069x** | ±0.171 | [2.069x, 2.167x, 1.870x] | 513.9 ns | 237.9 ns |
| `Arithmetic.Unary` | `tree` | `handwritten-workloads` | **2.068x** | ±0.046 | [2.068x, 2.090x, 2.012x] | 331.7 ns | 158.7 ns |
| `Arithmetic.Medium` | `tree` | `handwritten-workloads` | **2.036x** | ±0.123 | [1.896x, 2.036x, 2.109x] | 1364.6 ns | 678.4 ns |
| `Arithmetic.Nested` | `tree` | `handwritten-workloads` | **2.022x** | ±0.034 | [2.050x, 2.022x, 1.991x] | 2296.7 ns | 1130.9 ns |
| `Numbers.ScientificEmpty` | `validation` | `handwritten-workloads` | **1.995x** | ±0.062 | [1.961x, 1.995x, 2.069x] | 31.3 ns | 15.9 ns |
| `Numbers.ScientificLong` | `validation` | `handwritten-workloads` | **1.994x** | ±0.070 | [2.024x, 1.994x, 1.905x] | 7804.9 ns | 3943.0 ns |
| `Arithmetic.InvalidNumber` | `validation` | `handwritten-workloads` | **1.993x** | ±0.034 | [1.993x, 1.951x, 2.010x] | 66.0 ns | 32.8 ns |
| `JSON.InvalidTrailing` | `validation` | `json-ambiguity` | **1.991x** | ±0.017 | [1.991x, 2.015x, 1.988x] | 75.1 ns | 37.3 ns |
| `CSV.EmptyQuoted` | `validation` | `handwritten-workloads` | **1.991x** | ±0.157 | [1.991x, 1.957x, 2.212x] | 36.5 ns | 18.6 ns |
| `Numbers.HexaLong` | `tree` | `handwritten-workloads` | **1.984x** | ±0.011 | [1.991x, 1.971x, 1.984x] | 3880.3 ns | 1955.8 ns |
| `CSV.LongField` | `spans` | `handwritten-workloads` | **1.979x** | ±0.015 | [1.979x, 1.994x, 1.968x] | 3923.3 ns | 1976.6 ns |
| `CSV.Trailing` | `spans` | `handwritten-workloads` | **1.976x** | ±0.152 | [2.187x, 1.936x, 1.976x] | 105.6 ns | 53.5 ns |
| `Numbers.HexaLong` | `spans` | `handwritten-workloads` | **1.975x** | ±0.013 | [1.975x, 1.974x, 1.995x] | 3912.2 ns | 1977.2 ns |
| `JSON.Small` | `tree` | `json-ambiguity` | **1.966x** | ±0.144 | [1.966x, 2.102x, 1.848x] | 501.9 ns | 245.8 ns |
| `Arithmetic.Trailing` | `spans` | `handwritten-workloads` | **1.959x** | ±0.193 | [1.959x, 2.005x, 1.690x] | 223.7 ns | 116.7 ns |
| `Numbers.Scientific` | `validation` | `handwritten-workloads` | **1.945x** | ±0.134 | [1.945x, 1.748x, 1.961x] | 35.9 ns | 18.3 ns |
| `CSV.Empty` | `tree` | `handwritten-workloads` | **1.902x** | ±0.158 | [1.974x, 1.902x, 1.704x] | 95.0 ns | 49.9 ns |
| `Arithmetic.Flat` | `tree` | `handwritten-workloads` | **1.900x** | ±0.026 | [1.907x, 1.864x, 1.900x] | 41844.3 ns | 22446.0 ns |
| `CSV.Empty` | `spans` | `handwritten-workloads` | **1.889x** | ±0.307 | [1.889x, 1.929x, 1.440x] | 89.8 ns | 47.0 ns |
| `Arithmetic.Trailing` | `tree` | `handwritten-workloads` | **1.876x** | ±0.117 | [1.708x, 1.896x, 1.876x] | 230.6 ns | 127.0 ns |
| `Numbers.Binary` | `validation` | `handwritten-workloads` | **1.850x** | ±0.156 | [1.850x, 1.635x, 1.892x] | 33.3 ns | 18.2 ns |
| `Numbers.BinaryInvalid` | `validation` | `handwritten-workloads` | **1.847x** | ±0.166 | [2.013x, 1.720x, 1.847x] | 29.6 ns | 16.0 ns |
| `Numbers.Scientific` | `tree` | `handwritten-workloads` | **1.828x** | ±0.304 | [1.874x, 1.387x, 1.828x] | 91.2 ns | 49.9 ns |
| `CSV.MultilineQuoted` | `validation` | `handwritten-workloads` | **1.820x** | ±0.082 | [1.859x, 1.820x, 1.719x] | 42.1 ns | 24.0 ns |
| `Arithmetic.Empty` | `tree` | `handwritten-workloads` | **1.791x** | ±0.193 | [1.791x, 1.560x, 1.892x] | 114.4 ns | 65.1 ns |
| `Numbers.Scientific` | `spans` | `handwritten-workloads` | **1.771x** | ±0.017 | [1.779x, 1.750x, 1.771x] | 89.0 ns | 50.3 ns |
| `CSV.InvalidSpacing` | `tree` | `handwritten-workloads` | **1.760x** | ±0.103 | [1.760x, 1.883x, 1.706x] | 101.4 ns | 57.6 ns |
| `Arithmetic.InvalidNumber` | `spans` | `handwritten-workloads` | **1.750x** | ±0.225 | [2.076x, 1.715x, 1.750x] | 134.0 ns | 76.2 ns |
| `CSV.LongTruncated` | `tree` | `handwritten-workloads` | **1.733x** | ±0.007 | [1.733x, 1.726x, 1.738x] | 3421.8 ns | 1982.6 ns |
| `CSV.LongQuoted` | `spans` | `handwritten-workloads` | **1.732x** | ±0.008 | [1.732x, 1.735x, 1.722x] | 3418.1 ns | 1979.8 ns |
| `CSV.LongQuoted` | `tree` | `handwritten-workloads` | **1.730x** | ±0.134 | [1.528x, 1.736x, 1.730x] | 3392.0 ns | 1957.0 ns |
| `CSV.LongTruncated` | `spans` | `handwritten-workloads` | **1.726x** | ±0.000 | [1.726x, 1.726x, 1.726x] | 3398.4 ns | 1969.1 ns |
| `Numbers.ScientificLong` | `tree` | `handwritten-workloads` | **1.725x** | ±0.004 | [1.721x, 1.728x, 1.725x] | 6635.6 ns | 3840.4 ns |
| `CSV.LongQuoted` | `validation` | `handwritten-workloads` | **1.722x** | ±0.016 | [1.722x, 1.711x, 1.739x] | 3378.7 ns | 1946.1 ns |
| `Numbers.HexaLong` | `validation` | `handwritten-workloads` | **1.721x** | ±0.018 | [1.721x, 1.728x, 1.698x] | 3338.4 ns | 1954.1 ns |
| `CSV.LongField` | `tree` | `handwritten-workloads` | **1.720x** | ±0.008 | [1.718x, 1.731x, 1.720x] | 3373.8 ns | 1954.8 ns |
| `CSV.LongField` | `validation` | `handwritten-workloads` | **1.715x** | ±0.010 | [1.715x, 1.730x, 1.715x] | 3335.7 ns | 1944.5 ns |
| `CSV.LongTruncated` | `validation` | `handwritten-workloads` | **1.713x** | ±0.004 | [1.715x, 1.708x, 1.713x] | 3335.8 ns | 1947.5 ns |
| `Numbers.ScientificLong` | `spans` | `handwritten-workloads` | **1.707x** | ±0.016 | [1.707x, 1.693x, 1.722x] | 6692.7 ns | 3885.8 ns |
| `Numbers.Binary` | `spans` | `handwritten-workloads` | **1.690x** | ±0.113 | [1.833x, 1.690x, 1.641x] | 81.2 ns | 48.3 ns |
| `Numbers.ScientificTrailing` | `validation` | `handwritten-workloads` | **1.684x** | ±0.012 | [1.684x, 1.684x, 1.666x] | 29.1 ns | 17.4 ns |
| `Numbers.Binary` | `tree` | `handwritten-workloads` | **1.663x** | ±0.143 | [1.663x, 1.494x, 1.741x] | 81.2 ns | 48.8 ns |
| `Arithmetic.InvalidNumber` | `tree` | `handwritten-workloads` | **1.660x** | ±0.030 | [1.660x, 1.648x, 1.699x] | 155.7 ns | 91.9 ns |
| `Numbers.ScientificTruncated` | `validation` | `handwritten-workloads` | **1.622x** | ±0.104 | [1.622x, 1.558x, 1.739x] | 27.6 ns | 17.7 ns |
| `Numbers.Hexa` | `validation` | `handwritten-workloads` | **1.605x** | ±0.016 | [1.599x, 1.626x, 1.605x] | 31.8 ns | 19.8 ns |
| `CSV.InvalidSpacing` | `validation` | `handwritten-workloads` | **1.550x** | ±0.114 | [1.550x, 1.392x, 1.579x] | 26.1 ns | 16.8 ns |
| `PEGGrammar.Empty` | `tree` | `handwritten-workloads` | **1.546x** | ±0.062 | [1.502x, 1.546x, 1.612x] | 102.7 ns | 68.0 ns |
| `Ambiguous.Invalid` | `tree` | `json-ambiguity` | **1.545x** | ±0.165 | [1.580x, 1.312x, 1.545x] | 321.1 ns | 207.8 ns |
| `CSV.SingleLine` | `validation` | `handwritten-workloads` | **1.545x** | ±0.527 | [1.496x, 2.327x, 1.545x] | 58.5 ns | 37.9 ns |
| `CSV.Trailing` | `validation` | `handwritten-workloads` | **1.545x** | ±0.371 | [1.545x, 2.104x, 1.528x] | 25.5 ns | 16.7 ns |
| `Numbers.Hexa` | `tree` | `handwritten-workloads` | **1.540x** | ±0.158 | [1.540x, 1.322x, 1.584x] | 83.0 ns | 52.7 ns |
| `Numbers.Hexa` | `spans` | `handwritten-workloads` | **1.531x** | ±0.088 | [1.531x, 1.619x, 1.463x] | 86.0 ns | 53.1 ns |
| `Numbers.HexaInvalid` | `validation` | `handwritten-workloads` | **1.523x** | ±0.038 | [1.560x, 1.493x, 1.523x] | 24.4 ns | 16.3 ns |
| `CSV.Empty` | `validation` | `handwritten-workloads` | **1.512x** | ±0.117 | [1.512x, 1.348x, 1.539x] | 23.0 ns | 15.3 ns |
| `CSV.Truncated` | `validation` | `handwritten-workloads` | **1.480x** | ±0.162 | [1.638x, 1.352x, 1.480x] | 32.3 ns | 21.7 ns |
| `Ambiguous.Invalid` | `spans` | `json-ambiguity` | **1.436x** | ±0.184 | [1.336x, 1.654x, 1.436x] | 307.7 ns | 230.2 ns |
| `Ambiguous.Invalid` | `validation` | `json-ambiguity` | **1.402x** | ±0.188 | [1.402x, 1.124x, 1.419x] | 286.5 ns | 202.1 ns |
| `CSV.MultiLine` | `validation` | `handwritten-workloads` | **1.269x** | ±0.214 | [1.197x, 1.555x, 1.269x] | 397.4 ns | 300.5 ns |
| `Ambiguous.First` | `tree` | `json-ambiguity` | **1.089x** | ±0.023 | [1.120x, 1.089x, 1.083x] | 193.4 ns | 178.7 ns |
| `Ambiguous.First` | `spans` | `json-ambiguity` | **1.077x** | ±0.030 | [1.077x, 1.106x, 1.053x] | 194.4 ns | 180.6 ns |
| `JSON.LargeString` | `spans` | `json-ambiguity` | **1.034x** | ±0.016 | [1.034x, 1.057x, 1.032x] | 4068.8 ns | 3943.1 ns |
| `JSON.LargeString` | `tree` | `json-ambiguity` | **1.026x** | ±0.020 | [1.013x, 1.048x, 1.026x] | 4045.4 ns | 3946.9 ns |
| `JSON.WhitespaceHeavy` | `validation` | `json-ambiguity` | **1.012x** | ±0.037 | [1.012x, 1.067x, 1.009x] | 3021.0 ns | 2983.9 ns |
| `Numbers.BinaryLong` | `validation` | `handwritten-workloads` | **1.003x** | ±0.014 | [0.982x, 1.003x, 1.005x] | 3863.7 ns | 3911.1 ns |
| `Ambiguous.First` | `validation` | `json-ambiguity` | **0.979x** | ±0.040 | [0.979x, 0.922x, 0.987x] | 135.7 ns | 137.4 ns |
| `JSON.WhitespaceHeavy` | `tree` | `json-ambiguity` | **0.917x** | ±0.021 | [0.901x, 0.938x, 0.917x] | 2744.1 ns | 2992.2 ns |
| `JSON.LargeString` | `validation` | `json-ambiguity` | **0.911x** | ±0.054 | [0.911x, 0.910x, 0.992x] | 3627.0 ns | 3901.0 ns |
| `JSON.WhitespaceHeavy` | `spans` | `json-ambiguity` | **0.908x** | ±0.009 | [0.913x, 0.897x, 0.908x] | 2725.1 ns | 3000.3 ns |
| `Ambiguous.Retry` | `spans` | `json-ambiguity` | **0.899x** | ±0.067 | [0.931x, 0.817x, 0.899x] | 217.9 ns | 242.5 ns |
| `Arithmetic.LongNumber` | `tree` | `handwritten-workloads` | **0.883x** | ±0.003 | [0.881x, 0.883x, 0.886x] | 3440.2 ns | 3889.1 ns |
| `Arithmetic.LongNumber` | `validation` | `handwritten-workloads` | **0.878x** | ±0.006 | [0.879x, 0.869x, 0.878x] | 3380.0 ns | 3850.6 ns |
| `Arithmetic.LongNumber` | `spans` | `handwritten-workloads` | **0.875x** | ±0.010 | [0.864x, 0.875x, 0.882x] | 3443.5 ns | 3934.1 ns |
| `Numbers.BinaryLong` | `spans` | `handwritten-workloads` | **0.872x** | ±0.007 | [0.876x, 0.872x, 0.864x] | 3387.2 ns | 3883.4 ns |
| `Numbers.BinaryLong` | `tree` | `handwritten-workloads` | **0.865x** | ±0.008 | [0.857x, 0.865x, 0.872x] | 3340.5 ns | 3859.7 ns |
| `PEGGrammar.LongLiteral` | `tree` | `handwritten-workloads` | **0.712x** | ±0.004 | [0.716x, 0.709x, 0.712x] | 4121.0 ns | 5784.0 ns |
| `PEGGrammar.LongTruncated` | `tree` | `handwritten-workloads` | **0.704x** | ±0.006 | [0.705x, 0.696x, 0.704x] | 4093.0 ns | 5812.1 ns |
| `Ambiguous.Retry` | `tree` | `json-ambiguity` | **0.704x** | ±0.046 | [0.704x, 0.691x, 0.767x] | 191.4 ns | 269.6 ns |
| `PEGGrammar.LongLiteral` | `spans` | `handwritten-workloads` | **0.619x** | ±0.001 | [0.618x, 0.620x, 0.619x] | 3595.3 ns | 5803.6 ns |
| `Ambiguous.Retry` | `validation` | `json-ambiguity` | **0.611x** | ±0.109 | [0.611x, 0.750x, 0.565x] | 134.1 ns | 219.0 ns |
| `PEGGrammar.LongTruncated` | `spans` | `handwritten-workloads` | **0.605x** | ±0.019 | [0.578x, 0.610x, 0.605x] | 3531.3 ns | 5840.1 ns |
| `PEGGrammar.LongLiteral` | `validation` | `handwritten-workloads` | **0.600x** | ±0.020 | [0.572x, 0.603x, 0.600x] | 3452.3 ns | 5770.0 ns |
| `PEGGrammar.LongTruncated` | `validation` | `handwritten-workloads` | **0.592x** | ±0.011 | [0.609x, 0.592x, 0.592x] | 3419.3 ns | 5764.6 ns |

## 5. Toolchain & Environment Manifest

- **Source Revision:** `8e9407b990e0a5484f70b978c0cfa4b194a5d9a9`
- **Compiler:** `ldc2`
- **CPU:** `AMD Ryzen 7 PRO 5850U with Radeon Graphics`
- **Platform:** `Linux-7.2.8-2-cachyos-x86_64-with-glibc2.44`
- **Binary Size:** 5102128 bytes (Text: 3146449 bytes)
- **Iterations per Case:** 2000
- **Samples per Measurement:** 7
- **Target Ratio:** 1.5x
- **Raw Gate Data:** [`performance/phase3/A03-gate.json`](file:///home/alex-work/repos/triste/performance/phase3/A03-gate.json)
