// C01 repairs activation; use scripts/c01_shared_output.py for repeated, interleaved timing.
module benchmark.p09_crossover;

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

private struct Projection(alias Selector) {
    // Grammars for P09 Crossover Measurement
    mixin(grammar!(Memoization.selective, Selector, ParserBackend.direct)(`
DirectChain:
    Root <- Expr eoi
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));

    mixin(grammar!(Memoization.selective, Selector, ParserBackend.direct)(`
IndirectChain:
    Root <- Expr eoi
    Expr <- Sum / Number
    Sum <- Expr '+' Number
    Number <- ~[0-9]+
`));

    mixin(grammar!(Memoization.selective, Selector, ParserBackend.direct)(`
DenseChain:
    Root <- Expr eoi
    Expr <- Expr '+' Term / Term
    Term <- Mul / Atom
    Mul <- Term '*' Atom
    Atom <- Number
    Number <- ~[0-9]+
`));

    mixin(grammar!(Memoization.selective, Selector, ParserBackend.direct)(`
MixedChain:
    Root <- Header Expr eoi
    Header <- 'H' 'E' 'A' 'D' ';'
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));

}

// Selectors for Densities 0, 1, 2, 4
// Density 0: Root only (0 nodes per growth)
private uint selectDensity0(string name) @nogc nothrow pure {
    return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : uint.max;
}

// Density 1: 1 node per growth (Number / Atom only)
private uint selectDensity1(string name) @nogc nothrow pure {
    return name.length >= 7 && name[$ - 7 .. $] == ".Number" ? 1 : uint.max;
}

// Density 2: 2 nodes per growth (Expr + Number)
private uint selectDensity2(string name) @nogc nothrow pure {
    if (name.length >= 5 && name[$ - 5 .. $] == ".Expr")
        return 0;
    if (name.length >= 7 && name[$ - 7 .. $] == ".Number")
        return 1;
    return uint.max;
}

// Density 4: 4 nodes per growth (Expr + Term + Mul + Number)
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

// Control selector for JSON / CSV
private uint selectControl(string name) @nogc nothrow pure {
    return 0;
}

// Colocated unittests
@nogc nothrow unittest {
    assert(selectDensity0("DirectChain.Root") == 0);
    assert(selectDensity0("DirectChain.Expr") == uint.max);
    assert(selectDensity1("DirectChain.Number") == 1);
    assert(selectDensity1("DirectChain.Expr") == uint.max);
    assert(selectDensity2("DirectChain.Expr") == 0);
    assert(selectDensity2("DirectChain.Number") == 1);
    assert(selectDensity4("DenseChain.Mul") == 2);
}

// Benchmark runner for a single configuration
private void runCase(alias Parser, alias Selector)(string grammarName, string densityName,
        uint densityNodes, size_t depth, string input, bool valid) @nogc nothrow {
    const size_t iters = depth <= 64 ? 100 : (depth <= 512 ? 25 : 10);

    // Flat baseline (sharedOutput = false)
    ParseContext ctxFlat;
    ctxFlat.stepLimit = ctxFlat.depthLimit = ctxFlat.memoryLimit = size_t.max;
    version (NPeggedSharedOutput)
        ctxFlat.sharedOutput = false;
    version (NPeggedMetrics) {
        ParseMetrics metricsFlat;
        ctxFlat.metrics = &metricsFlat;
    }

    // Warmup flat
    auto resWarmFlat = parseRecords!(Parser, Selector)(ctxFlat, input, size_t.max);
    if (resWarmFlat.status == Status.outOfMemory || resWarmFlat.status == Status.resourceLimit)
        abort();
    assert(resWarmFlat.status == (valid ? Status.ok : Status.mismatch));

    ulong t0 = now();
    foreach (_; 0 .. iters) {
        auto r = parseRecords!(Parser, Selector)(ctxFlat, input, size_t.max);
        assert(r.status == (valid ? Status.ok : Status.mismatch));
    }
    ulong t1 = now();
    ulong flatNs = (t1 - t0) / iters;
    size_t flatPeak = resWarmFlat.arena.used + resWarmFlat.outputArena.used;
    size_t flatReq = resWarmFlat.arena.requestedBytes + resWarmFlat.outputArena.requestedBytes;
    size_t flatNodes = resWarmFlat.nodes.length;

    // Shared Output candidate (sharedOutput = true)
    ParseContext ctxShared;
    ctxShared.stepLimit = ctxShared.depthLimit = ctxShared.memoryLimit = size_t.max;
    version (NPeggedSharedOutput)
        ctxShared.sharedOutput = true;
    version (NPeggedMetrics) {
        ParseMetrics metricsShared;
        ctxShared.metrics = &metricsShared;
    }

    // Warmup shared
    auto resWarmShared = parseRecords!(Parser, Selector)(ctxShared, input, size_t.max);
    if (resWarmShared.status == Status.outOfMemory || resWarmShared.status == Status.resourceLimit)
        abort();
    assert(resWarmShared.status == (valid ? Status.ok : Status.mismatch));
    if (resWarmShared.status != resWarmFlat.status || resWarmShared.end != resWarmFlat.end
            || resWarmShared.failEnd != resWarmFlat.failEnd || resWarmShared.nodes != resWarmFlat
                .nodes)
        abort();

    ulong t2 = now();
    foreach (_; 0 .. iters) {
        auto r = parseRecords!(Parser, Selector)(ctxShared, input, size_t.max);
        assert(r.status == (valid ? Status.ok : Status.mismatch));
    }
    ulong t3 = now();
    ulong sharedNs = (t3 - t2) / iters;
    size_t sharedPeak = resWarmShared.arena.used + resWarmShared.outputArena.used;
    size_t sharedReq = resWarmShared.arena.requestedBytes + resWarmShared.outputArena.requestedBytes;

    ulong sharedSnapshots = 0, reusedNodes = 0, frozenNodes = 0;
    version (NPeggedMetrics) {
        version (NPeggedSharedOutput) {
            sharedSnapshots = metricsShared.output.sharedSnapshots;
            reusedNodes = metricsShared.output.sharedReusedNodes;
            frozenNodes = metricsShared.output.sharedFrozenNodes;
            static if (__traits(hasMember, __traits(parent, Parser), "npeggedSharedOutputEligible")) {
                static if (__traits(parent, Parser).npeggedSharedOutputEligible) // Final output length is not the size of a memo snapshot.
                    if (depth >= 256 && densityNodes && !sharedSnapshots)
                        abort();
            }
        }
    }

    double ratio = cast(double)sharedNs / cast(double)(flatNs ? flatNs : 1);

    printf("%s,%s,%u,%zu,%u,%llu,%llu,%.4f,%zu,%zu,%zu,%zu,%zu,%llu,%llu,%llu\n", grammarName.ptr,
            densityName.ptr,
            densityNodes, depth, valid ? 1 : 0, flatNs, sharedNs, ratio, flatNodes, flatPeak,
            sharedPeak, flatReq, sharedReq, sharedSnapshots, reusedNodes, frozenNodes);
}

int main() @nogc nothrow {
    alarm(120);

    printf("grammar,density,nodes_per_growth,depth,valid,flat_ns,shared_ns,ratio,committed_nodes,flat_peak_bytes,shared_peak_bytes,flat_req_bytes,shared_req_bytes,shared_snapshots,reused_nodes,frozen_nodes\n");

    char[16384] buf;

    // Direct Chain inputs: "1+1+1+..."
    const size_t[6] depths = [16, 64, 256, 512, 1024, 2048];

    // 1. DirectChain across Densities 0, 1, 2
    foreach (d; depths) {
        foreach (i; 0 .. d) {
            buf[i * 2] = '1';
            buf[i * 2 + 1] = '+';
        }
        buf[d * 2 - 1] = '1';
        string validDirect = cast(string)buf[0 .. d * 2 - 1];

        // Density 0 (0 nodes/growth: Root only)
        runCase!(Projection!(selectDensity0).DirectChain.Root, selectDensity0)("DirectChain",
                "density0", 0, d, validDirect, true);
        // Density 1 (1 node/growth: Number)
        runCase!(Projection!(selectDensity1).DirectChain.Root, selectDensity1)("DirectChain",
                "density1", 1, d, validDirect, true);
        // Density 2 (2 nodes/growth: Expr + Number)
        runCase!(Projection!(selectDensity2).DirectChain.Root, selectDensity2)("DirectChain",
                "density2", 2, d, validDirect, true);

        // Late failure on Density 2
        buf[d * 2 - 1] = '!'; // Invalid token at end
        string invalidDirect = cast(string)buf[0 .. d * 2];
        runCase!(Projection!(selectDensity2).DirectChain.Root, selectDensity2)("DirectChain",
                "density2_latefail", 2, d, invalidDirect, false);
    }

    // 2. IndirectChain across Densities 0, 1, 2
    foreach (d; [16, 64, 256, 512, 1024]) {
        foreach (i; 0 .. d) {
            buf[i * 2] = '1';
            buf[i * 2 + 1] = '+';
        }
        buf[d * 2 - 1] = '1';
        string validIndirect = cast(string)buf[0 .. d * 2 - 1];

        runCase!(Projection!(selectDensity0).IndirectChain.Root, selectDensity0)("IndirectChain",
                "density0", 0, d, validIndirect, true);
        runCase!(Projection!(selectDensity1).IndirectChain.Root, selectDensity1)("IndirectChain",
                "density1", 1, d, validIndirect, true);
        runCase!(Projection!(selectDensity2).IndirectChain.Root, selectDensity2)("IndirectChain",
                "density2", 2, d, validIndirect, true);
    }

    // 3. DenseChain for Density 4 (4 nodes/growth: Expr, Term, Mul, Number)
    // Input format: "1*1+1*1+..."
    foreach (d; [16, 64, 256, 512, 1024]) {
        size_t len = 0;
        foreach (i; 0 .. d) {
            buf[len++] = '1';
            buf[len++] = '*';
            buf[len++] = '1';
            if (i + 1 < d)
                buf[len++] = '+';
        }
        string validDense = cast(string)buf[0 .. len];
        runCase!(Projection!(selectDensity4).DenseChain.Root, selectDensity4)("DenseChain",
                "density4", 4, d, validDense, true);
    }

    // 4. MixedChain (Header + Left-recursive body)
    foreach (d; [16, 64, 256, 512, 1024]) {
        buf[0 .. 5] = "HEAD;";
        size_t len = 5;
        foreach (i; 0 .. d) {
            buf[len++] = '1';
            if (i + 1 < d)
                buf[len++] = '+';
        }
        string validMixed = cast(string)buf[0 .. len];
        runCase!(Projection!(selectDensity2).MixedChain.Root, selectDensity2)("MixedChain",
                "density2_mixed", 2, d, validMixed, true);
    }

    // 5. Non-recursive Flat Controls (JSON & CSV)
    enum jsonInput = `{"a":[1,true,null],"b":"x"}`;
    enum csvInput = "a,b,c\n1,2,3\n4,5,6\n";
    runCase!(JSON.JSONObject, selectControl)("JSON", "flat_control", 0, 1, jsonInput, true);
    runCase!(CSV.CsvFile, selectControl)("CSV", "flat_control", 0, 1, csvInput, true);

    return 0;
}
