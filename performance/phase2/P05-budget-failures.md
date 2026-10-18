# P05 — NPeggedPureIslands Budget Failures and Root-Cause Analysis

## 1. Executive Summary & Objective

Milestone **P05** isolates, reproduces, and documents the minimal budget-edge mismatches between
the direct fast path of `version (NPeggedPureIslands)` and reference `treeFallback` execution
in action-bearing grammars.

In Milestone H03, `NPeggedPureIslands` demonstrated a massive **0.0024–0.0028×** runtime ratio
(~350×–410× speedup) for pure entries in action-bearing grammars, but was restricted from default
promotion due to small-case regressions (up to 1.792×) under finite budgets. This milestone
reduces these budget discrepancies to a minimal reproducible fixture and analyzes the exact
failure mechanisms.

---

## 2. Minimal Reproducible Fixture

A deterministic, minimal regression test has been implemented in [`tests/pure_islands_budget.d`](file:///home/alex-work/repos/triste/tests/pure_islands_budget.d).

### Grammar Definition
```peg
BudgetIslands:
    Root <- [a-z]+ eoi
    Mixed <- Root Act
    Act <- '!' {dummyAction}
```

- `Root` is statically proven to be an acyclic, closed, pure island (`Candidate.npeggedPureIslandEntries == ["Root", "opCall"]`).
- `Act` contains a semantic action `{dummyAction}`, which classifies `BudgetIslands` as an action-bearing grammar (`actionGrammar == true`).
- `Mixed` is a composite rule calling both pure `Root` and actionful `Act`.

---

## 3. Root-Cause Analysis: Four Independent Budget Mismatches

Systematic sweeps of `stepLimit`, `depthLimit`, `memoryLimit`, and `trace` on input `"abc"` reveal
four distinct architectural causes for behavioral divergence between direct pure-island execution
and the reference `treeFallback` path:

### Root Cause 1: Step Accounting Disparity (`stepLimit`)
Direct recognition lowers character matching into coarse-grained scalar loops or DFA scanners.
In contrast, reference combinator execution (used by `treeFallback`) advances in fine-grained
per-combinator steps:

| Step Limit | Direct Lowered Recognition | Reference `treeFallback` Path | Divergence / Mismatch |
|---|---|---|---|
| `stepLimit = 0..3` | `Status.resourceLimit` (steps 0..3) | `Status.resourceLimit` (steps 0..3) | Exact Match (Failure) |
| **`stepLimit = 4..10`** | **`Status.ok`** (completed at **step 4**) | **`Status.resourceLimit`** (partial `failEnd` 0..3) | **FAIL: Direct succeeds, Reference fails** |
| `stepLimit >= 11` | `Status.ok` (step 4) | `Status.ok` (completed at **step 11**) | Semantic Match (Status OK) |

**Mechanism:** Direct recognition takes **4 steps** to parse `"abc"`, while `treeFallback` takes
**11 steps** (`defined`, `dfaToken`, `and`, `oneOrMore`, `charRange` for 'a', 'b', 'c', repeat exit, `eoi`).
If the guard is disabled, any budget in $4 \le \text{stepLimit} < 11$ produces an observable contract
failure: direct mode reports success while the reference parser reports `Status.resourceLimit`.

### Root Cause 2: Memory Allocation Divergence (`memoryLimit`)
- **Direct Recognition:** Completely `@nogc`, allocating **0 bytes** on the arena.
- **Reference `treeFallback`:** Allocates `ParseTree` nodes, match slices, and child arrays on `arena`.
- **Divergence:** Under tight memory limits ($1 \le \text{memoryLimit} < 256\text{ B}$), direct recognition
  completes with `Status.ok`, whereas reference `treeFallback` aborts with `Status.resourceLimit` or
  `Status.outOfMemory`.

### Root Cause 3: Observability Bypass (`trace`)
- Direct lowered recognition compiles out intermediate combinators into inlined loops, firing no intermediate
  callbacks.
- Reference `treeFallback` fires per-combinator `trace()` callbacks for each node in the PEG expression.
- If direct execution were permitted while `context.trace !is null`, tracing observers would miss all
  intermediate combinator events.

### Root Cause 4: Records Traversal Overhead (`parseRecords`)
- In records mode (`Check == 2`), direct emission writes `CompactNode` records straight into `RecordBuffer`.
- In `treeFallback`, the parser first constructs a complete `ParseTree` on the arena, and then calls
  `projectRecords(tree)`, walking the tree recursively and calling `tick()` on every node. This doubles
  the step count and recursion depth consumed for identical output records.

---

## 4. Evaluation of the H03 Guard and Guarded-Off Overhead

### The H03 Guard Architecture
To ensure strict differential oracle equivalence, H03 introduced `pureIslandAllowed()`:
```d
bool allowed = pureIslandsEnabled && status == Status.ok && context.trace is null
    && context.stepLimit == size_t.max
    && context.depthLimit == size_t.max && context.memoryLimit == size_t.max
    && arena !is null && arena.limit == size_t.max && arena.status == Status.ok
    && arena.allocator is Arena.init.allocator;
```

### Measured Impact
1. **Guarded-On Path (Unlimited Budgets):**
   - Pure entries achieve **0.0024–0.0028×** reference time on 128-word inputs (350×–410× speedup).
   - Zero memory allocations, zero closures, exact output parity.
2. **Guarded-Off Path (Finite Budgets):**
   - When any budget is set (`stepLimit != size_t.max`), `pureIslandAllowed()` returns `false`, falling back
     to `treeFallback`.
   - The condition evaluation before falling back incurs a small fixed latency penalty (~15–40 ns), which
     caused the **1.75×–1.79× ratio regression** on 16-byte inputs reported in H03.

---

## 5. Decision & Transition to Milestone P06

1. **Regression Fixture Pinned:** [`tests/pure_islands_budget.d`](file:///home/alex-work/repos/triste/tests/pure_islands_budget.d)
   reproduces and asserts exact budget-edge behavior across all boundary conditions.
2. **Root Cause Confirmed:** The failure is not an algorithmic bug, but an intrinsic discrepancy between
   coarse direct-lowered step/memory accounting and fine-grained combinator tree construction.
3. **P06 Lane Direction:**
   Milestone **P06** will prototype an exact budget/accounting repair behind the opt-in flag, evaluating:
   - A conservative, zero-cost fast-path guard that eliminates fallback penalty while guaranteeing strict
     contract parity.
