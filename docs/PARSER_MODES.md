# NPegged Parser Modes & Performance Recommendations

This guide provides a decision table and operating manual for selecting the optimal NPegged parser configuration based on grammar structure, output requirements, and performance objectives.

---

## 1. Quick Decision Matrix

| Mode / output obligation | Configuration | Resource / ownership contract | Evidence |
|---|---|---|---|
| Full ParseTree | `parse` or generated context overload; grammar-selected memo policy | Owned input and result Arena; default limits remain finite | Not interchangeable with recognition or compact records |
| Recognition | Explicit `check`; choose backend/memo policy in grammar generation | Borrows input; memoization and conservative action fallback can allocate | No blanket zero-allocation or ≤1.5× promise |
| Compact records | `parseRecords` with the compiled selector | Owns output Arena; `OwnInput=true` copies input by default | Match tags, parents, ownership and failure obligations |
| Shared snapshots (opt-in) | `NPeggedSharedOutput`, eligible selected left recursion, request enabled | All context/output limits explicitly unlimited; no trace | C01 active crossover; C02 rejects wider finite activation |
| Pure islands (opt-in) | `NPeggedPureIslands`, direct action grammar, proved entry/projection | Unlimited applicable limits, no trace, healthy default arenas | D01 active gains and fallback penalties; D02 keeps specialized mode |

The maintained target is **≤1.5× handwritten time with matched work**, not the older 5× ceiling. Ratios depend on source, grammar, input, output and ownership. See the [Phase 3 integrated audit](../performance/phase3/E01-report.md); historical maxima and opt-in synthetic gains are not current default-gate results.

---

## 2. Detailed Configuration Profiles

### 2.1. Full ParseTree Mode (Reference Default)
- **API:**
  ```d
  ParseContext context;
  auto result = Arithmetic(context, "1 + 2 * 3");
  if (result.status == Status.ok) {
      // result.tree is fully constructed
      assert(result.matches == ["1", "+", "2", "*", "3"]);
  }
  ```
- **Characteristics:**
  - Full packrat memoization (`Memoization.yes` by default).
  - Retains all intermediate node names, strings, and child slices.
  - `@nogc nothrow` runtime; all allocations reside in `result.arena`.
- **When to choose:** You require a classic full parse tree with string matches and child node navigation, or are developing and debugging a new grammar.

---

### 2.2. Selective Recognition (`check`)
- **API:**
  ```d
  ParseContext context;
  auto result = check!(Arithmetic.opCall)(context, "1 + 2 * 3");
  if (result.successful) {
      assert(result.end == 9);
  }
  ```
- **Characteristics:**
  - Recognition does not expose a tree; conservative action handling may still construct one internally.
  - Eligible character classes/repetitions can use scanners; generated backend and semantic guards determine the path.
  - Allocation depends on memoization, grammar and fallback; do not infer zero allocation from the API name or selective policy alone.
- **When to choose:** Validating whether input conforms to a grammar without constructing an in-memory representation.

---

### 2.3. Compact Records Mode (`parseRecords`)
- **API:**
  ```d
  uint selectNodes(string name) @nogc nothrow pure {
      if (name == "Arithmetic.Sum") return 1;
      if (name == "Arithmetic.Number") return 2;
      return uint.max; // Omit other rules
  }

  ParseContext context;
  auto result = parseRecords!(Arithmetic.opCall, selectNodes)(context, "1 + 2 * 3");
  if (result.successful) {
      foreach (node; result.nodes) {
          printf("Kind: %u, [%llu .. %llu], Parent: %llu\n",
                 node.kind, cast(ulong)node.begin, cast(ulong)node.end, cast(ulong)node.parent);
      }
  }
  ```
- **Characteristics:**
  - Produces a flat preorder array of `CompactNode` structures (32 bytes on the measured 64-bit target).
  - The compiled selector determines retained rule records; fallback may still perform intermediate work.
  - Zero garbage collection allocations; output slice is borrowed from `result.outputArena`.
  - `NPeggedFlatSpecialization` is a separate opt-in shared-output specialization. Neither zero overhead nor a universal handwritten ratio is established by the compile flag.
- **When to choose:** Compiling languages, building high-performance parsers, or extracting structured data from large files (JSON, CSV, logs).

---

### 2.4. Shared Output for Left Recursion (`NPeggedSharedOutput`)

Compile `NPeggedSharedOutput` and generate the grammar with its actual selector. Eligibility requires a selected left-recursive subtree and the existing grammar restrictions. `NPeggedFlatSpecialization` is optional, not a substitute for activation proof.

For a deliberately unlimited opt-in caller:

```d
ParseContext context;
context.sharedOutput = true;
context.stepLimit = context.depthLimit = context.memoryLimit = size_t.max;
auto result = parseRecords!(RecursiveGrammar.opCall, selector)(context, deepInput, size_t.max);
```

Ordinary default context and output limits are finite and select flat fallback. Tracing also selects fallback. Shared mode selection does not prove that a particular snapshot crossed the 4096-byte threshold; verify nonzero snapshot/replay counters separately from native timing.

[C01](../performance/phase3/C01-report.md) measured about 0.39–0.41× flat latency for dense successful 2048-term synthetic chains, with matched owned input/output and actual activation. This is not a handwritten ratio or a default-gate improvement. Snapshot copying shrinks; replay still materializes records and can remain quadratic in these chains. Small, root-only, ineligible and finite controls do not establish free overhead.

The former P09 2.16×/depth-64 and P13 threshold claims used inactive configurations and must not be reused. [C02](../performance/phase3/C02-report.md) demonstrates incompatible finite-memory decisions with the current representation. Keep budgets/defaults/thresholds unchanged; [C03](../performance/phase3/C03-report.md) closes the gate-irrelevant optimization branch.

---

### 2.5. Action-Bearing Pure Islands (`NPeggedPureIslands`)

This remains a specialized opt-in mode. The generator must use `ParserBackend.direct` and prove the requested public entry known, action-free and acyclic/shareable. Recognition and compact records have separate entry/projection proofs. Full trees and actual action-bearing entries remain on the reference path.

All step/depth/parser-memory limits must explicitly equal `size_t.max`; records output must also use `size_t.max`. Tracing must be absent, arenas healthy and allocators unchanged. Default ParseContext limits are finite, so default-limit eligibility is **0%**, even in a feature-enabled binary. Do not remove guards or change defaults to obtain the active-path timing.

D01 confirms active gains for eligible cases and also records fallback penalties. Its large pure-Root result is not a general speed promise for action-heavy parsing or full output. See [the specialized mode contract and tested API example](PURE_ISLAND_POLICY.md) and [source-matched measurements](../performance/phase3/D01-report.md). No general exact finite-budget variant has been established.

---

### 2.6. Resource Limits & Tracing
All modes support strict deterministic budgets:
```d
ParseContext context;
context.stepLimit = 100_000;         // Max rule evaluation steps
context.depthLimit = 256;            // Max logical parser call depth
context.memoryLimit = 16 * 1024 * 1024; // 16 MB max arena allocation
context.trace = &traceCallback;      // Event logging callback
```
- A quota failure reports `Status.resourceLimit`; an allocator failure reports `Status.outOfMemory`.
- Error status is sticky and rolls back live output structures deterministically.

---

### 2.7. Diagnostic Instrumentation (`NPeggedMetrics`)
For debugging and performance profiling:
- `-d-version=NPeggedMetrics`: Enables `context.metrics` counters (memo hits, invalidations, snapshot bytes, replay bytes).
- `-d-version=NPeggedScannerMetrics`: Tracks scanner replay frequencies and fallback causes.
- **Note:** Never use diagnostic builds for production timing; counters introduce measurable instrumentation overhead.
