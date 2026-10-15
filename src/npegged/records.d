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

/// Non-owning builder: both live storage and snapshots belong to explicit arenas.
struct RecordBuffer {
    Arena* arena;
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
        return RecordSnapshot(owner.copy!CompactNode(storage[checkpoint .. _length]), checkpoint);
    }

    bool restore(RecordSnapshot saved) @nogc nothrow {
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
        }
        complete = true;
        return true;
    }
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
