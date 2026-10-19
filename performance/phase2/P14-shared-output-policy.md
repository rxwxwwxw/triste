# P14 — R06 Shared-Output Policy Decision & Workload Matrix

## 1. Executive Summary & Policy Decision

- **Milestone:** P14 — Decide R06 policy using a 2×2 workload matrix
- **Decision:** **OPT-IN INDEFINITELY WITH COMPILE-TIME ZERO-OVERHEAD FLAT SPECIALIZATION (HYBRID OPT-IN VARIANT)**.
- **Core Policy Rationale:**
  1. **Do Not Promote to Universal Default:** Empirical evidence from P09 demonstrated that shared output is not universally faster. For sparse node captures (density 0 / Root-only), flat copying has zero inner nodes to copy on rollback, making persistent snapshot allocation pure overhead (+5% to +6% latency penalty across all depths). For density 1, break-even requires depth $\ge 512$. For shallow recursive inputs (depth $\le 16$), initial frame setup costs cause a 5–10% regression. Promoting shared output to the global default would penalize standard shallow-expression workloads.
  2. **Preserve P11 Zero-Overhead Flat Specialization:** For non-recursive grammars (JSON, CSV), `Owner.npeggedSharedOutputEligible` statically proves `sharedStore` is null, constant-folding away all span traversal and skipping stack allocation. Enabling `version (NPeggedSharedOutput)` imposes zero penalty on flat grammars.
  3. **Preserve Conservative Safety Fallbacks:** Under explicit parse budgets (`stepLimit`, `depthLimit`, `memoryLimit`, `outputLimit`) or active tracing, `parseRecords` transparently and conservatively falls back to the reference flat path, ensuring exact deterministic resource limits and sticky error semantics.
  4. **Document High-Performance Variant Usage:** Provide clear trigger guidelines in user documentation: enable `context.sharedOutput = true` for grammars with dense AST capture under left recursion with expected input depth $\ge 64$.

---

## 2. 2×2 Workload Matrix & Performance Profile

The matrix compares **Shared-Off (Reference Flat)** vs **Shared Opt-In** across input recursion profiles and captured node densities:

| Workload Category | Workload & Shape | Shared-Off (Flat) Latency | Shared Opt-In Latency | Ratio (Opt-In / Flat) | Recommended Policy | Rationale |
|---|---|---|---|---|---|---|
| **Provably Flat / Non-Recursive** | JSON / CSV Records | 2,785 ns / 3,616 ns | 2,727 ns / 3,614 ns | **0.98–1.00×** | Safe / Neutral | P11 flat specialization eliminates span loops and stack store. Zero penalty. |
| **Recursive / Shallow or Sparse** | DirectChain depth 16, Density 0–1 | 1,068 ns / 1,441 ns | 879 ns / 1,588 ns | **1.00–1.10×** | **Use Flat** | Snapshot setup (~50–150 ns) dominates shallow recursion; 0 nodes copied by flat. |
| **Recursive / Moderate Depth** | DirectChain depth 64, Density 2 | 108,657 ns | 103,969 ns | **0.9569×** | **Use Shared** | Break-even point; shared snapshots begin outpacing repeated flat copying. |
| **Recursive / Deep & Dense** | DenseChain depth 64–2048, Density 4 | 166,002 ns (d64) | 76,915 ns (d64) | **0.4633× (2.16× speedup)** | **Use Shared** | Quadratic snapshot copying eliminated; linear persistent snapshots dominate. |
| **Mixed Grammar** | Header + Recursive Expression (MixedChain) | 19,522 ns | 18,823 ns | **0.9642×** | **Use Shared** | Header processed via flat path; recursive body accelerated seamlessly. |

---

## 3. Policy Specification & Trigger Conditions

### 3.1. Compilation Mode
- The shared-output subsystem is compiled into the binary via `-d-version=NPeggedSharedOutput` (LDC2) or `-version=NPeggedSharedOutput` (DMD).
- Zero-overhead flat specialization (`version (NPeggedFlatSpecialization)`) is enabled alongside shared output, guaranteeing that flat grammars pay zero runtime penalty.

### 3.2. Runtime Activation Trigger
Users activate shared output explicitly in the parse configuration:
```d
ParseContext context;
context.sharedOutput = true; // Explicit opt-in for left-recursive AST generation
```

### 3.3. Automatic Conservative Fallback
Even when `context.sharedOutput = true` is requested, `parseRecords` automatically and transparently evaluates using the reference flat path if any of the following hold:
1. `!Owner.npeggedSharedOutputEligible`: Grammar has no left-recursive rules with selected child AST records.
2. `context.trace !is null`: Diagnostic tracing requires exact step-by-step visitor logging.
3. `context.stepLimit != size_t.max` or `context.depthLimit != size_t.max`: Step or call depth accounting requires reference evaluation.
4. `context.memoryLimit != size_t.max` or `outputLimit != size_t.max`: Hard byte limits require flat allocation tracking.

### 3.4. Rollback & Invariant Guarantees
- Replays always use bounded arena scratch space with zero garbage collection allocations (`@nogc nothrow`).
- Failed replays deterministically restore `RecordBuffer._length` to the checkpoint.
- Output fragments never escape `CompactResult`; all memory is deterministically reclaimed upon `CompactResult` destruction via RAII.

---

## 4. Final Recommendation & Implementation Roadmap

1. **Keep Opt-In Indefinitely:** Do not promote `NPeggedSharedOutput` to the default configuration. Automatic promotion would violate the Prime Directive (do not regress typical shallow workloads).
2. **Phase 2 Status:** Milestones P09 (crossover measurement), P10 (feasibility analysis), P11 (flat specialization prototype), P12 (safety audit), P13 (fragment tuning closure), and P14 (policy decision) form a complete, empirically validated body of work.
3. **Transition to P15 & P16:** Proceed to Milestone P15 (Full Release Matrix) and Milestone P16 (User Documentation & Decision Tables).
