/** A02 active-path smoke fixtures verifying active optimizations and guarded fallbacks. */
module tests.active_smoke_fixtures;

import core.stdc.stdio : printf, fprintf, stderr;
import core.sys.posix.unistd : alarm;
import npegged.grammar;
import npegged.peg;
import npegged.records : CompactNode;

version (NPeggedSharedOutput) {
} else {
    static assert(0, "active_smoke_fixtures requires version(NPeggedSharedOutput)");
}
version (NPeggedPureIslands) {
} else {
    static assert(0, "active_smoke_fixtures requires version(NPeggedPureIslands)");
}
version (NPeggedMetrics) {
} else {
    static assert(0, "active_smoke_fixtures requires version(NPeggedMetrics)");
}

private uint selectSmoke(string name) @nogc nothrow pure {
    if (name.length >= 5 && name[$ - 5 .. $] == ".Expr")
        return 1;
    if (name.length >= 5 && name[$ - 5 .. $] == ".Leaf")
        return 2;
    if (name.length >= 5 && name[$ - 5 .. $] == ".Root")
        return 0;
    if (name.length >= 10 && name[$ - 10 .. $] == ".PureEntry")
        return 3;
    return 1;
}

// 1. Eligible recursive-record grammar producing snapshots past 4096-byte threshold
mixin(grammar!(Memoization.selective, selectSmoke, ParserBackend.combinators)(`
RecursiveEligible:
    Root <- Expr eoi
    Expr <- Expr '+' Leaf / Leaf
    Leaf <~ [0-9]+
`));

// 2. Known ineligible / flat grammar
mixin(grammar!(Memoization.selective, selectSmoke, ParserBackend.combinators)(`
FlatIneligible:
    Root <- Leaf+ eoi
    Leaf <~ [0-9]+ [ ]*
`));

// 3 & 4. Action grammar with proven eligible pure entry and action rule
private ParseTree smokeAction(bool CT)(ref State!CT state, ParseTree tree) @nogc nothrow {
    return tree;
}

mixin(grammar!(Memoization.selective, selectSmoke, ParserBackend.direct)(`
ActionCandidate:
    Root <- PureEntry+ ActionRule eoi
    PureEntry <~ [a-z]+ [ ]*
    ActionRule <- '!' {smokeAction}
`));

mixin(grammar!(Memoization.selective, selectSmoke, ParserBackend.combinators)(`
ActionReference:
    Root <- PureEntry+ ActionRule eoi
    PureEntry <~ [a-z]+ [ ]*
    ActionRule <- '!' {smokeAction}
`));

private void dummyTrace(string, size_t, bool, void*) @nogc nothrow {
}

private bool nodesEqual(scope const CompactNode[] a, scope const CompactNode[] b) @nogc nothrow pure {
    if (a.length != b.length)
        return false;
    foreach (i; 0 .. a.length) {
        if (a[i].kind != b[i].kind || a[i].begin != b[i].begin || a[i].end != b[i].end || a[i].parent != b[i]
                .parent)
            return false;
    }
    return true;
}

int main() @nogc nothrow {
    alarm(30);

    // ------------------------------------------------------------------------
    // Part 1: Eligible recursive grammar passing 4096-byte threshold
    // ------------------------------------------------------------------------
    static assert(__traits(hasMember, RecursiveEligible, "npeggedSharedOutputEligible"));
    static assert(RecursiveEligible.npeggedSharedOutputEligible,
            "RecursiveEligible must be marked shared-output eligible");

    // Construct an input with 200 terms: "1+1+...+1", producing 200 Leaf + 200 Expr nodes = 400 nodes
    // 400 nodes * 32 bytes/node = 12,800 bytes, well over the 4096-byte (128 node) threshold.
    char[400] recInputBuffer;
    foreach (i; 0 .. 399)
        recInputBuffer[i] = (i % 2 == 0) ? '1' : '+';
    string recInput = cast(string)recInputBuffer[0 .. 399];

    // Reference parse (sharedOutput = false)
    ParseContext ctxRef;
    ctxRef.sharedOutput = false;
    ctxRef.stepLimit = ctxRef.depthLimit = ctxRef.memoryLimit = size_t.max;
    auto refResult = parseRecords!(RecursiveEligible.opCall, selectSmoke)(ctxRef, recInput, size_t
            .max);
    assert(refResult.successful, "Reference recursive parse must succeed");
    assert(refResult.nodes.length >= 128, "Must produce >= 128 nodes");

    // Active shared output parse (sharedOutput = true, unlimited budgets, outputLimit = size_t.max)
    ParseContext ctxActiveShared;
    ParseMetrics metricsShared;
    ctxActiveShared.metrics = &metricsShared;
    ctxActiveShared.sharedOutput = true;
    ctxActiveShared.stepLimit = ctxActiveShared.depthLimit = ctxActiveShared.memoryLimit = size_t.max;
    auto candResult = parseRecords!(RecursiveEligible.opCall, selectSmoke)(ctxActiveShared, recInput, size_t
            .max);
    assert(candResult.successful, "Active shared output parse must succeed");

    // Semantic parity check
    assert(candResult.status == refResult.status, "Status mismatch");
    assert(candResult.end == refResult.end, "End mismatch");
    assert(candResult.failEnd == refResult.failEnd, "FailEnd mismatch");
    assert(candResult.nodes.length == refResult.nodes.length, "Node count mismatch");
    assert(nodesEqual(candResult.nodes, refResult.nodes), "Node content mismatch");

    // Verify active counters: sharedSnapshots > 0 and reused/replays > 0
    assert(metricsShared.output.sharedSnapshots > 0, "sharedSnapshots must be > 0 on active path");
    assert(metricsShared.output.sharedReusedNodes > 0 || metricsShared.output.sharedReplays > 0,
            "sharedReusedNodes or sharedReplays must be > 0 on active path");

    // ------------------------------------------------------------------------
    // Part 2: Known ineligible / flat grammar
    // ------------------------------------------------------------------------
    static assert(!__traits(hasMember, FlatIneligible, "npeggedSharedOutputEligible")
            || !FlatIneligible.npeggedSharedOutputEligible,
            "FlatIneligible must not be marked shared-output eligible");

    char[400] flatInputBuffer;
    foreach (i; 0 .. 399)
        flatInputBuffer[i] = (i % 2 == 0) ? '1' : ' ';
    string flatInput = cast(string)flatInputBuffer[0 .. 399];

    ParseContext ctxFlatActive;
    ParseMetrics metricsFlat;
    ctxFlatActive.metrics = &metricsFlat;
    ctxFlatActive.sharedOutput = true;
    ctxFlatActive.stepLimit = ctxFlatActive.depthLimit = ctxFlatActive.memoryLimit = size_t.max;
    auto flatResult = parseRecords!(FlatIneligible.opCall, selectSmoke)(ctxFlatActive, flatInput, size_t
            .max);
    assert(flatResult.successful, "Flat parse must succeed");
    // Assert that shared snapshots are zero for flat grammar
    assert(metricsFlat.output.sharedSnapshots == 0, "Flat grammar must have sharedSnapshots == 0");
    assert(metricsFlat.output.sharedReplays == 0, "Flat grammar must have sharedReplays == 0");
    assert(metricsFlat.output.sharedReusedNodes == 0, "Flat grammar must have sharedReusedNodes == 0");

    // ------------------------------------------------------------------------
    // Part 3: Proven eligible pure entry in an action grammar
    // ------------------------------------------------------------------------
    static assert(__traits(hasMember, ActionCandidate, "npeggedPureIslandEntries"),
            "ActionCandidate must have npeggedPureIslandEntries");
    bool foundPureEntry;
    foreach (entry; ActionCandidate.npeggedPureIslandEntries) {
        if (entry == "PureEntry")
            foundPureEntry = true;
    }
    assert(foundPureEntry, "PureEntry must be an eligible pure island entry");

    string actionInput = "hello world test !";

    // Candidate parse in active mode (unlimited budgets, trace = null)
    ParseContext ctxActivePure;
    ParseMetrics metricsPure;
    ctxActivePure.metrics = &metricsPure;
    ctxActivePure.stepLimit = ctxActivePure.depthLimit = ctxActivePure.memoryLimit = size_t.max;
    auto pureResult = parseRecords!(ActionCandidate.opCall, selectSmoke)(ctxActivePure, actionInput, size_t
            .max);
    assert(pureResult.successful, "Active pure island parse must succeed");

    // Reference parse (combinators backend)
    ParseContext ctxRefAction;
    ctxRefAction.stepLimit = ctxRefAction.depthLimit = ctxRefAction.memoryLimit = size_t.max;
    auto refActionResult = parseRecords!(ActionReference.opCall, selectSmoke)(ctxRefAction, actionInput,
            size_t.max);
    assert(refActionResult.successful, "Reference action parse must succeed");

    // Semantic parity between candidate and reference
    assert(pureResult.status == refActionResult.status, "Action status mismatch");
    assert(pureResult.end == refActionResult.end, "Action end mismatch");
    assert(pureResult.nodes.length == refActionResult.nodes.length, "Action node count mismatch");
    assert(nodesEqual(pureResult.nodes, refActionResult.nodes), "Action nodes mismatch");

    // Assert active pure-island entries nonzero
    assert(metricsPure.pureIslandEntries > 0, "pureIslandEntries must be > 0 in active mode");

    // ------------------------------------------------------------------------
    // Part 4: Guarded fallbacks with finite limits or tracing
    // ------------------------------------------------------------------------
    // Fallback 4a: Finite stepLimit (10_000_000)
    {
        ParseContext ctxFallback;
        ParseMetrics metricsFallback;
        ctxFallback.metrics = &metricsFallback;
        ctxFallback.stepLimit = 10_000_000;
        ctxFallback.depthLimit = size_t.max;
        ctxFallback.memoryLimit = size_t.max;
        auto res = parseRecords!(ActionCandidate.opCall, selectSmoke)(ctxFallback, actionInput, size_t
                .max);
        assert(res.successful, "Fallback 4a must succeed");
        assert(metricsFallback.pureIslandEntries == 0, "pureIslandEntries must be 0 with finite stepLimit");
        assert(metricsFallback.pureIslandFallbacks > 0, "pureIslandFallbacks must be > 0 with finite stepLimit");
        assert(nodesEqual(res.nodes, refActionResult.nodes), "Fallback 4a node parity");
    }

    // Fallback 4b: Finite depthLimit (1024)
    {
        ParseContext ctxFallback;
        ParseMetrics metricsFallback;
        ctxFallback.metrics = &metricsFallback;
        ctxFallback.stepLimit = size_t.max;
        ctxFallback.depthLimit = 1024;
        ctxFallback.memoryLimit = size_t.max;
        auto res = parseRecords!(ActionCandidate.opCall, selectSmoke)(ctxFallback, actionInput, size_t
                .max);
        assert(res.successful, "Fallback 4b must succeed");
        assert(metricsFallback.pureIslandEntries == 0, "pureIslandEntries must be 0 with finite depthLimit");
        assert(metricsFallback.pureIslandFallbacks > 0, "pureIslandFallbacks must be > 0 with finite depthLimit");
        assert(nodesEqual(res.nodes, refActionResult.nodes), "Fallback 4b node parity");
    }

    // Fallback 4c: Finite memoryLimit (256 MiB)
    {
        ParseContext ctxFallback;
        ParseMetrics metricsFallback;
        ctxFallback.metrics = &metricsFallback;
        ctxFallback.stepLimit = size_t.max;
        ctxFallback.depthLimit = size_t.max;
        ctxFallback.memoryLimit = 256 * 1024 * 1024;
        auto res = parseRecords!(ActionCandidate.opCall, selectSmoke)(ctxFallback, actionInput, size_t
                .max);
        assert(res.successful, "Fallback 4c must succeed");
        assert(metricsFallback.pureIslandEntries == 0, "pureIslandEntries must be 0 with finite memoryLimit");
        assert(metricsFallback.pureIslandFallbacks > 0, "pureIslandFallbacks must be > 0 with finite memoryLimit");
        assert(nodesEqual(res.nodes, refActionResult.nodes), "Fallback 4c node parity");
    }

    // Fallback 4d: Tracing enabled
    {
        ParseContext ctxFallback;
        ParseMetrics metricsFallback;
        ctxFallback.metrics = &metricsFallback;
        ctxFallback.stepLimit = ctxFallback.depthLimit = ctxFallback.memoryLimit = size_t.max;
        ctxFallback.trace = &dummyTrace;
        auto res = parseRecords!(ActionCandidate.opCall, selectSmoke)(ctxFallback, actionInput, size_t
                .max);
        assert(res.successful, "Fallback 4d must succeed");
        assert(metricsFallback.pureIslandEntries == 0, "pureIslandEntries must be 0 with trace != null");
        assert(metricsFallback.pureIslandFallbacks > 0, "pureIslandFallbacks must be > 0 with trace != null");
        assert(nodesEqual(res.nodes, refActionResult.nodes), "Fallback 4d node parity");
    }

    // Fallback 4e: Shared output fallback under finite stepLimit
    {
        ParseContext ctxFallback;
        ParseMetrics metricsFallback;
        ctxFallback.metrics = &metricsFallback;
        ctxFallback.sharedOutput = true;
        ctxFallback.stepLimit = 10_000_000;
        ctxFallback.depthLimit = size_t.max;
        ctxFallback.memoryLimit = size_t.max;
        auto res = parseRecords!(RecursiveEligible.opCall, selectSmoke)(ctxFallback, recInput, size_t
                .max);
        assert(res.successful, "Fallback 4e must succeed");
        assert(metricsFallback.output.sharedSnapshots == 0,
                "sharedSnapshots must be 0 with finite stepLimit even if sharedOutput=true");
        assert(nodesEqual(res.nodes, refResult.nodes), "Fallback 4e node parity");
    }

    // Fallback 4f: Shared output fallback under default finite outputLimit (256 MiB)
    {
        ParseContext ctxFallback;
        ParseMetrics metricsFallback;
        ctxFallback.metrics = &metricsFallback;
        ctxFallback.sharedOutput = true;
        ctxFallback.stepLimit = ctxFallback.depthLimit = ctxFallback.memoryLimit = size_t.max;
        // outputLimit left at default (256 * 1024 * 1024) instead of size_t.max
        auto res = parseRecords!(RecursiveEligible.opCall, selectSmoke)(ctxFallback, recInput);
        assert(res.successful, "Fallback 4f must succeed");
        assert(metricsFallback.output.sharedSnapshots == 0,
                "sharedSnapshots must be 0 with default outputLimit != size_t.max");
        assert(nodesEqual(res.nodes, refResult.nodes), "Fallback 4f node parity");
    }

    printf("A02 active-path smoke fixtures passed (shared output and pure islands verified)\n");
    return 0;
}
