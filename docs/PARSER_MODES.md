# NPegged Parser Modes & Performance Recommendations

This guide provides a decision table and operating manual for selecting the optimal NPegged parser configuration based on grammar structure, output requirements, and performance objectives.

---

## 1. Quick Decision Matrix

| Parser Mode | Invocation / Entrypoint | Compile Flags | Output Type | Typical Latency vs Handwritten D | Memory Model | Recommended Use Case |
|---|---|---|---|---|---|---|
| **Full ParseTree (Reference Default)** | `Grammar(context, input)` | *(None / Default)* | Scoped `ParseTree` AST | ~2.5–5.0× | Scoped `Arena` (move-only) | General AST construction, interactive tools, syntax inspection |
| **Selective Recognition** | `check!(Grammar.opCall)(context, input)` | `-d-version=NPeggedDirect` | `CheckResult` (status, end, failEnd) | **1.0–1.5×** | Zero allocation (stack-only) | High-speed syntax validation, protocol framing, security filtering |
| **Compact Records (Flat Fast Path)** | `parseRecords!(Grammar.opCall, selector)(context, input)` | `-d-version=NPeggedDirect` | `CompactNode[]` `(kind, begin, end, parent)` | **1.1–2.0×** | Result-owned `Arena` (POD slice) | Compilers, ETL pipelines, high-throughput tabular/JSON extraction |
| **Recursive Records (Shared Snapshots)** | `parseRecords!(Grammar.opCall, selector)(context, input)` with `context.sharedOutput = true` | `-d-version=NPeggedSharedOutput` `-d-version=NPeggedFlatSpecialization` | `CompactNode[]` | **0.46–1.0×** (Up to **2.16× faster** on deep recursion) | Persistent DAG fragments in `Arena` | Deep left-recursive grammars ($\ge 64$ terms), math expressions, programming languages |
| **Action Grammar Pure Islands** | `check!(Grammar.opCall)` or `parseRecords` | `-d-version=NPeggedPureIslands` | `CheckResult` or `CompactNode[]` | Sub-microsecond on pure sub-rules | Bounded scratch | Action-heavy grammars containing pure tokens/identifiers |

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
  - Evaluates without creating AST nodes or string slices.
  - Automatically lowers ASCII character classes (`[0-9]`, `[a-zA-Z]`) and repetitions to scalar byte scanners.
  - Zero heap or arena allocations when rules are non-recursive or selectively memoized.
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
  - Produces a flat, pre-order array of 32-byte `CompactNode` structures.
  - Statically eliminates unused intermediate rule nodes via `selector`.
  - Zero garbage collection allocations; output slice is borrowed from `result.outputArena`.
  - **Flat Specialization:** When compiled with `NPeggedFlatSpecialization`, non-recursive grammars pay zero overhead for left-recursion infrastructure (matching handwritten D within 1.0–1.4×).
- **When to choose:** Compiling languages, building high-performance parsers, or extracting structured data from large files (JSON, CSV, logs).

---

### 2.4. Shared Output for Left Recursion (`NPeggedSharedOutput`)
- **Compilation Flags:** `-d-version=NPeggedSharedOutput -d-version=NPeggedFlatSpecialization` (LDC2) or `-version=NPeggedSharedOutput -version=NPeggedFlatSpecialization` (DMD).
- **Activation:**
  ```d
  ParseContext context;
  context.sharedOutput = true; // Enable persistent fragment snapshots
  auto result = parseRecords!(RecursiveGrammar.opCall, selector)(context, deepInput);
  ```
- **Performance Characteristics:**
  - Standard flat buffers copy all accumulated nodes during every left-recursive seed growth iteration ($O(N^2)$ byte copies).
  - Shared output stores snapshots as an immutable DAG of `RecordFragment` slices ($O(N)$ byte copies).
  - **Empirical Break-Even Matrix:**
    - Depth $< 16$: Flat mode is slightly faster due to frame setup overhead.
    - Density 0 (no child nodes captured): Flat mode is faster across all depths.
    - Density 1: Crosses over at depth 256–512.
    - Density 2: Crosses over at depth 64 (**0.95× latency**).
    - Density $\ge 4$: Substantial acceleration across all depths ($\le 0.46\times$ latency, **2.16× speedup** at depth 64).
- **Safety & Fallbacks:**
  - Transparently falls back to reference flat copying whenever explicit budgets (`stepLimit`, `depthLimit`, `memoryLimit`, `outputLimit`) or tracing are active.

---

### 2.5. Action-Bearing Pure Islands (`NPeggedPureIslands`)
- **Compilation Flag:** `-d-version=NPeggedPureIslands`.
- **Characteristics:**
  - Grammars containing semantic actions (`{action}`) normally fall back to reference tree mode to preserve capture contexts.
  - `NPeggedPureIslands` proves which sub-rules are pure (no actions, no state mutations) and compiles them into direct scalar code.
  - Execution speedup on pure sub-rules is up to **300–400×** relative to reference tree dispatch.
- **Safety:** Automatically routes through the reference path if explicit parse budgets or tracing are configured.

---

### 2.6. Resource Limits & Tracing
All modes support strict deterministic budgets:
```d
ParseContext context;
context.stepLimit = 100_000;         // Max rule evaluation steps
context.depthLimit = 256;            // Max call stack depth
context.memoryLimit = 16 * 1024 * 1024; // 16 MB max arena allocation
context.trace = &traceCallback;      // Event logging callback
```
- Exceeding any budget sets `result.status` to `Status.resourceLimit` or `Status.outOfMemory`.
- Error status is sticky and rolls back live output structures deterministically.

---

### 2.7. Diagnostic Instrumentation (`NPeggedMetrics`)
For debugging and performance profiling:
- `-d-version=NPeggedMetrics`: Enables `context.metrics` counters (memo hits, invalidations, snapshot bytes, replay bytes).
- `-d-version=NPeggedScannerMetrics`: Tracks scanner replay frequencies and fallback causes.
- **Note:** Never use diagnostic builds for production timing; counters introduce measurable instrumentation overhead.
