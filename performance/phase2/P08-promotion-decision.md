# P08 — Explicit Promotion Decision for Pure Islands

## 1. Executive Summary & Policy Decision

- **Milestone:** P08 — Explicit promotion decision for pure islands
- **Decision:** **KEEP `version (NPeggedPureIslands)` AS AN OPT-IN HIGH-PERFORMANCE BACKEND VARIANT.**
- **Promotion Status:** **REJECT DEFAULT PROMOTION.** Do not promote `NPeggedPureIslands` to default compilation policy. The feature remains safely available behind the `-version=NPeggedPureIslands` / `-d-version=NPeggedPureIslands` flag.
- **Core Rationale:**
  1. **Niche Workload Scope:** Pure islands lowering exclusively targets *action-bearing* grammars containing pure sub-rules. Pure grammars (e.g. JSON, CSV) already use direct lowering by default under `ParserBackend.direct`. The vast majority of production grammars without semantic actions see 0% benefit from pure islands.
  2. **Code Generation Footprint:** Default promotion would unconditionally emit dual paths (both direct cursor lowering and reference `treeFallback`) for all qualifying sub-rules in every action-bearing grammar, unnecessarily increasing object code size (+7.4 KB per compilation unit) and CTFE template instantiation overhead for applications that only require full AST or standard combinator parsing.
  3. **Strict Conservative Fallback:** P06 established a single-cycle API-entry guard that diverts budgeted and traced calls to reference `treeFallback`. While this eliminates small-case regressions (down from 1.79× to 1.11–1.14×), the cleanest and most robust engineering posture is to preserve opt-in status, guaranteeing zero risk of behavioral drift or unexpected code generation for general users.

---

## 2. Policy & Workload Matrix

| Workload / Configuration | Default Policy | With `NPeggedPureIslands` | Semantic Parity | Performance Impact |
|---|---|---|---|---|
| **Pure Grammar (JSON/CSV) `check`** | Direct Lowering (0 bytes) | Direct Lowering (0 bytes) | Identical | 1.00× (No difference) |
| **Pure Grammar `parseRecords`** | Direct Emission (Compact) | Direct Emission (Compact) | Identical | 1.00× (No difference) |
| **Action Grammar Pure Entry (Unbounded `check`)** | Reference `treeFallback` (Combinators) | **Direct Pure Island (Lowered)** | **Exact Match** | **~350×–410× Speedup** |
| **Action Grammar Pure Entry (Unbounded `parseRecords`)** | Reference `treeFallback` + projection | **Direct Pure Island (Compact)** | **Exact Match** | **~350×–410× Speedup** |
| **Action Grammar Pure Entry (Finite Budgets)** | Reference `treeFallback` | **Reference `treeFallback` (P06 Guard)** | **Exact Match** | **1.11×–1.14× (+8–10 ns)** |
| **Action Grammar Pure Entry (Tracing Active)** | Reference `treeFallback` | **Reference `treeFallback` (P06 Guard)** | **Exact Match** | **1.00× (Exact Parity)** |
| **Action Grammar Actionful Entry (`ActRoot`)** | Reference `treeFallback` | Reference `treeFallback` | Identical | 1.00× (No difference) |
| **Action Grammar Full Tree (`parse`)** | Reference `treeFallback` | Reference `treeFallback` | Identical | 1.00× (No difference) |

---

## 3. Supported Configurations & Eligibility Rules

When `version (NPeggedPureIslands)` is enabled, the parser applies direct lowered execution strictly when **all** of the following criteria are met:

### 3.1. Static Rule Eligibility Invariants
A rule `r` qualifies as an island (`Candidate.npeggedPureIslandEntries`) if and only if:
1. **`localEffects[r].known == true`:** No external D functions, opaque stubs, or unanalyzed grammar symbols.
2. **`localEffects[r].actionful == false`:** The rule contains no inline semantic actions `{action}` and makes no calls to action-bearing rules.
3. **`analyzed.shareable(roots[r]) == true`:** The rule call graph is completely acyclic and closed (no direct left recursion, indirect left recursion, or mutual recursion cycles).
4. **`recordKinds.length == 0 || islandRecordShape(roots[r])`:** In record-generating modes, anonymous non-selected nodes must not introduce AST structural mismatch.

### 3.2. Dynamic API-Entry Guard Conditions
Even if a rule is statically eligible, the direct fast-path is dynamically engaged if and only if:
1. `context.trace is null`: Tracing is inactive (no missing combinator trace callbacks).
2. `context.stepLimit == size_t.max`: No explicit finite execution step limit is set.
3. `context.depthLimit == size_t.max`: No explicit finite recursion depth limit is set.
4. `context.memoryLimit == size_t.max`: No explicit finite memory limit is set on the parse context.
5. `result.arena.limit == size_t.max` and `result.outputArena.limit == size_t.max`: No explicit allocation limit is set on input or output arenas.

If **any** of these conditions fails, `state.pureIslandsEnabled` is set to `false` at API entry ([`check`](file:///home/alex-work/repos/triste/src/npegged/peg.d#L1546), [`parseRecords`](file:///home/alex-work/repos/triste/src/npegged/peg.d#L1637)), and execution immediately routes through reference `treeFallback`.

---

## 4. Fallback Behavior & Stability Guarantees

1. **Deterministic Parity:** Across all 36 configurations tested in [`scripts/pure-islands-check.sh`](file:///home/alex-work/repos/triste/scripts/pure-islands-check.sh) and all budget sweeps in [`tests/pure_islands_budget.d`](file:///home/alex-work/repos/triste/tests/pure_islands_budget.d), candidate output matches reference output bit-for-bit (exact status, AST node count, failEnd, and error offsets).
2. **Zero Allocation:** Unbounded pure island recognition allocates 0 bytes on the arena and 0 GC heap bytes (`@nogc nothrow`).
3. **Rollback & Maintenance Mandate:** If any semantic discrepancy between direct lowered pure islands and reference `treeFallback` is discovered in the future, the fast path must be immediately disarmed for that rule shape via `islands[i] = false` or the P06 API guard, preserving reference parser correctness over speed.

---

## 5. Conclusion & Action Items

- The pure islands optimization lane is **formally closed**.
- All experimental code, benchmarks, documentation, and regression tests are integrated and version-guarded.
- Users desiring maximum throughput on pure sub-rules within action grammars may pass `-d-version=NPeggedPureIslands` (LDC2) or `-version=NPeggedPureIslands` (DMD) to their builds.
- Proceed to Milestone **P09** (Recursive-record output lane).
