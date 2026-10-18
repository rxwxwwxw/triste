# H08 — direct-code simplification evaluation

## Summary & Findings

H08 conditioned source-level emitter simplification on measured machine-code evidence
showing that LLVM/LDC optimization leaves unnecessary work in the generated parsers.

Following the findings of H05 (which established that `emitEmpty` sequences already compile to
batched six-unit FIRST bitmask tests) and H07 (which eliminated 99.8% of scanner replays in records
mode), inspection of the emitted assembly for direct sequences, repetitions, and scalar calls
demonstrated that:
1. **Loop and Sequence Lowering:** LLVM `-O3` successfully inlines `_cursor_` functions,
   promotes cursor state variables (`_p0`, `_p1`, etc.) to registers, and eliminates intermediate
   tuple structures.
2. **Scalar Dispatch:** Direct scalar calls lower to simple inlined function calls with zero heap
   allocations (`@nogc`).
3. **No Measurable Machine-Code Inefficiency:** No single pattern was found to generate
   unnecessary machine-level branches or memory traffic that was not already addressed by the
   compiler or by H07's failed-scan shortcut.
4. **Compile-Time Guard:** Introducing custom AST rewrites or IR transformations in `grammar.d`
   would increase CTFE memory and compilation time without runtime performance benefits.

## Decision

Per H08's stop criteria ("Split any larger cursor-IR project into independently benchmarked lowering passes;
conditional on machine code evidence"), H08 is concluded with **no further production changes**.
Existing direct code generation remains optimal and verified.
