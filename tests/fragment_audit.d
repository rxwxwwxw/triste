/** P12 Audit: Fragment lifetime, parent rebasing, rollback, and resource limits. */
module tests.fragment_audit;

import npegged.records;
import npegged.storage : Arena, Status;
import npegged.grammar;
import npegged.peg : ParseContext, parseRecords, CompactResult;
import core.sys.posix.unistd : alarm;
import core.stdc.stdio : printf;
import core.stdc.string : memcmp;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;

version (NPeggedFullMemo)
    private enum memo = Memoization.yes;
else
    private enum memo = Memoization.selective;

private uint exprSelector(string name) @nogc nothrow pure {
    if (name.length >= 5 && name[$ - 5 .. $] == ".Expr")
        return 1;
    if (name.length >= 5 && name[$ - 5 .. $] == ".Term")
        return 2;
    if (name.length >= 7 && name[$ - 7 .. $] == ".Factor")
        return 3;
    if (name.length >= 5 && name[$ - 5 .. $] == ".Root")
        return 0;
    return uint.max;
}

private uint alternatingSelector(string name) @nogc nothrow pure {
    // Alternates: Root and Atom are selected; Inner and Middle are omitted
    if (name.length >= 5 && name[$ - 5 .. $] == ".Root")
        return 0;
    if (name.length >= 5 && name[$ - 5 .. $] == ".Atom")
        return 1;
    return uint.max;
}

// Nested left recursion grammar: Expr calls Term, Term calls Factor
mixin(grammar!(memo, exprSelector, backend)(`
NestedLR:
    Root <- Expr eoi
    Expr <- Expr '+' Term / Term
    Term <- Term '*' Factor / Factor
    Factor <- '(' Expr ')' / 'n'
`));

// Alternating selected / non-selected nodes in left-recursive grammar
mixin(grammar!(memo, alternatingSelector, backend)(`
AlternatingLR:
    Root <- Expr eoi
    Expr <- Expr '+' Inner / Inner
    Inner <- Middle
    Middle <- Atom
    Atom <- 'n'
`));

// Probe inside left-recursive grammar for suppressRecords testing
mixin(grammar!(memo, exprSelector, backend)(`
ProbeLR:
    Root <- Expr eoi
    Expr <- &Expr Expr '+' 'n' / 'n'
`));

private void compareTrees(scope const(CompactNode)[] a, scope const(CompactNode)[] b) @nogc nothrow {
    assert(a.length == b.length);
    foreach (i; 0 .. a.length) {
        assert(a[i].kind == b[i].kind);
        assert(a[i].begin == b[i].begin);
        assert(a[i].end == b[i].end);
        assert(a[i].parent == b[i].parent);
    }
}

/// 1. Repeated frozen seed: test 50 generations of freeze -> join -> restore.
private void testRepeatedFrozenSeed() @nogc nothrow {
    Arena sharedArena, baselineArena;
    SharedRecordStore store;
    store.arena = &sharedArena;

    // Seed larger than 128 nodes
    enum seedSize = 140;
    CompactNode[seedSize] seedNodes;
    seedNodes[0] = CompactNode(0, 0, 1000, size_t.max);
    foreach (i; 1 .. seedSize)
        seedNodes[i] = CompactNode(cast(uint)i, i, i + 1, 0);

    auto currentShared = store.freeze(RecordSnapshot(seedNodes[], 0));
    assert(currentShared.length == seedSize);

    // Reference flat snapshot
    Arena refLive;
    RecordBuffer refBuffer;
    refBuffer.arena = &refLive;
    assert(refBuffer.restore(RecordSnapshot(seedNodes[], 0)));
    auto refSnapshot = refBuffer.snapshot(baselineArena, 0);

    // 50 iterations of seed growth
    foreach (gen; 0 .. 50) {
        // Growth delta: 4 nodes
        CompactNode[4] delta;
        const base = seedSize + gen * 4;
        foreach (k; 0 .. 4) {
            auto idx = base + k;
            delta[k] = CompactNode(cast(uint)(1000 + gen * 10 + k), idx, idx + 1, 0);
        }

        auto deltaShared = store.freeze(RecordSnapshot(delta[], base));
        currentShared = store.join(currentShared, deltaShared, 0);
        assert(currentShared.length == base + 4);

        // Update reference
        refBuffer.parent = 0;
        assert(refBuffer.restore(RecordSnapshot(delta[], base)));
        refSnapshot = refBuffer.snapshot(baselineArena, 0);

        // Replay and compare
        Arena live, scratch;
        RecordBuffer actual;
        actual.arena = &live;
        assert(store.restore(actual, currentShared, scratch));
        compareTrees(actual.nodes, refBuffer.nodes);
    }
    printf("1. repeated frozen seed passed\n");
}

/// 2. Nested left recursion: Expr + Term both left-recursive, evaluated over deep inputs.
private void testNestedLeftRecursion() @nogc nothrow {
    ParseContext flatContext, sharedContext;
    version (NPeggedSharedOutput)
        sharedContext.sharedOutput = true;

    // Build nested expression: n*n+n*n+n*n...
    char[512] input;
    size_t pos = 0;
    foreach (i; 0 .. 40) {
        if (i > 0)
            input[pos++] = '+';
        input[pos++] = 'n';
        input[pos++] = '*';
        input[pos++] = 'n';
    }
    string exprStr = cast(string)input[0 .. pos];

    auto flatResult = parseRecords!(NestedLR.opCall, exprSelector)(flatContext, exprStr);
    auto sharedResult = parseRecords!(NestedLR.opCall, exprSelector)(sharedContext, exprStr);

    assert(flatResult.successful && sharedResult.successful);
    assert(flatResult.status == Status.ok && sharedResult.status == Status.ok);
    assert(flatResult.end == sharedResult.end && flatResult.failEnd == sharedResult.failEnd);
    compareTrees(flatResult.nodes, sharedResult.nodes);
    printf("2. nested left recursion passed\n");
}

/// 3. Many siblings: 2,000 siblings attached to one parent, mixing single nodes and shared spans.
private void testManySiblings() @nogc nothrow {
    Arena sharedArena;
    SharedRecordStore store;
    store.arena = &sharedArena;

    // Small reusable fragment (4 siblings)
    CompactNode[4] chunk = [
        CompactNode(1, 1, 2, size_t.max), CompactNode(2, 2, 3, size_t.max),
        CompactNode(3, 3, 4, size_t.max), CompactNode(4, 4, 5, size_t.max)
    ];
    auto chunkSnapshot = store.freeze(RecordSnapshot(chunk[], 0));

    // Compose 500 chunks = 2,000 siblings attached to root
    CompactNode[1] root = [CompactNode(0, 0, 10000, size_t.max)];
    auto fullTree = store.freeze(RecordSnapshot(root[], 0));
    foreach (c; 0 .. 500) {
        fullTree = store.join(fullTree, chunkSnapshot, 0);
    }
    assert(fullTree.length == 2001);

    Arena live, scratch;
    RecordBuffer buffer;
    buffer.arena = &live;
    assert(store.restore(buffer, fullTree, scratch));
    assert(buffer.length == 2001);

    // Verify all 2,000 children point to parent 0
    foreach (i; 1 .. 2001) {
        assert(buffer.nodes[i].parent == 0);
    }
    printf("3. many siblings passed\n");
}

/// 4. suppressRecords: probe lookahead with left recursion
private void testSuppressRecords() @nogc nothrow {
    ParseContext flatContext, sharedContext;
    version (NPeggedSharedOutput)
        sharedContext.sharedOutput = true;

    string input = "n+n+n+n+n+n+n";
    auto flatResult = parseRecords!(ProbeLR.opCall, exprSelector)(flatContext, input);
    auto sharedResult = parseRecords!(ProbeLR.opCall, exprSelector)(sharedContext, input);

    assert(flatResult.successful && sharedResult.successful);
    assert(flatResult.status == Status.ok && sharedResult.status == Status.ok);
    assert(flatResult.end == sharedResult.end);
    compareTrees(flatResult.nodes, sharedResult.nodes);
    printf("4. suppressRecords passed\n");
}

/// 5. Truncation and resource limits: memory exhaustion during freeze, join, and restore.
private void testResourceLimits() @nogc nothrow {
    // 5a. Freeze memory limit
    Arena tightArena;
    tightArena.limit = 64; // Too small for 100 CompactNodes
    SharedRecordStore tightStore;
    tightStore.arena = &tightArena;
    CompactNode[100] nodes;
    auto freezeFailed = tightStore.freeze(RecordSnapshot(nodes[], 0));
    assert(!freezeFailed.length);
    assert(tightStore.status == Status.resourceLimit);

    // 5b. Join memory limit
    Arena okArena, unavailable;
    unavailable.limit = 0;
    SharedRecordStore okStore, cannotJoin;
    okStore.arena = &okArena;
    cannotJoin.arena = &unavailable;
    CompactNode[1] dummy;
    auto s1 = okStore.freeze(RecordSnapshot(dummy[], 0));
    assert(s1.length == 1);
    auto joinFailed = cannotJoin.join(s1, s1);
    assert(!joinFailed.length);
    assert(cannotJoin.status == Status.resourceLimit);

    // 5c. Restore memory limit with sticky rollback
    Arena scratchArena, destArena;
    destArena.limit = 4096;
    SharedRecordStore replayStore;
    replayStore.arena = &scratchArena;
    CompactNode[200] bulkNodes;
    auto bulkSnapshot = replayStore.freeze(RecordSnapshot(bulkNodes[], 0));
    assert(bulkSnapshot.length == 200);

    RecordBuffer limitedBuffer;
    limitedBuffer.arena = &destArena;
    assert(limitedBuffer.put(CompactNode(99, 0, 1, size_t.max)) == 0);

    // Restore must fail due to destArena limit, roll back, and leave status sticky
    Arena replayScratch;
    assert(!replayStore.restore(limitedBuffer, bulkSnapshot, replayScratch));
    assert(limitedBuffer.length == 1); // Rolled back to checkpoint
    assert(limitedBuffer.status == Status.resourceLimit);
    assert(limitedBuffer.put(CompactNode(1, 1, 2, size_t.max)) == size_t.max); // Sticky
    printf("5. truncation and resource limits passed\n");
}

/// 6. Failed restores: forward parent references, out-of-bounds destination parents.
private void testFailedRestores() @nogc nothrow {
    Arena live, owner, scratch;
    SharedRecordStore store;
    store.arena = &owner;
    RecordBuffer buffer;
    buffer.arena = &live;

    // Forward parent index: node 0 points to node 1 (invalid)
    CompactNode[2] forwardParent = [CompactNode(1, 0, 1, 1), CompactNode(2, 1, 2, size_t.max)];
    assert(!buffer.restore(RecordSnapshot(forwardParent[], 0)));
    assert(buffer.status == Status.invalidInput);
    assert(buffer.length == 0);

    // Out-of-bounds destination parent
    RecordBuffer fresh;
    fresh.arena = &live;
    fresh.parent = 500; // Destination has 0 nodes, parent 500 is illegal
    CompactNode[1] validNode = [CompactNode(1, 0, 1, size_t.max)];
    auto validSnapshot = store.freeze(RecordSnapshot(validNode[], 0));
    assert(!store.restore(fresh, validSnapshot, scratch));
    assert(fresh.status == Status.invalidInput);
    assert(fresh.length == 0);
    printf("6. failed restores passed\n");
}

/// 7. Alternating selected/non-selected nodes
private void testAlternatingSelectedNodes() @nogc nothrow {
    ParseContext flatContext, sharedContext;
    version (NPeggedSharedOutput)
        sharedContext.sharedOutput = true;

    char[128] input;
    size_t pos = 0;
    foreach (i; 0 .. 30) {
        if (i > 0)
            input[pos++] = '+';
        input[pos++] = 'n';
    }
    string exprStr = cast(string)input[0 .. pos];

    auto flatResult = parseRecords!(AlternatingLR.opCall, alternatingSelector)(flatContext, exprStr);
    auto sharedResult = parseRecords!(AlternatingLR.opCall, alternatingSelector)(sharedContext, exprStr);

    assert(flatResult.successful && sharedResult.successful);
    assert(flatResult.status == Status.ok && sharedResult.status == Status.ok);
    assert(flatResult.end == sharedResult.end);
    compareTrees(flatResult.nodes, sharedResult.nodes);
    printf("7. alternating selected/nonselected passed\n");
}

/// 8. Late failure: 50 recursive matches then unexpected syntax error.
private void testLateFailure() @nogc nothrow {
    ParseContext flatContext, sharedContext;
    version (NPeggedSharedOutput)
        sharedContext.sharedOutput = true;

    // 50 valid recursive additions followed by invalid character '!'
    char[256] input;
    size_t pos = 0;
    foreach (i; 0 .. 50) {
        if (i > 0)
            input[pos++] = '+';
        input[pos++] = 'n';
    }
    input[pos++] = '!';
    string badInput = cast(string)input[0 .. pos];

    auto flatResult = parseRecords!(NestedLR.opCall, exprSelector)(flatContext, badInput);
    auto sharedResult = parseRecords!(NestedLR.opCall, exprSelector)(sharedContext, badInput);

    assert(!flatResult.successful && !sharedResult.successful);
    assert(flatResult.status == sharedResult.status);
    assert(flatResult.end == sharedResult.end);
    assert(flatResult.failEnd == sharedResult.failEnd);
    printf("8. late failure passed\n");
}

/// 9. Cross-parse owner destruction: verifying arena memory isolation and requested vs retained bytes.
private void testCrossParseDestruction() @nogc nothrow {
    ParseContext context;
    version (NPeggedSharedOutput)
        context.sharedOutput = true;

    size_t retainedFirst, requestedFirst;
    {
        auto result1 = parseRecords!(NestedLR.opCall, exprSelector)(context, "n+n*n+n");
        assert(result1.successful);
        retainedFirst = result1.arena.used;
        requestedFirst = result1.arena.requestedBytes;
        assert(retainedFirst >= requestedFirst);
        // result1 goes out of scope and frees its arenas
    }

    {
        auto result2 = parseRecords!(NestedLR.opCall, exprSelector)(context, "n+n*n+n");
        assert(result2.successful);
        assert(result2.arena.used == retainedFirst);
        assert(result2.arena.requestedBytes == requestedFirst);
    }
    printf("9. cross-parse owner destruction passed\n");
}

/// 10. Oversized offsets / parent indices boundary tests
private void testOversizedOffsets() @nogc nothrow {
    Arena live, owner;
    SharedRecordStore store;
    store.arena = &owner;
    RecordBuffer buffer;
    buffer.arena = &live;

    // CompactNode with parent = size_t.max - 1
    CompactNode badParent = CompactNode(1, 0, 10, size_t.max - 1);
    assert(buffer.put(badParent) == size_t.max);
    assert(buffer.status == Status.invalidInput);

    // SharedRecordStore.join attachment out of bounds
    CompactNode[1] node = [CompactNode(1, 0, 10, size_t.max)];
    auto leaf = store.freeze(RecordSnapshot(node[], 0));
    assert(leaf.length == 1);
    auto badJoin = store.join(leaf, leaf, 5); // attachment 5 >= left.length 1
    assert(!badJoin.length);
    assert(store.status == Status.invalidInput);
    printf("10. oversized offsets and parent indices passed\n");
}

int main() @nogc nothrow {
    alarm(60);
    testRepeatedFrozenSeed();
    testNestedLeftRecursion();
    testManySiblings();
    testSuppressRecords();
    testResourceLimits();
    testFailedRestores();
    testAlternatingSelectedNodes();
    testLateFailure();
    testCrossParseDestruction();
    testOversizedOffsets();
    printf("All P12 fragment audit tests passed successfully!\n");
    return 0;
}
