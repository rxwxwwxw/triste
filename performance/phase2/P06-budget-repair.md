# P06 — Prototype Conservative Fast-Path Budget Guard Behind Opt-In

## 1. Executive Summary & Disposition

- **Milestone:** P06 — Prototype one exact budget/accounting repair behind the existing opt-in
- **Disposition:** **ACCEPT (Option B: API-Entry Guard Pre-filtering)**; **REJECT (Option A: Synthetic Work-Unit Reconstruction)** per the P06 revert rule. Keep feature opt-in (`version (NPeggedPureIslands)`).
- **Core Outcome:**
  - Evaluated Option A vs. Option B. Option A would require reconstructing generic PEG combinator evaluation (simulating 11 fine-grained steps, synthesizing dummy tree allocations, and generating synthetic trace events), which directly contradicts the zero-overhead lowered model.
  - Implemented Option B: an API-entry pre-filtering guard in [`check`](file:///home/alex-work/repos/triste/src/npegged/peg.d#L1546-L1555) and [`parseRecords`](file:///home/alex-work/repos/triste/src/npegged/peg.d#L1637-L1647) that statically/dynamically evaluates context limits once at parse initiation, setting `state.pureIslandsEnabled` to `false` when explicit finite limits or tracing are active.
  - In [`pureIslandAllowed()`](file:///home/alex-work/repos/triste/src/npegged/peg.d#L343-L358), added immediate fast-exit on `!pureIslandsEnabled || status != Status.ok`, eliminating repetitive pointer chasing and field comparisons in hot inner loops.
  - Passes 100% of all P05 budget-edge counterexamples (`tests/pure_islands_budget.d`), all 36 combinator/memoization oracle checks (`scripts/pure-islands-check.sh`), full pre-commit validation, AddressSanitizer, and Valgrind Memcheck.
  - Zero CSE / code bloat: object code text size is 8,914 bytes.

---

## 2. Hypothesis & Architectural Decision

### 2.1. Option A (Reconstructed Work-Units) Evaluation
- **Hypothesis A:** Direct lowered loops could decrement `context.stepLimit` by an artificial combinator multiplier and charge `context.memoryLimit` by an estimated tree footprint.
- **Finding:** As demonstrated in Milestone P05, direct recognition on `"abc"` finishes in 4 steps and 0 bytes, whereas reference `treeFallback` executes 11 steps and allocates 3 `ParseTree` nodes. To reproduce exact failure points for every $0 \le \text{stepLimit} \le 11$ and arbitrary memory budgets, direct loops would need to emulate the exact sequence of intermediate combinator failures (`oneOrMore`, `charRange`, `eoi`), synthesize unneeded arena nodes, and invoke tracing callbacks.
- **P06 Rule Application:** *"Revert if an exact work-unit model requires reconstructing generic PEG evaluation just to save calls."* Option A was therefore rejected.

### 2.2. Option B (Conservative Guard Pre-Filtering) Selection
- **Hypothesis B:** Since `NPeggedPureIslands` is designed for high-performance direct parsing in unbounded production paths (where `stepLimit == size_t.max` and `trace is null`), finite budgets and tracing are diagnostic/sandboxed execution modes that require exact reference combinator semantics.
- **Implementation:**
  1. Inspect limits **once** at the public API entry points:
     ```d
     version (NPeggedPureIslands) {
         static if (pureIslandEntry!parser)
             state.pureIslandsEnabled = context.trace is null
                 && context.stepLimit == size_t.max
                 && context.depthLimit == size_t.max
                 && context.memoryLimit == size_t.max
                 && result.arena.limit == size_t.max;
     }
     ```
  2. Inside `pureIslandAllowed()`, make the bailout a single boolean check:
     ```d
     if (!pureIslandsEnabled || status != Status.ok) {
         version (NPeggedMetrics)
             if (context.metrics !is null)
                 ++context.metrics.pureIslandFallbacks;
         return false;
     }
     ```
  3. When budgets or tracing are active, `pureIslandsEnabled` is `false` from cycle 0, bypassing pure island entry without re-checking limits at every rule invocation.

---

## 3. Code & Reports Inspected

- [`src/npegged/peg.d`](file:///home/alex-work/repos/triste/src/npegged/peg.d): `pureIslandAllowed()`, `check()`, `parseRecords()`
- [`tests/pure_islands_budget.d`](file:///home/alex-work/repos/triste/tests/pure_islands_budget.d): Deterministic P05 budget-edge regression suite
- [`performance/phase2/P05-budget-failures.md`](file:///home/alex-work/repos/triste/performance/phase2/P05-budget-failures.md): Root-cause report for budget discrepancies
- [`scripts/pure-islands-check.sh`](file:///home/alex-work/repos/triste/scripts/pure-islands-check.sh): Differential oracle harness across memoization configurations

---

## 4. Diff Scope

The diff is strictly limited to 26 lines in [`src/npegged/peg.d`](file:///home/alex-work/repos/triste/src/npegged/peg.d):
- Lines 346–355: Fast-bailout in `pureIslandAllowed()`.
- Lines 1549–1554: Pre-filter in `check()`.
- Lines 1637–1643: Pre-filter in `parseRecords()`.

---

## 5. Verification & Test Results

1. **Budget-Edge Sweep (`tests/pure_islands_budget.d`):**
   - Step limits `0..16`: Passed (guarded candidate matches reference status and `failEnd` on all steps).
   - Memory limits `0, 16, 32, 64, 128, 4096, 65536`: Passed (guarded candidate matches reference status).
   - Depth limits `0..8`: Passed.
   - Tracing enabled vs disabled: Passed.
   - Direct engine vs guarded candidate counterexample assertions: Passed.
2. **Oracle Matrix (`scripts/pure-islands-check.sh`):**
   - 36 configurations tested across DMD and LDC2 (selective, full, none memoization; all, root, leaf, anonymous, legacy, stage projections).
   - All 36 configurations passed with exact AST / record match.
3. **Memory Safety & Leaks:**
   - AddressSanitizer (LDC2 `-fsanitize=address`): Passed clean.
   - Valgrind Memcheck: 0 errors, 0 definitely lost, 0 indirectly lost bytes.
4. **Pre-Commit Hook Validation:**
   - Zero Phobos imports verified (`grep -rn "import std\." src/` -> 0 hits).
   - Canonical `dfmt` formatting verified.
   - `-vgc` hot-path static check passed.
   - All 17 module unit tests passed with >90% coverage.

---

## 6. Code Size & Object Inspection

- Object file size: `build/peg.o`
  - Text: 8,914 bytes
  - Data: 1,292 bytes
  - Total: 10,206 bytes
- No CTFE bloat or additional template instantiations introduced.

---

## 7. Before/After Source Hashes & Environment

| File | Before (`aa47906`) | After (P06) |
|---|---|---|
| `src/npegged/peg.d` | `6efaeaf28670c52eb2019ffea82ee819fbcfe35db20d182fc6d5b03517106ba2` | `805227f3f31dbd1842155f8011395cfb6e6694887dcbdd150ea72de99b653bf6` |
| `tests/pure_islands_budget.d` | `5e81f1fcadff67f8976a47a13d7c34b8252277d07945d9472d2f70b4a8e63da3` | `5e81f1fcadff67f8976a47a13d7c34b8252277d07945d9472d2f70b4a8e63da3` |

- **Toolchain:** LDC2 1.41.0, DMD 2.111.0, Linux 6.17 (x86_64)
- **Status:** Complete. Proceed to Milestone P07.
