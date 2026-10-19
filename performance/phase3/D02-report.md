# D02 — Pure-island deployment decision

Disposition: **KEEP_SPECIALIZED_OPT_IN; NO-GO for broader/default policy.** An exact general finite-budget variant is not established. No parser source, default, guard, accounting rule or public API changed.

## Decision evidence

The source-pinned D01 matrix has 132 active configurations, 234 default-finite untraced controls and 486 traced controls. Every targeted active case has nonzero entries; every guarded case has zero. D01's full exact oracle and DMD/LDC/memory checks passed. `scripts/d02_decision.py` verifies those source/output hashes before producing `D02-decision.json`.

- Ordinary default-limit eligibility is **0%**, even in a feature-enabled binary. `pureIslandAllowed` requires step/depth/memory to equal `size_t.max`, no trace, healthy default-allocated arenas, and unlimited output arena for records.
- The current default gate uses conventional policies and the combinator backend; these measured direct/action pure-entry gains do not demonstrate whole-gate improvement. No new gate score is claimed here.
- Pure entry gains are real in the intended configuration. D01's 128-word Root recognition ratio is about 0.0029 with all selection, but that entry executes no actions and emits no tree. All-selection Root records and full trees remain fallback, and actual action-bearing ActRoot does not get that gain.
- Fallback is not proved free. D01 observed >3% slowdown in all three rounds for 26/234 finite-default configurations and 59/486 tracing configurations. These are descriptive repeatability counts, not adjusted significance claims, but they do not support broader deployment.
- Compiler/binary costs also remain visible: D01 retained per-build CTFE-inclusive wall/RSS and binary size. Those single concurrent-build observations do not prove negligible CTFE cost.

These conditions do not make the feature broadly useful under ordinary policies. Keep its existing compile-time opt-in, explicit eligible entry/output proof and unlimited/no-trace contract.

## Finite-budget feasibility

A finite-budget implementation is not ruled out for every possible restricted grammar. It would be a new accounting algorithm, not removal of the current guard. The current fast and fallback representations perform observably different work:

| Obligation | Current reference fallback | Pure scalar route | Requirement for finite equivalence |
|---|---|---|---|
| Logical steps | Parser/combinator evaluation, memo bookkeeping, diagnostics and records projection | Lowered scanning/direct emission | Exact prefix charges and failure frontier at every quota edge, not one final charge |
| Depth | Logical parser calls plus recursive projection of the fallback tree | Different control structure; scalar output need not reconstruct that tree | Preserve the specified logical depth decisions and partial-failure behavior |
| Parser memory | Diagnostic trees, matches, child arrays, memo data and owned input | Fewer/different allocations | Match reserved-byte/slab decisions, allocation ordering and error propagation |
| Output memory | Projected selected records after tree execution | Direct selected emission when projection is proved | Match order, rollback, parent indices and quota failure points |
| Trace/actions | Full required event/callback behavior | Intermediate work can be omitted only for a proved pure entry | Preserve complete observations; actionful/opaque entry remains fallback |

A current D01 example demonstrates the memory difference without hypothesizing a disabled guard: successful 128-word Root recognition reserves **191580 bytes in 41 allocations** with the feature off, versus **4096 bytes in one allocation** with it on; requested payload is 184352 versus 592 bytes. The fast public call is not universally zero-allocation. Finite-memory decisions cannot be inferred from acceptance/output parity or output length alone.

The unchanged `tests/pure_islands_budget.d` fixture also passes on current DMD and LDC. For input `abc` and step limits 4–10, it asserts that the manually invoked lowered **private body** succeeds while the public reference fallback reports resourceLimit. The private body omits public rule wrappers; its reported four steps are **not** the total work of an active public fast API. This is a component counterexample to borrowing its coarse charge model, not a proposed finite public policy. It also exercises memory/depth, tracing, records and mixed-entry guarded comparisons. Its legacy `Mixed <- Root Act` rule uses a Root containing eoi, so it is not evidence of a successful action-executing workflow; D01's actual ActRoot supplies that coverage.

A restricted finite variant would need an exact reference-work ledger or an equivalent guarded algorithm, including EOF/invalid input, backtracking, all failEnd updates, discarded captures, memo/projection work, slab clamping, owned/borrowed input, output prefixes, and partial allocation failure. An upfront estimate of total work cannot reproduce failure offsets at small remaining budgets. Merely decrementing budgets by bytes or selected nodes is insufficient. Custom allocators and action-driven context/input mutation require their existing barriers or independent proof. Any ledger would also need to show that recreating these obligations leaves a realistic gate-relevant speed benefit.

**Feasibility conclusion:** no general exact finite variant exists in the current implementation or is proved by the supplied evidence. Restricted variants may be technically possible, but require a separate design/proof and native experiment. No finite/default promotion is approved. Do not copy the shared-output C02 counterexample as proof of impossibility for pure islands; the independent pure-island work/allocation differences above establish the obligations for this feature.

## Documented specialized mode

[`docs/PURE_ISLAND_POLICY.md`](../../docs/PURE_ISLAND_POLICY.md) now documents the existing mode rather than inventing a new API:

- Generate the direct backend and compile `NPeggedPureIslands` explicitly.
- Call an entry in the generated recognition or record-entry proof; records additionally require the exact compiled selector and anonymous-name omission.
- Deliberately choose unlimited relevant budgets and no trace. Default-limit callers retain fallback; changing defaults is not part of the recommendation.
- Use `check` or `parseRecords` with matched output and ownership. Complete trees and actual action execution remain reference paths.
- Verify nonzero operations in a separate metrics build; do not infer activation from a compile flag or reuse diagnostic clocks as performance evidence.

The document's complete program is extracted, dfmt-normalized, and compiled/run on both DMD and LDC with metrics. It verifies recognition and root-only owned records really enter the specialization and that an ordinary default-context call has zero entries with matching status/end/failEnd. README and the pure-island section/table in the parser-mode guide now state this contract. Generic resource wording distinguishes quota failure (`resourceLimit`) from allocator failure (`outOfMemory`).

## Legacy P07 probe corrections

Current-source inspection found that `tests/pure_islands_audit.d` and `tests/pure_islands_perf.d` still called their finite default contexts “unbounded.” Both now explicitly set the three context limits and records output limit to `size_t.max` in those named phases. Their selectors also kept the anonymous name, which prevents the record-projection proof. They now omit that name. The performance probe has independent nonzero recognition/records entry assertions in its metrics configuration; a failed assertion at this prerequisite exposed the anonymous-selection problem before this correction.

The audit's hierarchical record selection can still fall back, and its comment says so; unrestricted budgets alone do not prove projection eligibility. The legacy single-batch perf output is retained only as diagnostic smoke evidence. **No D01 timing row was replaced or reinterpreted**, and none of these old probe clocks is a new deployment benchmark. D01's paired, repeated uninstrumented matrix remains the timing evidence.

## Verification and reproduction

```sh
python3 scripts/d02_decision.py
```

Eight warning-free builds/runs passed: DMD/LDC × the documentation program, unchanged budget fixture, repaired eligibility audit and repaired legacy perf probe. Assertions are enabled, functions retain `@nogc nothrow`, and children have a 4 GiB address-space ceiling, 300-second compile timeout and 45-second execution timeout (legacy binaries also have their own alarms). Exact commands, source hashes, binary/transcript hashes and the decision are in `D02-decision.json`; raw output/build/run logs are in `D02/`.

No production parser change, fresh performance gate, sanitizer rerun, src coverage refresh or full staged validation is claimed for this decision/documentation/configuration correction. The D01 oracle and sanitizer evidence remains source-matched to its actual fixture; these legacy probe files were not part of that fixture. Any wider policy remains a separate PR requiring its own exact oracle, guarded controls and complete gate.

D02 is closed with the specialized opt-in policy retained. X07 applicability and E01 remain outstanding; the actual ≤1.5× objective is not declared met.
