# C02 — Bounded shared-output correctness

Disposition: **COMPLETE — NO-GO for general finite-budget/default activation with the current representation.** Retain all production guards. This milestone adds an integration oracle and a design decision, not a parser optimization. No `src/` file, default limit, accounting rule or activation threshold changed.

## Evidence and scope

Base revision: `dcf6b1bbdef83a856d231b0f2a86f3afc9aa33af`; dirty-worktree test/script hashes and exact compiler commands are in `C02/manifest.json`. `tests/bounded_shared_output.d` is a same-package integration fixture so it can set up the internal record builder. It separates two experiments:

1. Public `parseRecords` always uses the unchanged activation guards. Each finite-budget request is compared with sharing disabled, under the same input ownership, status/frontier, records, limits, allocation and trace obligations.
2. Component-level `RecordBuffer`/`SharedRecordStore` tests place explicit limits on their own scratch arenas to characterize storage differences. They do not parse with a finite-budget fast path. The only direct parser-state shared setup uses explicitly unlimited budgets, and measures logical steps, not latency.

DMD and LDC, each with combinator and direct lowering, pass. All four complete 233-line transcripts are identical. Each binary executes 36 snapshot boundary cases, five unlimited parser-state comparisons, 40 adjacent quota transitions, 150 printed public comparisons plus bisection probes, and one partial allocation-failure case. Assertions remain enabled; every test function is `@nogc nothrow`. The integration main has a 45-second alarm; runners impose a 60-second deadline and 4 GiB address-space ceiling.

## Allocation counterexample

On this 64-bit target, a CompactNode is 32 bytes. Arena charges the requested block size, including its block header and conservative alignment overhead, and may allocate a 4096-byte slab for smaller requests. A flat 128-node snapshot needs `128*32 + 2*sizeof(size_t) + alignof(CompactNode)-1 = 4119` bytes. Sharing first allocates a fragment in a 4096-byte slab, then needs that same 4119-byte leaf block. Its first corresponding shared snapshot therefore needs 8215 bytes.

| Component scratch limit | Flat 128-node snapshot | Shared 128-node snapshot |
|---:|---|---|
| 4118 | resourceLimit | resourceLimit |
| 4119 | succeeds, 4119 reserved | resourceLimit, 4096 already reserved |
| 4120 | succeeds | resourceLimit |
| 8214 | succeeds | resourceLimit |
| 8215 | succeeds | succeeds, 8215 reserved |
| 8216 | succeeds | succeeds |

The oracle asserts the transition itself, restores successful snapshots, and compares every kind/span/parent against the original nodes. It also exercises 127- and 129-node snapshots around both allocation boundaries. A 127-node snapshot stays flat even when sharing is enabled. A 129-node payload needs another 32 bytes, so its corresponding shared allocation still fails at 8215. Snapshot counters and subsequent replay counters distinguish selected policy from operations actually performed.

This is a counterexample to exact finite-memory parity for the current allocation algorithm: the same live records and scratch limit can succeed flat and fail shared. At a successful shared boundary, reported requested bytes also include replay-frame/span bookkeeping performed during the restore; they must not be mistaken for leaf-copy bytes alone.

The opposite direction appears after reuse becomes worthwhile. Unlimited component parser observations:

| Terms | Flat scratch reserved | Shared scratch reserved | Flat/shared logical steps | Shared snapshots/replays |
|---:|---:|---:|---:|---:|
| 63 | 167936 | 167936 | 575 / 575 | 0 / 0 |
| 64 | 172032 | 172032 | 584 / 584 | 0 / 0 |
| 65 | 176183 | 180279 | 593 / 593 | 1 / 2 |
| 128 | 566720 | 205390 | 1160 / 1160 | 64 / 65 |
| 129 | 574967 | 205390 | 1169 / 1169 | 65 / 66 |

At the first shared snapshot there is an extra metadata cost; later sharing substantially reduces retained snapshot storage. Charging only payload bytes, assuming a fixed saving per node, or comparing only final output length would hide both behaviors. These are resource diagnostics, not timing or Amdahl fractions. C01 separately measured unchanged replay materialization bytes despite reduced snapshot copying.

## Step, depth and output boundaries

For each of the five input sizes and both ownership modes, the oracle brackets an **adjacent failure/success transition** for steps, depth, parser memory and output memory. It tests one below, at and one above the transition. The bracketing search preserves an observed failing lower point and successful upper point; it does not assume global monotonicity or call the result a global minimum, because arena slab clamping can change allocation shapes as the budget varies.

Representative success boundaries (both ownership modes; complete rows are retained):

| Input bytes / terms | Steps | Depth | Parser-memory bytes | Output-memory bytes |
|---|---:|---:|---:|---:|
| 125 / 63 | 575 | 3 | 167863 | 8215 |
| 127 / 64 | 584 | 3 | 172023 | 16430 |
| 129 / 65 | 593 | 3 | 176183 | 16430 |
| 255 / 128 | 1160 | 3 | 566720 | 32837 |
| 257 / 129 | 1169 | 3 | 574967 | 32837 |

Every finite request has zero shared snapshots, replays, frozen nodes and reused nodes. Against the matched flat reference, exact status/success, end/failEnd, every selected record/parent, both arenas' reserved/requested bytes and allocation counts agree. Separate default-limit, tracing and late-failure controls agree too; trace event sequences are compared exactly. Owned/borrowed input behavior is checked. These finite tests establish the existing guarded fallback, not hypothetical finite activation.

The unlimited component setup observes the actual `State.steps`. Sharing preserves the tested logical tick counts and returns with depth zero. Snapshot copying and shared replay do not themselves call `State.tick`; parser rule/seed operations do. Shared fragment traversal uses an explicit allocated frame stack rather than parser-depth recursion. Therefore:

- Fewer copied bytes do not imply fewer charged parser steps.
- Output tree depth is not the parser call-depth quota: this left-recursive seed-growth fixture has depth boundary 3 even as selected output grows.
- Step/depth accounting is not an observed obstacle for this fixture in the absence of allocation failure. A shared allocation failure can still stop execution earlier, changing subsequent step consumption, failure frontier and side effects.
- Output nodes are materialized through `RecordBuffer.put` in both representations, but allocation ordering, rollback and failure propagation still need a proof before enabling finite output limits. This study does not establish that a finite-output-only variant is impossible; it establishes that the present general activation policy must not be widened on these tests alone.

## Failure and ownership behavior

A deterministic malloc-compatible allocator returns null on the second request during shared freezing. The fragment slab has already been allocated; the leaf allocation fails. The oracle verifies `outOfMemory`, two allocator calls, 4096 bytes still owned by the arena until scope exit, and zero frozen payload bytes. Arena RAII releases the partial operation without manual cleanup. This tests the partial freeze path, not every possible allocator-failure position in every grammar.

Shared allocation schedules differ from flat schedules, so identical real allocator-failure behavior cannot be inferred from logical node parity. Even unbounded parsing may encounter real out-of-memory conditions. Promotion must preserve the error/rollback/lifetime contract at each added allocation site, rather than asserting that an unlimited limit means allocation cannot fail.

The new integration fixture passed ASan/LSan and Valgrind. All sanitizer and Memcheck transcripts match the compiler transcripts. Valgrind reports zero errors and zero definitely, indirectly or possibly lost bytes; 120 bytes remain reachable in druntime. ASan uses a user systemd scope with `MemoryMax=4G` and swap disabled (its shadow mapping cannot run under a 4 GiB address-space cap). Compilation and Memcheck use the normal 4 GiB address-space cap. No full-repository sanitizer or coverage claim is made.

## Dynamic threshold versus static rule selection

The current implementation selects sharing for an eligible parse but still chooses each snapshot's representation using its local node count (`length-checkpoint >= 4096/CompactNode.sizeof`). The same rule crosses that branch as seed growth or selection density changes. At 64 terms the final output has 129 nodes but no shared snapshot; at 65 there is one. Final result length therefore cannot stand in for snapshot size.

A rule-local/static choice could make dispatch more predictable, but it would not remove fragment/replay allocations or make their charged sizes and failure order equal to flat snapshots. Static eligibility proves an applicable grammar/output family, not per-call budget equivalence. A blanket size-based threshold adjustment also cannot fix both the first-fragment overhead and later reuse savings. Keep the existing threshold and opt-in policy.

## Proof obligations and go/no-go

A future finite-budget proposal must supply all of the following before a separate policy PR:

1. An exact definition of the resource contract: requested payload, reserved allocator bytes and allocation failures are distinct. The existing Arena reserves physical block bytes; do not silently replace that with a node-count estimate.
2. Matching budget decisions at each observable allocation/rollback point, including input ownership, metadata, replay stacks/spans, arena slab clamping, near-threshold snapshots, siblings, late failure and partial replay.
3. Sticky resource/OOM status and identical output prefix or discarded-output obligations, end/failEnd, action order and trace events under failures. A changed allocator-call sequence needs explicit fault-injection coverage.
4. Exact step/depth bookkeeping and overflow handling through success, cached failure and resource failure. Do not charge output tree depth as parser call depth or remove ticks to obtain speedup.
5. A defined policy for finite-output-only operation with unlimited scratch, if proposed separately; prove output allocation order and rollback rather than extrapolating from snapshot savings.
6. Compiler, `@nogc nothrow`, ownership/lifetime, sanitizer, differential and gate evidence for the actual new policy. A virtual flat ledger would be additional design work, and would not by itself eliminate extra real allocations or their OOM outcomes.

**Decision:** current representation is not exactly equivalent under ordinary finite-memory accounting. General finite/default activation is **NO-GO**. Step/depth and isolated output-limit possibilities remain unproven special cases, not authorization to drop guards. The public API continues to fall back under any finite limit or trace. No default, limit, accounting or activation change is included.

B04's emitted-policy audit found no selected left-recursive subtree in the default gate. C03's gate-relevance condition therefore remains false; the attractive synthetic gains do not justify promotion.

## Reproduction and retained evidence

```sh
python3 scripts/c02_bounded_shared.py
bash scripts/c02_memory.sh
```

The second command requires a functioning user systemd scope for a real physical-memory ceiling and Valgrind loader symbols (the existing debuginfod cache is used). Exact compiler commands, source/binary/transcript hashes and row schemas are in `C02/manifest.json` and `C02/validation.json`. Raw compiler transcripts, build/run logs, ASan and Memcheck output are retained in `performance/phase3/C02/`.

The four-configuration resource oracle is also wired into `scripts/validate.sh --full`; the full repository pipeline was not rerun for this wiring-only addition.

The new D fixture is formatted with dfmt and compiles warning-free on both compilers. It lives in `tests/` and owns all allocations through Arena lifetimes. No `std.*` import was added. No `src/` edit, performance gate rerun, src coverage refresh or staged hook/commit is claimed for this correctness/design milestone.
