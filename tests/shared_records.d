/** Isolated R05 oracle. Invoked with process timeout and 4 GiB memory ceiling. */
module tests.shared_records;
import npegged.records;
import npegged.storage : Arena, Status;
import core.stdc.stdio : printf;
import core.stdc.string : memcmp;
import core.sys.posix.unistd : alarm;

private void equal(scope const(CompactNode)[] a, scope const(CompactNode)[] b) @nogc nothrow {
    assert(a.length == b.length);
    foreach (i; 0 .. a.length) {
        assert(a[i].kind == b[i].kind && a[i].begin == b[i].begin);
        assert(a[i].end == b[i].end && a[i].parent == b[i].parent);
    }
    assert(!a.length || memcmp(a.ptr, b.ptr, a.length * CompactNode.sizeof) == 0);
}

private void deep(size_t depth) @nogc nothrow {
    Arena legacyArena, sharedArena;
    legacyArena.limit = 1024UL * 1024 * 1024;
    sharedArena.limit = 1024UL * 1024 * 1024;
    SharedRecordStore store;
    store.arena = &sharedArena;
    RecordSnapshot baseline;
    SharedRecordSnapshot candidate;
    version (NPeggedMetrics) ulong baselineFrozen;
    foreach (i; 0 .. depth) {
        // Each growth replaces the root. Only its immutable child is shared.
        Arena live;
        RecordBuffer flat;
        flat.arena = &live;
        assert(flat.put(CompactNode(cast(uint)i, 0, i + 1)) == 0);
        flat.parent = 0;
        assert(flat.restore(baseline));
        baseline = flat.snapshot(legacyArena, 0);
        version (NPeggedMetrics)
            baselineFrozen += baseline.nodes.length * CompactNode.sizeof;
        auto head = store.freeze(RecordSnapshot(flat.nodes[0 .. 1], 0));
        candidate = store.join(head, candidate, 0);
        assert(candidate.length == baseline.nodes.length);
    }
    Arena scratch, destination;
    RecordBuffer output;
    output.arena = &destination;
    assert(store.restore(output, candidate, scratch));
    equal(baseline.nodes, output.nodes);
    version (NPeggedMetrics) {
        assert(store.frozenBytes == depth * CompactNode.sizeof);
        assert(store.replayBytes == depth * CompactNode.sizeof);
        printf("%llu,%llu,%llu,%llu,%llu,%llu,%llu\n", cast(ulong)depth, baselineFrozen,
                store.frozenBytes,
                store.replayBytes, cast(ulong)legacyArena.used, cast(ulong)sharedArena.used, cast(ulong)scratch
                    .used);
    }
}

private void versions() @nogc nothrow {
    Arena memory;
    SharedRecordStore store;
    store.arena = &memory;
    CompactNode[2] original = [CompactNode(1, 0, 3), CompactNode(2, 1, 2, 0)];
    auto first = store.freeze(RecordSnapshot(original[], 0));
    // Simulate backtracking and replace the full output with unrelated records.
    CompactNode[2] replacement = [CompactNode(3, 8, 9), CompactNode(4, 10, 12)];
    auto second = store.freeze(RecordSnapshot(replacement[], 0));
    auto combined = store.join(second, first, 1);
    foreach (variant; 0 .. 3) {
        Arena live, scratch, expectedArena;
        RecordBuffer output, expected;
        output.arena = &live;
        expected.arena = &expectedArena;
        assert(output.put(CompactNode(9, 0, 20)) == 0);
        assert(expected.put(CompactNode(9, 0, 20)) == 0);
        output.parent = expected.parent = 0;
        if (variant == 0) {
            assert(store.restore(output, first, scratch));
            assert(expected.restore(RecordSnapshot(original[], 0)));
        } else if (variant == 1) {
            assert(store.restore(output, second, scratch));
            assert(expected.restore(RecordSnapshot(replacement[], 0)));
        } else {
            assert(store.restore(output, combined, scratch));
            assert(expected.restore(RecordSnapshot(replacement[], 0)));
            expected.parent = 2;
            assert(expected.restore(RecordSnapshot(original[], 0)));
        }
        equal(output.nodes, expected.nodes);
        const checkpoint = output.length;
        assert(store.restore(output, first, scratch));
        output.rollback(checkpoint);
        equal(output.nodes, expected.nodes);
    }
    // Every allocation budget is explicit. Partial replay must preserve the prefix.
    foreach (limit; [0, 1, 64, 4096, 8192]) {
        Arena live, scratch;
        live.limit = cast(size_t)limit;
        RecordBuffer output;
        output.arena = &live;
        auto success = store.restore(output, combined, scratch);
        assert(success ? output.length == 4 : output.length == 0);
        assert(success ? output.status == Status.ok : output.status == Status.resourceLimit);
    }
}

private void combinations() @nogc nothrow {
    Arena memory, baselines;
    SharedRecordStore store;
    store.arena = &memory;
    SharedRecordSnapshot[16] versions;
    RecordSnapshot[16] flat;
    uint random = 19;
    foreach (iteration; 0 .. 256) {
        random = random * 1664525 + 1013904223;
        auto source = (random >> 16) % 16;
        auto destination = (random >> 8) % 16;
        auto parent = flat[source].nodes.length && (random & 1) ? random % flat[source].nodes.length : size_t
            .max;
        CompactNode[2] leaf = [
            CompactNode(cast(uint)iteration, iteration, iteration + 2, 3),
            CompactNode(1000, iteration + 1, iteration + 2, 100)
        ];
        auto imported = store.freeze(RecordSnapshot(leaf[], 100));
        auto composed = store.join(versions[source], imported, parent);
        Arena live, scratch, expectedArena;
        RecordBuffer expected, actual;
        expected.arena = &expectedArena;
        actual.arena = &live;
        assert(expected.restore(flat[source]));
        expected.parent = parent;
        assert(expected.restore(RecordSnapshot(leaf[], 100)));
        assert(store.restore(actual, composed, scratch));
        equal(actual.nodes, expected.nodes);
        flat[destination] = expected.snapshot(baselines, 0);
        versions[destination] = composed;
    }
}

int main() @nogc nothrow {
    alarm(45);
    versions();
    combinations();
    version (NPeggedMetrics)
        printf("depth,flat_snapshot_bytes,shared_frozen_bytes,shared_replay_bytes,flat_peak,shared_peak,scratch_peak\n");
    foreach (depth; [16, 32, 64, 128, 256, 512, 1024, 2048])
        deep(depth);
    return 0;
}
