# P16 — Publish Default-versus-Fast-Mode Recommendations

## 1. Executive Summary & Disposition

- **Milestone:** P16 — Publish default-versus-fast-mode recommendations
- **Disposition:** **ACCEPT (USER-FACING DOCUMENTATION & DECISION TABLES PUBLISHED)**.
- **Deliverables:**
  1. [`docs/PARSER_MODES.md`](file:///home/alex-work/repos/triste/docs/PARSER_MODES.md): Full reference guide containing quick decision tables, invocation examples, and memory models.
  2. [`README.md`](file:///home/alex-work/repos/triste/README.md): Added Section "Parser modes and recommendations" linking to `docs/PARSER_MODES.md`.
  3. [`CHANGELOG.md`](file:///home/alex-work/repos/triste/CHANGELOG.md): Documented Phase 2 capabilities and performance features.
- **Coverage:** Decision criteria across all 6 core operating modes:
  - Reference Full ParseTree (`Grammar(context, input)`)
  - Selective Recognition (`check!(Grammar.opCall)(context, input)`)
  - Compact Records Flat Path (`parseRecords!(Grammar.opCall, selector)(context, input)`)
  - Recursive Records with Shared Output (`version (NPeggedSharedOutput)` + `context.sharedOutput = true`)
  - Action-Bearing Pure Islands (`version (NPeggedPureIslands)`)
  - Explicit Budgets & Diagnostic Tracing (`stepLimit`, `depthLimit`, `memoryLimit`, `trace`)
- **Compatibility:** Backward compatibility of the default API (`Grammar(context, input)`) is 100% preserved. All fast paths are explicit compile-time or runtime opt-ins with conservative fallbacks.

---

## 2. Decision Table Summary

| Workload Requirement | Recommended Mode | Compile Flags | Invocation |
|---|---|---|---|
| Need full AST with string slices | Reference ParseTree | None | `Grammar(context, input)` |
| Syntax validation only, zero allocation | Selective Recognition | `-d-version=NPeggedDirect` | `check!(Grammar.opCall)(context, input)` |
| Serialization, data extraction (flat grammar) | Compact Records | `-d-version=NPeggedDirect` | `parseRecords!(Grammar.opCall, selector)(context, input)` |
| Deep left recursion ($\ge 64$ terms, dense AST) | Shared Output | `-d-version=NPeggedSharedOutput` | `parseRecords` with `context.sharedOutput = true` |
| Action grammar with pure tokens | Pure Islands | `-d-version=NPeggedPureIslands` | `check` or `parseRecords` |
| Bounded execution / security limits | Any mode + Budgets | Any | Configure `stepLimit`, `memoryLimit`, etc. |

---

## 3. Conclusion & Phase 2 Closeout

Milestone P16 concludes the Phase 2 performance plan. All 16 Phase 2 milestones (P01–P16) have been implemented, tested, documented, and committed.
