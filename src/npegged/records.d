/** Result-owned compact rule records and transactional output (Boost 1.0). */
module npegged.records;
import npegged.storage : Arena, Status, growthCapacity;

/// Preorder record. Kind tags are supplied by the caller's rule selector.
struct CompactNode {
    uint kind;
    size_t begin, end;
    size_t parent = size_t.max;
}

/// Frozen records retain their original base for parent-index rebasing on replay.
struct RecordSnapshot {
    CompactNode[] nodes;
    size_t base;
}

version (NPeggedMetrics) {
    /// Actual output work, including appends subsequently rolled back on failure.
    struct RecordMetrics {
        ulong restoreCalls, restoreNodes, restoreBytes, growthCopyBytes;
        ulong snapshotCalls, snapshotNodes, snapshotBytes;
    }

    @nogc nothrow unittest {
        RecordMetrics metrics;
        assert(metrics.restoreCalls == 0 && metrics.restoreNodes == 0);
        assert(metrics.snapshotCalls == 0 && metrics.snapshotNodes == 0 && metrics.snapshotBytes == 0);
        assert(metrics.restoreBytes == 0 && metrics.growthCopyBytes == 0);
    }
}

/// Non-owning builder: both live storage and snapshots belong to explicit arenas.
struct RecordBuffer {
    Arena* arena;
    version (NPeggedMetrics) RecordMetrics* metrics;
    uint function(string) @nogc nothrow pure selector;
    private CompactNode[] storage;
    private size_t _length;
    size_t parent = size_t.max;
    bool suppressed;
    private Status failure;

    @property size_t length() const @nogc nothrow {
        return _length;
    }

    @property Status status() const @nogc nothrow {
        return failure != Status.ok ? failure : arena is null ? Status.invalidInput : arena.status;
    }

    @property CompactNode[] nodes() return @nogc nothrow {
        return storage[0 .. _length];
    }

    size_t put(CompactNode node) @nogc nothrow {
        if (status != Status.ok)
            return size_t.max;
        if (_length == size_t.max) {
            failure = Status.resourceLimit;
            return size_t.max;
        }
        if (node.parent != size_t.max && node.parent >= _length) {
            failure = Status.invalidInput;
            return size_t.max;
        }
        if (_length == storage.length) {
            auto replacement = arena.allocate!CompactNode(growthCapacity(_length, _length + 1, 32));
            if (!replacement.length)
                return size_t.max;
            replacement[0 .. _length] = storage[0 .. _length];
            version (NPeggedMetrics)
                if (metrics !is null)
                    metrics.growthCopyBytes += _length * CompactNode.sizeof;
            storage = replacement;
        }
        storage[_length] = node;
        return _length++;
    }

    size_t open(string name, size_t begin) @nogc nothrow {
        if (suppressed)
            return size_t.max;
        if (selector is null) {
            failure = Status.invalidInput;
            return size_t.max;
        }
        return openKind(selector(name), begin);
    }

    size_t openKind(uint kind, size_t begin) @nogc nothrow {
        if (suppressed || kind == uint.max)
            return size_t.max;
        auto index = put(CompactNode(kind, begin, begin, parent));
        if (index != size_t.max)
            parent = index;
        return index;
    }

    void finish(size_t index, size_t end) @nogc nothrow {
        if (index != size_t.max) {
            assert(index < _length);
            storage[index].end = end;
        }
    }

    void rollback(size_t checkpoint) @nogc nothrow {
        assert(checkpoint <= _length);
        _length = checkpoint;
    }

    RecordSnapshot snapshot(ref Arena owner, size_t checkpoint) @nogc nothrow {
        assert(checkpoint <= _length);
        auto frozen = owner.copy!CompactNode(storage[checkpoint .. _length]);
        version (NPeggedMetrics)
            if (metrics !is null) {
                ++metrics.snapshotCalls;
                metrics.snapshotNodes += frozen.length;
                metrics.snapshotBytes += frozen.length * CompactNode.sizeof;
            }
        return RecordSnapshot(frozen, checkpoint);
    }

    bool restore(RecordSnapshot saved) @nogc nothrow {
        version (NPeggedMetrics)
            if (metrics !is null)
                ++metrics.restoreCalls;
        const base = _length;
        bool complete;
        scope (exit)
            if (!complete)
                _length = base;
        foreach (i, original; saved.nodes) {
            auto node = original;
            if (node.parent == size_t.max || node.parent < saved.base)
                node.parent = parent;
            else {
                auto offset = node.parent - saved.base;
                if (offset >= i) {
                    failure = Status.invalidInput;
                    return false;
                }
                // offset names an already appended node, so this sum cannot wrap.
                node.parent = base + offset;
            }
            if (put(node) == size_t.max)
                return false;
            version (NPeggedMetrics)
                if (metrics !is null) {
                    ++metrics.restoreNodes;
                    metrics.restoreBytes += CompactNode.sizeof;
                }
        }
        complete = true;
        return true;
    }
}

version (NPeggedMetrics) @nogc nothrow unittest {
    Arena owner;
    RecordMetrics metrics;
    RecordBuffer records;
    records.arena = &owner;
    records.metrics = &metrics;
    CompactNode[33] nodes;
    assert(records.restore(RecordSnapshot(nodes[], 0)));
    assert(metrics.restoreCalls == 1 && metrics.restoreNodes == 33);
    assert(metrics.restoreBytes == 33 * CompactNode.sizeof);
    assert(metrics.growthCopyBytes == 32 * CompactNode.sizeof);
    assert(records.restore(RecordSnapshot.init));
    assert(metrics.restoreCalls == 2 && metrics.restoreNodes == 33);
    Arena snapshots;
    auto frozen = records.snapshot(snapshots, 1);
    assert(frozen.nodes.length == 32);
    assert(metrics.snapshotCalls == 1 && metrics.snapshotNodes == 32);
    assert(metrics.snapshotBytes == 32 * CompactNode.sizeof);
    assert(records.snapshot(snapshots, records.length).nodes.length == 0);
    assert(metrics.snapshotCalls == 2 && metrics.snapshotNodes == 32);
    Arena noSnapshot;
    noSnapshot.limit = 0;
    assert(records.snapshot(noSnapshot, 0).nodes.length == 0);
    assert(metrics.snapshotCalls == 3 && metrics.snapshotNodes == 32);
    CompactNode[2] corrupt = [CompactNode.init, CompactNode(0, 0, 0, 1)];
    assert(!records.restore(RecordSnapshot(corrupt[], 0)));
    assert(metrics.restoreCalls == 3 && metrics.restoreNodes == 34);
    assert(metrics.restoreBytes == 34 * CompactNode.sizeof && records.length == 33);
    Arena exhausted;
    exhausted.limit = 0;
    RecordBuffer failed;
    failed.arena = &exhausted;
    failed.metrics = &metrics;
    assert(!failed.restore(RecordSnapshot(nodes[0 .. 1], 0)));
    assert(metrics.restoreCalls == 4 && metrics.restoreNodes == 34);
}

@nogc nothrow unittest {
    Arena owner, snapshots;
    RecordBuffer records;
    records.arena = &owner;
    records.selector = (string name) @nogc nothrow => name == "skip" ? uint.max : 7;
    assert(records.open("skip", 0) == size_t.max && records.length == 0);
    auto root = records.open("root", 0);
    assert(root == 0 && records.parent == 0);
    auto child = records.open("child", 1);
    records.finish(child, 2);
    records.parent = root;
    records.finish(root, 3);
    assert(records.nodes[1].parent == 0 && records.nodes[0].end == 3);
    auto saved = records.snapshot(snapshots, 1);
    records.rollback(1);
    records.parent = size_t.max;
    auto other = records.open("other", 4);
    assert(other == 1);
    assert(records.restore(saved));
    assert(records.nodes[2].parent == 1 && records.nodes[2].begin == 1);
    foreach (i; 0 .. 70)
        assert(records.put(CompactNode(8, i, i + 1, 1)) != size_t.max);
    assert(records.nodes.length == 73 && saved.nodes[0].begin == 1);
    auto nested = records.snapshot(snapshots, 1);
    records.rollback(1);
    records.parent = 0;
    assert(records.restore(nested));
    assert(records.nodes[1].parent == 0 && records.nodes[2].parent == 1);
    records.suppressed = true;
    assert(records.open("ignored", 99) == size_t.max && records.length == 73);
    records.finish(size_t.max, 99);
    assert(records.openKind(8, 99) == size_t.max);
    records.suppressed = false;
    assert(records.openKind(uint.max, 99) == size_t.max);
    assert(records.status == Status.ok);
    Arena limited;
    limited.limit = 0;
    RecordBuffer failed;
    failed.arena = &limited;
    assert(failed.put(CompactNode.init) == size_t.max && failed.status == Status.resourceLimit);
    assert(!failed.restore(saved));
    RecordBuffer invalid;
    assert(invalid.status == Status.invalidInput && invalid.put(CompactNode.init) == size_t.max);
    invalid.arena = &owner;
    assert(invalid.open("x", 0) == size_t.max && invalid.status == Status.invalidInput);
    RecordBuffer overflow;
    overflow.arena = &owner;
    overflow._length = size_t.max;
    assert(overflow.put(CompactNode.init) == size_t.max && overflow.status == Status.resourceLimit);
    CompactNode[2] corrupt = [CompactNode(0, 0, 1), CompactNode(0, 1, 2, 1)];
    records.parent = 0;
    auto originalLength = records.length;
    assert(!records.restore(RecordSnapshot(corrupt[], 0)) && records.status == Status.invalidInput);
    assert(records.length == originalLength);
    RecordBuffer badParent;
    badParent.arena = &owner;
    assert(badParent.put(CompactNode(0, 0, 1, 0)) == size_t.max);
    assert(badParent.status == Status.invalidInput && badParent.length == 0);
}

/// Experimental immutable record composition. Handles borrow their component arenas.
/// Only explicit fragment composition shares storage; arbitrary flat input is copied.
struct SharedRecordSnapshot {
    private const(RecordFragment)* root;
    @property size_t length() const @nogc nothrow {
        return root is null ? 0 : root.length;
    }
}

@nogc nothrow unittest {
    SharedRecordSnapshot empty;
    assert(empty.length == 0);
}

private struct RecordFragment {
    const(RecordFragment)* left, right;
    const(CompactNode)[] nodes;
    size_t length, height;
    size_t attachment = size_t.max;
}

/// Non-owning experimental store. Every component arena must outlive its handles and replay.
/// No parser uses this API; callers must prove composition or import a full flat copy.
struct SharedRecordStore {
    Arena* arena;
    private Status failure;
    /// Cumulative diagnostic work; linking existing fragments never increases frozenBytes.
    version (NPeggedMetrics) ulong frozenBytes, replayBytes, fragmentCount;

    @property Status status() const @nogc nothrow {
        return failure != Status.ok ? failure : arena is null ? Status.invalidInput : arena.status;
    }

    /// Conservative fallback: validate, copy and normalize all parent indices.
    SharedRecordSnapshot freeze(RecordSnapshot saved) @nogc nothrow {
        if (status != Status.ok || !saved.nodes.length)
            return SharedRecordSnapshot.init;
        foreach (i, node; saved.nodes)
            if (node.parent != size_t.max && node.parent >= saved.base && node.parent - saved.base >= i) {
                failure = Status.invalidInput;
                return SharedRecordSnapshot.init;
            }
        auto fragment = arena.allocate!RecordFragment(1);
        if (!fragment.length)
            return SharedRecordSnapshot.init;
        auto copy = arena.copy!CompactNode(saved.nodes);
        if (!copy.length)
            return SharedRecordSnapshot.init;
        foreach (ref node; copy)
            node.parent = node.parent == size_t.max || node.parent < saved.base ? size_t.max : node
                .parent - saved.base;
        fragment[0].nodes = copy;
        fragment[0].length = copy.length;
        fragment[0].height = 1;
        version (NPeggedMetrics) {
            frozenBytes += copy.length * CompactNode.sizeof;
            ++fragmentCount;
        }
        return SharedRecordSnapshot(&fragment[0]);
    }

    /// Right external roots attach to an earlier left node or to the replay parent.
    /// Internal parent references in both operands remain unchanged.
    SharedRecordSnapshot join(SharedRecordSnapshot left, SharedRecordSnapshot right, size_t attachment = size_t
            .max) @nogc nothrow {
        if (status != Status.ok)
            return SharedRecordSnapshot.init;
        if (attachment != size_t.max && attachment >= left.length) {
            failure = Status.invalidInput;
            return SharedRecordSnapshot.init;
        }
        if (left.length > size_t.max - right.length) {
            failure = Status.resourceLimit;
            return SharedRecordSnapshot.init;
        }
        if (!right.length)
            return left;
        if (!left.length)
            return right;
        auto height = left.root.height > right.root.height ? left.root.height : right.root.height;
        if (height == size_t.max) {
            failure = Status.resourceLimit;
            return SharedRecordSnapshot.init;
        }
        auto fragment = arena.allocate!RecordFragment(1);
        if (!fragment.length)
            return SharedRecordSnapshot.init;
        fragment[0].left = left.root;
        fragment[0].right = right.root;
        fragment[0].attachment = attachment;
        fragment[0].length = left.length + right.length;
        fragment[0].height = height + 1;
        version (NPeggedMetrics)
            ++fragmentCount;
        return SharedRecordSnapshot(&fragment[0]);
    }

    /// Iterative replay uses bounded scratch arena space; failure rolls output length back.
    bool restore(ref RecordBuffer output, SharedRecordSnapshot saved, ref Arena scratch) @nogc nothrow {
        if (output.status != Status.ok)
            return false;
        if (status != Status.ok) {
            output.failure = status;
            return false;
        }
        if (!saved.length)
            return true;
        const checkpoint = output.length;
        if (saved.length > size_t.max - checkpoint) {
            output.failure = Status.resourceLimit;
            return false;
        }
        struct Frame {
            const(RecordFragment)* fragment;
            size_t base, parent;
        }
        // DFS retains at most one pending right fragment per nesting level.
        auto stack = scratch.allocate!Frame(saved.root.height);
        if (!stack.length) {
            output.failure = scratch.status;
            return false;
        }
        bool complete;
        scope (exit)
            if (!complete)
                output.rollback(checkpoint);
        size_t count = 1;
        stack[0] = Frame(saved.root, checkpoint, output.parent);
        // The checked total length bounds every descendant base/parent addition.
        while (count) {
            auto frame = stack[--count];
            auto fragment = frame.fragment;
            if (fragment.left !is null) {
                stack[count++] = Frame(fragment.right, frame.base + fragment.left.length,
                        fragment.attachment == size_t.max ? frame.parent : frame.base + fragment
                            .attachment);
                stack[count++] = Frame(fragment.left, frame.base, frame.parent);
            } else {
                foreach (original; fragment.nodes) {
                    CompactNode node = original;
                    node.parent = node.parent == size_t.max ? frame.parent : frame.base + node.parent;
                    if (output.put(node) == size_t.max)
                        return false;
                    version (NPeggedMetrics)
                        replayBytes += CompactNode.sizeof;
                }
            }
        }
        complete = true;
        return true;
    }
}

@nogc nothrow unittest {
    version (NPeggedMetrics) {
    } else {
        static assert(!__traits(hasMember, SharedRecordStore, "frozenBytes"));
        static assert(!__traits(hasMember, SharedRecordStore, "replayBytes"));
        static assert(!__traits(hasMember, SharedRecordStore, "fragmentCount"));
    }
    Arena owner, live, scratch;
    SharedRecordStore store;
    store.arena = &owner;
    assert(store.status == Status.ok);
    assert(!store.freeze(RecordSnapshot.init).length && owner.used == 0);
    CompactNode[2] input = [CompactNode(1, 3, 8, 5), CompactNode(2, 4, 6, 7)];
    auto leaf = store.freeze(RecordSnapshot(input[], 7));
    assert(leaf.length == 2);
    version (NPeggedMetrics)
        assert(store.frozenBytes == 2 * CompactNode.sizeof);
    input[0].kind = 99;
    CompactNode[1] root = [CompactNode(3, 0, 9)];
    auto outer = store.freeze(RecordSnapshot(root[], 0));
    auto nested = store.join(outer, leaf, 0);
    auto sibling = store.join(nested, leaf);
    assert(sibling.length == 5);
    version (NPeggedMetrics)
        assert(store.frozenBytes == 3 * CompactNode.sizeof && store.fragmentCount == 4);
    assert(store.join(SharedRecordSnapshot.init, leaf).length == 2);
    assert(store.join(leaf, SharedRecordSnapshot.init).length == 2);
    RecordBuffer output;
    output.arena = &live;
    assert(output.put(CompactNode(9, 0, 10)) == 0);
    output.parent = 0;
    assert(store.restore(output, sibling, scratch));
    assert(output.nodes[1] == CompactNode(3, 0, 9, 0));
    assert(output.nodes[2] == CompactNode(1, 3, 8, 1));
    assert(output.nodes[3] == CompactNode(2, 4, 6, 2));
    assert(output.nodes[4] == CompactNode(1, 3, 8, 0));
    assert(output.nodes[5] == CompactNode(2, 4, 6, 4));
    output.rollback(1);
    assert(store.restore(output, leaf, scratch));
    assert(output.nodes[1] == CompactNode(1, 3, 8, 0));
    assert(output.nodes[2] == CompactNode(2, 4, 6, 1));
    assert(store.restore(output, SharedRecordSnapshot.init, scratch));
    version (NPeggedMetrics)
        assert(store.replayBytes == 7 * CompactNode.sizeof);
}

@nogc nothrow unittest {
    SharedRecordStore missing;
    assert(missing.status == Status.invalidInput);
    assert(!missing.freeze(RecordSnapshot.init).length);
    assert(!missing.join(SharedRecordSnapshot.init, SharedRecordSnapshot.init).length);
    Arena memory, live, scratch;
    RecordBuffer output;
    output.arena = &live;
    assert(!missing.restore(output, SharedRecordSnapshot.init, scratch));
    assert(output.status == Status.invalidInput);
    SharedRecordStore invalid;
    invalid.arena = &memory;
    CompactNode[1] corrupt = [CompactNode(0, 0, 1, 0)];
    assert(!invalid.freeze(RecordSnapshot(corrupt[], 0)).length);
    assert(invalid.status == Status.invalidInput && memory.used == 0);
    assert(!invalid.freeze(RecordSnapshot.init).length);
    SharedRecordStore attachment;
    attachment.arena = &memory;
    assert(!attachment.join(SharedRecordSnapshot.init, SharedRecordSnapshot.init, 0).length);
    assert(attachment.status == Status.invalidInput);
    SharedRecordStore overflow;
    overflow.arena = &memory;
    RecordFragment huge, small;
    huge.length = size_t.max;
    small.length = 1;
    assert(!overflow.join(SharedRecordSnapshot(&huge), SharedRecordSnapshot(&small)).length);
    assert(overflow.status == Status.resourceLimit);
    SharedRecordStore depth;
    depth.arena = &memory;
    huge.length = 1;
    huge.height = size_t.max;
    assert(!depth.join(SharedRecordSnapshot(&huge), SharedRecordSnapshot(&small)).length);
    assert(depth.status == Status.resourceLimit);
}

@nogc nothrow unittest {
    CompactNode[1] node;
    Arena frozen;
    SharedRecordStore store;
    store.arena = &frozen;
    auto saved = store.freeze(RecordSnapshot(node[], 0));
    assert(saved.length == 1);
    Arena unavailable, live;
    unavailable.limit = 0;
    RecordBuffer output;
    output.arena = &live;
    assert(!store.restore(output, saved, unavailable));
    assert(output.length == 0 && output.status == Status.resourceLimit);
    RecordBuffer noOutput;
    assert(!store.restore(noOutput, saved, live));
    Arena limited, scratch;
    limited.limit = 0;
    RecordBuffer failed;
    failed.arena = &limited;
    assert(!store.restore(failed, saved, scratch));
    assert(failed.length == 0 && failed.status == Status.resourceLimit);
    Arena empty;
    empty.limit = 0;
    SharedRecordStore cannotFreeze;
    cannotFreeze.arena = &empty;
    assert(!cannotFreeze.freeze(RecordSnapshot(node[], 0)).length);
    assert(cannotFreeze.status == Status.resourceLimit);
    // Fragment allocation fits, but the larger leaf copy must fail.
    Arena tight;
    tight.limit = 4096;
    SharedRecordStore partial;
    partial.arena = &tight;
    CompactNode[200] many;
    assert(!partial.freeze(RecordSnapshot(many[], 0)).length);
    assert(partial.status == Status.resourceLimit);
    version (NPeggedMetrics)
        assert(partial.frozenBytes == 0);
}

@nogc nothrow unittest {
    Arena owner;
    SharedRecordStore store;
    store.arena = &owner;
    CompactNode[100] many;
    auto saved = store.freeze(RecordSnapshot(many[], 0));
    Arena limited, scratch;
    limited.limit = 4096;
    RecordBuffer output;
    output.arena = &limited;
    assert(output.put(CompactNode(9, 0, 1)) == 0);
    output.parent = 0;
    assert(!store.restore(output, saved, scratch));
    assert(output.length == 1 && output.nodes[0].kind == 9);
    assert(output.status == Status.resourceLimit);
    version (NPeggedMetrics)
        assert(store.replayBytes > 0);
    Arena unavailable;
    unavailable.limit = 0;
    SharedRecordStore cannotJoin;
    cannotJoin.arena = &unavailable;
    assert(!cannotJoin.join(saved, saved).length);
    assert(cannotJoin.status == Status.resourceLimit);
    // Replay size overflow is checked before appending.
    RecordFragment huge;
    huge.length = size_t.max;
    huge.height = 1;
    Arena live, work;
    RecordBuffer overflow;
    overflow.arena = &live;
    assert(overflow.put(CompactNode.init) == 0);
    assert(!store.restore(overflow, SharedRecordSnapshot(&huge), work));
    assert(overflow.length == 1 && overflow.status == Status.resourceLimit && work.used == 0);
}

@nogc nothrow unittest {
    Arena memory, live, scratch;
    SharedRecordStore store;
    store.arena = &memory;
    CompactNode[1] node;
    auto saved = store.freeze(RecordSnapshot(node[], 0));
    RecordBuffer output;
    output.arena = &live;
    output.parent = 0; // No preceding parent exists in the destination.
    assert(!store.restore(output, saved, scratch));
    assert(output.length == 0 && output.status == Status.invalidInput);
}

@nogc nothrow unittest {
    Arena live, scratch;
    RecordBuffer output;
    output.arena = &live;
    output.failure = Status.resourceLimit;
    SharedRecordStore missing;
    assert(!missing.restore(output, SharedRecordSnapshot.init, scratch));
    assert(output.status == Status.resourceLimit);
}
