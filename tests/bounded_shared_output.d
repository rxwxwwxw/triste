/** C02 resource semantics. This module's package permits component setup only;
 * public parseRecords tests always retain the production activation guards. */
module npegged.tests.bounded_shared_output;

import npegged.grammar;
import npegged.records : RecordBuffer, SharedRecordStore, RecordSnapshot, CompactNode, RecordMetrics;
import core.stdc.stdio : printf;
import core.stdc.stdlib : malloc;
import core.sys.posix.unistd : alarm;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;

private uint selected(string name) @nogc nothrow pure {
    return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : 1;
}

mixin(grammar!(Memoization.selective, selected, backend)(`
BoundedShared:
    Root <- Expr eoi
    Expr <- Expr '+' Atom / Atom
    Atom <- '(' Expr ')' / 'n'
`));
static assert(BoundedShared.npeggedSharedOutputEligible);

private struct Event {
    string name;
    size_t position;
    bool successful;
}

private struct Events {
    Event[4096] values;
    size_t length;
    static void observe(string name, size_t position, bool successful, void* user) @nogc nothrow {
        auto events = cast(Events*)user;
        assert(events.length < events.values.length);
        events.values[events.length++] = Event(name, position, successful);
    }
}

private ParseContext unlimited() @nogc nothrow {
    ParseContext context;
    context.stepLimit = context.depthLimit = context.memoryLimit = size_t.max;
    return context;
}

private enum Budget {
    steps,
    depth,
    memory,
    output,
    defaults,
    trace
}

private void configure(ref ParseContext context, Budget kind, size_t limit) @nogc nothrow {
    final switch (kind) {
    case Budget.steps:
        context.stepLimit = limit;
        break;
    case Budget.depth:
        context.depthLimit = limit;
        break;
    case Budget.memory:
        context.memoryLimit = limit;
        break;
    case Budget.output:
        break;
    case Budget.defaults:
        context = ParseContext.init;
        break;
    case Budget.trace:
        break;
    }
}

private Status publicPair(bool owned)(string input, Budget kind, size_t limit, bool emit = true) @nogc nothrow {
    auto before = unlimited();
    configure(before, kind, limit);
    auto after = before;
    after.sharedOutput = true;
    ParseMetrics beforeMetrics, afterMetrics;
    before.metrics = &beforeMetrics;
    after.metrics = &afterMetrics;
    Events beforeEvents, afterEvents;
    if (kind == Budget.trace) {
        before.trace = after.trace = &Events.observe;
        before.userData = &beforeEvents;
        after.userData = &afterEvents;
    }
    const outputLimit = kind == Budget.output ? limit : kind == Budget.defaults ? 256 * 1024 * 1024 : size_t
        .max;
    auto reference = parseRecords!(BoundedShared.opCall, selected, owned)(before, input, outputLimit);
    auto candidate = parseRecords!(BoundedShared.opCall, selected, owned)(after, input, outputLimit);
    assert(reference.status == candidate.status && reference.successful == candidate.successful);
    assert(reference.end == candidate.end && reference.failEnd == candidate.failEnd);
    assert(reference.nodes == candidate.nodes);
    assert(reference.arena.used == candidate.arena.used);
    assert(reference.arena.requestedBytes == candidate.arena.requestedBytes);
    assert(reference.arena.allocationCalls == candidate.arena.allocationCalls);
    assert(reference.outputArena.used == candidate.outputArena.used);
    assert(reference.outputArena.requestedBytes == candidate.outputArena.requestedBytes);
    assert(reference.outputArena.allocationCalls == candidate.outputArena.allocationCalls);
    assert(beforeEvents.length == afterEvents.length);
    assert(beforeEvents.values[0 .. beforeEvents.length] == afterEvents.values[0 .. afterEvents
            .length]);
    assert(afterMetrics.output.sharedSnapshots == 0 && afterMetrics.output.sharedReplays == 0);
    assert(afterMetrics.output.sharedFrozenNodes == 0 && afterMetrics.output.sharedReusedNodes == 0);
    static if (owned) {
        assert(reference.input == candidate.input);
        if (reference.status != Status.resourceLimit || reference.input.length) {
            assert(reference.input == input);
            assert(!input.length || reference.input.ptr != input.ptr);
        }
    } else
        assert(reference.input.length == 0 && candidate.input.length == 0);
    if (emit) {
        printf("public,%u,%u,%llu,%llu,%u,%u,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu\n",
                cast(uint)owned, cast(uint)kind, cast(ulong)input.length, cast(ulong)limit,
                cast(uint)candidate.status, cast(uint)candidate.successful,
                cast(ulong)candidate.end, cast(ulong)candidate.failEnd,
                cast(ulong)candidate.nodes.length, cast(ulong)candidate.arena.used,
                cast(ulong)candidate.outputArena.used,
                afterMetrics.output.sharedSnapshots, afterMetrics.output.sharedReplays, cast(ulong)afterEvents
                    .length);
    }
    return candidate.status;
}

// Find an adjacent failure/success transition, not an assumed globally monotone
// minimum: arena slab clamping can change allocation shapes as limits vary.
private size_t transition(bool owned)(string input, Budget kind, size_t high) @nogc nothrow {
    size_t low;
    assert(publicPair!owned(input, kind, low, false) == Status.resourceLimit);
    assert(publicPair!owned(input, kind, high, false) == Status.ok);
    while (high - low > 1) {
        const middle = low + (high - low) / 2;
        const status = publicPair!owned(input, kind, middle, false);
        assert(status == Status.ok || status == Status.resourceLimit);
        if (status == Status.ok)
            high = middle;
        else
            low = middle;
    }
    assert(publicPair!owned(input, kind, high - 1) == Status.resourceLimit);
    assert(publicPair!owned(input, kind, high) == Status.ok);
    assert(publicPair!owned(input, kind, high + 1) == Status.ok);
    printf("transition,%u,%u,%llu,%llu\n", cast(uint)owned, cast(uint)kind, cast(ulong)input.length, cast(
            ulong)high);
    return high;
}

private struct Work {
    size_t steps, depth, requested, reserved, outputReserved, nodes;
    ulong snapshots, replays;
}

// Direct subsystem setup is unlimited only. It observes actual State.steps;
// it never enables the public fast path with finite limits.
private Work work(string input, bool sharing) @nogc nothrow {
    Arena scratch, output;
    scratch.limit = output.limit = size_t.max;
    SharedRecordStore store;
    store.arena = &scratch;
    RecordBuffer records;
    records.arena = &output;
    records.selector = &selected;
    if (sharing)
        assert(records.enableSharedOutput(store, scratch));
    State!(false, 2) state;
    state.arena = &scratch;
    state.input = input;
    state.context = unlimited();
    ParseMetrics metrics;
    state.context.metrics = &metrics;
    state.attachRecords(records);
    auto node = state.finish(BoundedShared.opCall(state, 0));
    assert(state.status == Status.ok && node.successful && node.end == input.length);
    assert(records.status == Status.ok && state.depth == 0);
    return Work(state.steps, state.depth, scratch.requestedBytes, scratch.used, output.used,
            records.length, metrics.output.sharedSnapshots, metrics.output.sharedReplays);
}

private void snapshotBoundary(size_t count, size_t limit, bool sharing) @nogc nothrow {
    Arena live, scratch;
    scratch.limit = limit;
    SharedRecordStore store;
    store.arena = &scratch;
    RecordBuffer records;
    records.arena = &live;
    RecordMetrics metrics;
    records.metrics = &metrics;
    if (sharing)
        assert(records.enableSharedOutput(store, scratch));
    foreach (i; 0 .. count)
        assert(records.put(CompactNode(cast(uint)i, i, i + 1, i ? 0 : size_t.max)) == i);
    auto saved = records.snapshot(scratch, 0);
    const snapshotStatus = scratch.status;
    if (count == 128) {
        enum flatNeeded = 128 * CompactNode.sizeof + 2 * size_t.sizeof + CompactNode.alignof - 1;
        const needed = sharing ? 4096 + flatNeeded : flatNeeded;
        assert((snapshotStatus == Status.ok) == (limit >= needed));
    }
    if (snapshotStatus == Status.ok) {
        records.rollback(0);
        assert(records.restore(saved));
        assert(records.length == count);
        foreach (i, node; records.nodes)
            assert(node == CompactNode(cast(uint)i, i, i + 1, i ? 0 : size_t.max));
    } else {
        assert(snapshotStatus == Status.resourceLimit);
        assert(records.length == count);
        assert(!records.restore(saved) || !saved.nodes.length);
    }
    if (sharing && count >= 4096 / CompactNode.sizeof && snapshotStatus == Status.ok)
        assert(metrics.sharedSnapshots > 0 && metrics.sharedReplays > 0);
    if (count < 4096 / CompactNode.sizeof)
        assert(metrics.sharedSnapshots == 0 && metrics.sharedReplays == 0);
    printf("snapshot,%llu,%llu,%u,%u,%llu,%llu,%llu,%llu,%llu\n", cast(ulong)count,
            cast(ulong)limit, cast(uint)sharing, cast(uint)snapshotStatus, cast(ulong)scratch.used,
            cast(ulong)scratch.requestedBytes, metrics.sharedSnapshots, metrics.sharedReplays, metrics
                .snapshotBytes);
}

private __gshared size_t allocatorCalls;
private void* failSecond(size_t bytes) @nogc nothrow {
    return ++allocatorCalls == 2 ? null : malloc(bytes);
}

private void allocationFailure() @nogc nothrow {
    Arena scratch;
    scratch.allocator = &failSecond;
    SharedRecordStore store;
    store.arena = &scratch;
    CompactNode[128] nodes;
    allocatorCalls = 0;
    auto snapshot = store.freeze(RecordSnapshot(nodes[], 0));
    assert(!snapshot.length && store.status == Status.outOfMemory);
    assert(scratch.allocationCalls == 2 && scratch.used == 4096);
    assert(store.frozenBytes == 0);
    printf("allocation-failure,%u,%llu,%llu\n", cast(uint)store.status,
            cast(ulong)scratch.allocationCalls, cast(ulong)scratch.used);
}

int main() @nogc nothrow {
    alarm(45);
    // A 128-node payload needs 4096 bytes plus Arena's documented block and
    // worst-case alignment accounting. Shared freezing first allocates a slab
    // containing a fragment, so the same first leaf needs an additional slab.
    enum overhead = 2 * size_t.sizeof + CompactNode.alignof - 1;
    enum flatBoundary = 128 * CompactNode.sizeof + overhead;
    enum sharedBoundary = 4096 + flatBoundary;
    foreach (count; [127, 128, 129])
        foreach (limit; [
            flatBoundary - 1, flatBoundary, flatBoundary + 1, sharedBoundary - 1, sharedBoundary,
            sharedBoundary + 1
    ])
            foreach (sharing; [false, true])
                snapshotBoundary(count, limit, sharing);
    allocationFailure();
    char[512] bytes;
    foreach (i, ref c; bytes)
        c = i % 2 ? '+' : 'n';
    foreach (terms; [63, 64, 65, 128, 129]) {
        auto input = cast(string)bytes[0 .. terms * 2 - 1];
        auto flat = work(input, false);
        auto sharing = work(input, true);
        assert(flat.steps == sharing.steps && flat.depth == sharing.depth && flat.nodes == sharing
                .nodes);
        if (terms >= 128)
            assert(sharing.snapshots > 0 && sharing.replays > 0);
        printf("work,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu\n", cast(ulong)terms,
                cast(ulong)flat.steps, cast(ulong)sharing.steps, cast(ulong)flat.requested,
                cast(ulong)sharing.requested, cast(ulong)flat.reserved,
                cast(ulong)sharing.reserved, cast(ulong)flat.nodes, sharing.snapshots, sharing
                    .replays);
        static foreach (owned; [false, true]) {
            {
                auto context = unlimited();
                auto reference = parseRecords!(BoundedShared.opCall, selected, owned)(context, input, size_t
                        .max);
                assert(reference.successful);
                transition!owned(input, Budget.steps, flat.steps);
                transition!owned(input, Budget.depth, 1024);
                transition!owned(input, Budget.memory, reference.arena.used);
                transition!owned(input, Budget.output, reference.outputArena.used);
                publicPair!owned(input, Budget.defaults, 0);
                publicPair!owned(input, Budget.trace, 0);
                publicPair!owned(cast(string)bytes[0 .. terms * 2], Budget.steps, flat.steps + 100);
            }
        }
    }
    printf("C02 bounded shared-output oracle passed\n");
    return 0;
}
