# R05 — isolated immutable record snapshots

This milestone adds an experimental SharedRecordSnapshot/SharedRecordStore API
beside the existing flat RecordSnapshot API. All work counters and their updates
compile out unless NPeggedMetrics is enabled; normal builds statically assert
that these fields are absent. Parser memoization is unchanged:
R06 is the separate integration experiment. All operations are @nogc nothrow and
all allocation belongs to caller-owned RAII arenas.

## Safety boundary

`freeze` is the fallback for arbitrary flat snapshots: it validates parent
indices, copies the entire selected span, normalizes internal parents relative to
that span, and maps external parents to the enclosing replay parent. Later edits
to the input buffer cannot alter the frozen leaf.

`join(left, right, attachment)` creates a constant-size immutable composition.
External roots of the right fragment attach to an earlier left node, or to the
outer replay parent when attachment is size_t.max. Other parent relationships
remain local to their immutable fragments. Clients cannot construct fragment
internals. Composition checks attachment bounds, output-length overflow and
height overflow. It never infers sharing from mutable-buffer identity or presumed
stable prefixes. If a client cannot explicitly compose immutable fragments, it
must freeze the full flat output.

The replay invariant is inductive: a leaf's internal parent offset is strictly
less than its node offset; a composition's right attachment names an already
emitted left node. Moving a fragment changes only its base and external parent,
so every internal edge still names the same logical earlier node. The checked
root length plus destination checkpoint bounds all descendant index additions.
Depth-first replay retains at most one pending right fragment per level, bounded
by the checked stored height. Immutable leaves and links preserve this invariant
across historical versions, without examining mutable parser buffers.

Replay walks the composition iteratively with an arena-backed stack sized by
its checked height. Parent rebasing follows the same rules as RecordBuffer.
Allocation failure, invalid target state and size overflow return false with a
sticky output status and preserve the pre-replay logical length. Snapshot
construction failures return an empty handle plus sticky store status. Existing
handles remain immutable, but their source arenas must outlive every composition
and replay which references them (including cross-store references).

Rollback selects a prior immutable handle. Replacement creates a new handle,
possibly freezing unrelated output; it does not mutate an old version. Tests
exercise both whole-output replacement and nested subtree reuse.

## Evidence

The bounded integration oracle compares every CompactNode field and initialized
record bytes against the existing flat snapshot API. It covers nested external
and internal parent rebasing, multiple sibling roots, rollback and replacement,
256 deterministic compositions from retained historical versions, and finite
output/scratch/store allocation budgets. Colocated units also cover invalid
parents/attachments, overflow and partial replay failure preserving an existing
prefix. DMD, LDC and optimized LDC (-O3 with assertions enabled) emit identical
diagnostic measurement CSVs. Normal DMD/LDC builds run the same equality oracle
without counters or measurement output. Source/compiler hashes and runner settings are pinned in
metadata.json. The initial missing-API compile failure was committed before the
implementation (48d76ec), after R04 (29e6791).

The synthetic deep-growth fixture replaces the outer root at each level and
explicitly reuses its unchanged child. At depth 2048 the flat implementation
freezes **67141632 bytes** cumulatively; the shared implementation freezes
**65536 bytes**, and final replay writes **65536 bytes**. Flat snapshot retention
is 67261591 bytes versus 303104 bytes for immutable fragments, plus 49175 bytes
of replay stack. Both produce the same 2048-node output. These are work/memory
measurements, not parser timing or a claim that all grammars can share output.

Every new root is still copied once. Composition allocation and stack overhead
are linear in this fixture. A highly unbalanced composition requires a stack
linear in nesting depth. Repeated replay still writes the full requested output;
sharing only removes repeated freezing of an unchanged subtree. No mutable output
buffer or parser seed has been converted to a persistent representation.

Run `bash scripts/shared-records-check.sh` for both compiler oracles, their
measurement CSVs, byte comparison and -vgc checks. The runner enforces a 60-second
timeout and 4 GiB address-space ceiling; the oracle also has a 45-second alarm.

Final component ASan/LSan and Valgrind checks include the metric build and all
colocated units plus the integration oracle. They run under 60-second deadlines
and MemoryMax=4G scopes. Memcheck reports zero errors and zero lost bytes, with
120 reachable druntime initialization bytes and no suppressions. The repository
coverage gate is repeated for the final source; its log, branch summary and source
hashes are retained under verification/. R04 retains full baseline verification.
Routine fast/full validation now runs the shared-record oracle as well.

See deep-growth.svg for copy work and retained-memory plots. Re-render with
`python3 performance/results/R05/render.py` (matplotlib required).
