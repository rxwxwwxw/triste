# H07 — exact failed-scan shortcut in records mode

Following H06's diagnostic finding that 2,220 of 2,224 replays across the test suite were
caused by records mode (`Check == 2`) falling back to `Original` on failed token scans,
H07 extends the exact failed-scan shortcut in `dfaToken` to include:
```d
static if (Check == 1 || (Check == 2 && !HasInnerRecords))
```

## Measured Impact & Replay Elimination

Replays across the complete profile suite (41 static rules across 4 cohorts) dropped from
**2,224 down to 4**—a **99.8% reduction**:

| Hotspot Region | H06 Replays | H07 Replays | Reduction |
|---|---:|---:|---|
| `BenchPEG.Sp/_dfa_Sp_1` | 1,820 | 0 | -100% |
| `BenchPEG.TopBoundary/_dfa_TopBoundary` | 160 | 0 | -100% |
| `BenchPEG.ParamGuard/_dfa_ParamGuard` | 104 | 0 | -100% |
| `BenchPEG.Ident/_dfa_Ident` | 56 | 0 | -100% |
| `BenchPEG.ParamAhead/_dfa_ParamAhead` | 56 | 0 | -100% |
| `JSON.String/_dfa_String` | 12 | 4 | -66.7% (only budgetEdge remains) |
| `BenchPEG.SimpleHeader/_dfa_SimpleHeader` | 8 | 0 | -100% |
| `BenchPEG.DefHeaderGuard/_dfa_DefHeaderGuard` | 8 | 0 | -100% |
| **Total Replays** | **2,224** | **4** | **-99.8%** |

The 2,220 `failureDiagnostic` replays were completely eliminated (dropped to 0). The only
remaining 4 replays in the entire suite are tight 64-step `budgetEdge` cases where token scanning
was halted mid-stream due to budget exhaustion.

## Whole-Parser Speed Impact

The shortcut eliminates expensive combinator replays without changing parser semantics or outputs.
Paired spans benchmarks in the performance gate confirm speed improvements across the corpus:

| Benchmark (Spans Mode) | Baseline ns/parse | H07 ns/parse | Speedup Ratio |
|---|---:|---:|---:|
| `JSON.WhitespaceHeavy` | 3,125.3 | 2,730.9 | 0.874× (12.6% faster) |
| `JSON.EscapeHeavy` | 3,428.7 | 3,254.2 | 0.949× (5.1% faster) |
| `JSON.InvalidEscape` | 193.1 | 186.2 | 0.965× |
| `JSON.InvalidNumber` | 196.3 | 192.8 | 0.982× |
| `JSON.LargeString` | 4,082.3 | 4,051.6 | 0.992× |
| `CSV.MultiLine` | 2,581.2 | 2,531.7 | 0.981× |
| `CSV.Flat` | 22,093.9 | 21,751.1 | 0.984× |

## Verification

- **Transcript Invariance:** `scripts/scanner-report-check.sh` runs DMD and LDC2 in both
  ordinary and diagnostic modes across all backends, memoization modes, and budgets.
  All transcripts match byte-for-byte across both compilers.
- **Memory Safety:** `scripts/scanner-report-memory-check.sh` runs clean under AddressSanitizer/
  LeakSanitizer and Valgrind Memcheck with zero memory errors, zero definite leaks, zero
  indirect leaks, and the expected baseline druntime residual.
- **Test Coverage:** All executable modules in `src/` exceed the mandatory 90% threshold for
  both line and branch coverage (`scripts/coverage.sh`).
- **Zero Phobos & Canonical Formatting:** Verified zero `std.*` imports and formatted with `dfmt`.
- **Hotpath Verification:** Marked `@nogc` and verified cleanly under `-vgc`.
