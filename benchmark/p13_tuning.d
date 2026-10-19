// C01 repairs activation; these legacy single-batch timings are not the crossover evidence.
module benchmark.p13_tuning;

version (NPeggedSharedOutput) {
} else {
    static assert(0, "C01 repaired shared-output harness requires NPeggedSharedOutput");
}

import npegged.grammar;
import npegged.examples.json : JSON;
import npegged.examples.csv : CSV;
import core.stdc.stdio : printf;
import core.stdc.stdlib : abort;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;
import core.sys.posix.unistd : alarm;

private ulong now() @nogc nothrow {
    timespec ts;
    return clock_gettime(CLOCK_MONOTONIC, &ts) ? 0 : cast(ulong)ts.tv_sec * 1_000_000_000 + ts
        .tv_nsec;
}

mixin(grammar!(Memoization.selective, selectDensity2, ParserBackend.direct)(`
DirectChain:
    Root <- Expr eoi
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));

mixin(grammar!(Memoization.selective, selectDensity4, ParserBackend.direct)(`
DenseChain:
    Root <- Expr eoi
    Expr <- Expr '+' Term / Term
    Term <- Mul / Atom
    Mul <- Term '*' Atom
    Atom <- Number
    Number <- ~[0-9]+
`));

private uint selectDensity2(string name) @nogc nothrow pure {
    if (name.length >= 5 && name[$ - 5 .. $] == ".Expr")
        return 0;
    if (name.length >= 7 && name[$ - 7 .. $] == ".Number")
        return 1;
    return uint.max;
}

private uint selectDensity4(string name) @nogc nothrow pure {
    if (name.length >= 5 && name[$ - 5 .. $] == ".Expr")
        return 0;
    if (name.length >= 5 && name[$ - 5 .. $] == ".Term")
        return 1;
    if (name.length >= 4 && name[$ - 4 .. $] == ".Mul")
        return 2;
    if (name.length >= 7 && name[$ - 7 .. $] == ".Number")
        return 3;
    return uint.max;
}

private uint selectControl(string name) @nogc nothrow pure {
    return 0;
}

private void benchRecursive(alias Parser, alias Selector)(string name, string input, size_t warmup, size_t runs) @nogc nothrow {
    ParseContext ctx;
    ctx.stepLimit = ctx.depthLimit = ctx.memoryLimit = size_t.max;
    version (NPeggedMetrics) {
        ParseMetrics metrics;
        ctx.metrics = &metrics;
    }
    version (NPeggedSharedOutput)
        ctx.sharedOutput = true;

    auto flatContext = ctx;
    version (NPeggedSharedOutput)
        flatContext.sharedOutput = false;
    version (NPeggedMetrics)
        flatContext.metrics = null;
    auto flat = parseRecords!(Parser.opCall, Selector)(flatContext, input, size_t.max);
    auto active = parseRecords!(Parser.opCall, Selector)(ctx, input, size_t.max);
    if (flat.status != active.status || flat.successful != active.successful || flat.end != active.end
            || flat.failEnd != active.failEnd || flat.nodes != active.nodes)
        abort();
    foreach (_; 0 .. warmup) {
        auto res = parseRecords!(Parser.opCall, Selector)(ctx, input, size_t.max);
        assert(res.successful);
    }

    ulong totalNs = 0;
    foreach (_; 0 .. runs) {
        auto t0 = now();
        auto res = parseRecords!(Parser.opCall, Selector)(ctx, input, size_t.max);
        auto t1 = now();
        assert(res.successful);
        totalNs += (t1 - t0);
    }
    printf(
            "%s: %llu ns mean over %llu runs (construction only; no timing claim in metrics builds)\n",
            name.ptr, cast(ulong)(totalNs / runs), cast(ulong)runs);
    version (NPeggedMetrics)
        version (NPeggedSharedOutput) {
            static if (__traits(hasMember, Parser, "npeggedSharedOutputEligible")) {
                static if (Parser.npeggedSharedOutputEligible)
                    if (flat.nodes.length >= 128 && !metrics.output.sharedSnapshots)
                        abort();
            }
            printf("activation %s: snapshots=%llu replays=%llu reused=%llu frozen=%llu\n",
                    name.ptr, metrics.output.sharedSnapshots,
                    metrics.output.sharedReplays,
                    metrics.output.sharedReusedNodes, metrics.output.sharedFrozenNodes);
        }
}

int main() @nogc nothrow {
    alarm(60);

    // 1. DirectChain depth 256
    char[2048] direct256;
    size_t pos = 0;
    foreach (i; 0 .. 256) {
        if (i > 0)
            direct256[pos++] = '+';
        direct256[pos++] = '1';
    }
    benchRecursive!(DirectChain, selectDensity2)("DirectChain-d256", cast(string)direct256[0 .. pos], 5,
            20);

    // 2. DenseChain depth 64
    char[2048] dense64;
    pos = 0;
    foreach (i; 0 .. 64) {
        if (i > 0)
            dense64[pos++] = '+';
        dense64[pos++] = '1';
        dense64[pos++] = '*';
        dense64[pos++] = '2';
    }
    benchRecursive!(DenseChain, selectDensity4)("DenseChain-d64", cast(string)dense64[0 .. pos], 5, 20);

    // 3. DenseChain depth 256
    char[4096] dense256;
    pos = 0;
    foreach (i; 0 .. 256) {
        if (i > 0)
            dense256[pos++] = '+';
        dense256[pos++] = '1';
        dense256[pos++] = '*';
        dense256[pos++] = '2';
    }
    benchRecursive!(DenseChain, selectDensity4)("DenseChain-d256", cast(string)dense256[0 .. pos], 3, 10);

    // 4. Flat controls: JSON & CSV
    string jsonInput = `{"name": "test", "val": [1, 2, 3], "nested": {"a": true, "b": null}}`;
    benchRecursive!(JSON, selectControl)("JSON-control", jsonInput, 50, 1000);

    string csvInput = "1,2,3,4\n5,6,7,8\n9,10,11,12\n";
    benchRecursive!(CSV, selectControl)("CSV-control", csvInput, 50, 1000);

    return 0;
}
