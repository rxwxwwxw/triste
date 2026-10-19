/** R06 equal-output parser experiment. Instrumented builds never supply timings. */
module benchmark.diagnostics.shared_output;
import npegged.grammar;
import npegged.examples.json : JSON;
import npegged.examples.csv : CSV;
import npegged.examples.PEG : PEG;
import benchmark.measurement : opaqueInput, consume;
import core.stdc.stdio : printf, fprintf, stderr;
import core.stdc.stdlib : getenv;

private __gshared bool sharedRequested;
private __gshared bool finiteBudgets;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
version (NPeggedFullMemo)
    private enum memo = Memoization.yes;
else
    private enum memo = Memoization.selective;
private uint selected(string name) @nogc nothrow pure {
    version (ExprOnly)
        return name.length >= 5 && name[$ - 5 .. $] == ".Expr" ? 0 : uint.max;
    else version (RootOnly)
        return (name.length >= 5 && name[$ - 5 .. $] == ".Root") || name == "JSON.JSONObject"
            || name == "CSV.CsvFile" || name == "PEG.Grammar" ? 0 : uint.max;
    else
        return 0;
}

mixin(grammar!(memo, selected, backend)(`
DirectChain:
    Root <- Expr eoi
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));
mixin(grammar!(memo, selected, backend)(`
IndirectChain:
    Root <- Expr eoi
    Expr <- Sum / Number
    Sum <- Expr '+' Number
    Number <- ~[0-9]+
`));
mixin(grammar!(memo, selected, backend)(`
NestedChain:
    Root <- Expr eoi
    Expr <- Expr '+' Atom / Atom
    Atom <- '(' Expr ')' / Number
    Number <- ~[0-9]+
`));
private ulong now() @nogc nothrow {
    timespec ts;
    return clock_gettime(CLOCK_MONOTONIC, &ts) ? 0 : cast(ulong)ts.tv_sec * 1_000_000_000 + ts
        .tv_nsec;
}

version (NPeggedMetrics) {
    private enum samples = 1;
    private enum iterations = 1;
} else {
    private enum samples = 7;
    private enum iterations = 4;
}
private int run(alias Parser)(string input, string shape, size_t size, bool valid, string label = "") @nogc nothrow {
    enum defaultName = __traits(parent, Parser).stringof;
    const grammarName = label.length ? label : defaultName;
    // Keep ordinary finite-limit controls below known depth/memory ceilings.
    if (finiteBudgets && shape != "control" && size > 128)
        return 0;
    alias Owner = __traits(parent, Parser);
    static if (__traits(hasMember, Owner, "npeggedSharedOutputEligible"))
        enum eligible = Owner.npeggedSharedOutputEligible;
    else
        enum eligible = false;
    version (NPeggedSharedOutput)
        const policySelected = eligible && sharedRequested && !finiteBudgets;
    else
        enum policySelected = false;
    foreach (batch; 0 .. samples + 1) {
        ParseContext context;
        if (!finiteBudgets)
            context.stepLimit = context.depthLimit = context.memoryLimit = size_t.max;
        version (NPeggedSharedOutput)
            context.sharedOutput = sharedRequested;
        version (NPeggedMetrics) {
            ParseMetrics metrics;
            context.metrics = &metrics;
        }
        size_t peak, requested, nodes, end, failEnd;
        size_t parsePeak, outputPeak, parseRequested, outputRequested, allocations;
        ulong hash;
        const start = now();
        if (!start)
            return 4;
        foreach (_; 0 .. iterations) {
            auto result = parseRecords!(Parser, selected)(context, opaqueInput(input),
                    finiteBudgets ? 256 * 1024 * 1024 : size_t.max);
            if (result.status != (valid ? Status.ok : Status.mismatch) || result.successful != valid)
                return 2;
            hash = 5381;
            foreach (node; result.nodes)
                hash = hash * 33 + node.kind + node.begin * 3 + node.end * 7 + node.parent * 11;
            peak = result.arena.used + result.outputArena.used;
            requested = result.arena.requestedBytes + result.outputArena.requestedBytes;
            parsePeak = result.arena.used;
            outputPeak = result.outputArena.used;
            parseRequested = result.arena.requestedBytes;
            outputRequested = result.outputArena.requestedBytes;
            allocations = result.arena.allocationCalls + result.outputArena.allocationCalls;
            nodes = result.nodes.length;
            end = result.end;
            failEnd = result.failEnd;
            consume(result.successful, hash, nodes, result.status);
            assert(result.input == input);
            assert(!input.length || result.input.ptr != input.ptr);
            version (NPeggedMetrics) {
                if (batch) {
                    fprintf(stderr, "%.*s,%.*s,%llu,%u,%u,%llu,%llu", cast(int)grammarName.length,
                            grammarName.ptr, cast(int)shape.length, shape.ptr, cast(ulong)size,
                            cast(uint)valid, cast(uint)result.status, cast(ulong)end, cast(ulong)failEnd);
                    foreach (node; result.nodes)
                        fprintf(stderr, ",%u:%llu:%llu:%llu", node.kind, cast(ulong)node.begin,
                                cast(ulong)node.end, cast(ulong)node.parent);
                    fprintf(stderr, "\n");
                }
            }
        }
        const stop = now();
        if (stop <= start)
            return 4;
        const elapsed = stop - start;
        if (batch == 0)
            continue; // Separate warmup batch, never emitted as a timing sample.
        const sample = batch - 1;
        printf("%.*s,%.*s,%llu,%u,%u,%u,%llu,%llu,%llu,%llu,%llu,%llu,%llu",
                cast(int)grammarName.length,
                grammarName.ptr, cast(int)shape.length, shape.ptr, cast(ulong)size,
                cast(uint)valid, cast(uint)sample, cast(uint)iterations, elapsed, cast(ulong)peak,
                cast(ulong)requested, cast(ulong)nodes, cast(ulong)end, cast(ulong)failEnd, hash);
        printf(",%llu,%llu,%llu,%llu,%llu,%llu", cast(ulong)parsePeak, cast(ulong)outputPeak,
                cast(ulong)parseRequested, cast(ulong)outputRequested, cast(ulong)allocations,
                cast(ulong)input.length);
        printf(",%u,%u,%u", cast(uint)finiteBudgets, cast(uint)eligible, cast(uint)policySelected);
        version (NPeggedMetrics) {
            ulong sharedSnapshots, reused, frozen, replays;
            version (NPeggedSharedOutput) {
                sharedSnapshots = metrics.output.sharedSnapshots;
                reused = metrics.output.sharedReusedNodes;
                frozen = metrics.output.sharedFrozenNodes;
                replays = metrics.output.sharedReplays;
            }
            if (metrics.snapshotBytes != metrics.output.snapshotBytes)
                return 3;
            printf(",%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu", metrics.snapshotBytes,
                    metrics.output.restoreBytes,
                    metrics.output.growthCopyBytes,
                    metrics.invalidationVisits, sharedSnapshots, reused, frozen, replays);
        }
        printf("\n");
    }
    return 0;
}

int main() @nogc nothrow {
    auto choice = getenv("NPEGGED_SHARED_OUTPUT");
    sharedRequested = choice !is null && choice[0] == '1';
    auto budgets = getenv("NPEGGED_FINITE_BUDGETS");
    finiteBudgets = budgets !is null && budgets[0] == '1';
    printf("grammar,shape,size,valid,sample,iterations,ns,peak,requested,nodes,end,fail_end,hash,parse_peak,output_peak,parse_requested,output_requested,allocations,input_bytes,finite_budgets,grammar_eligible,policy_selected");
    version (NPeggedMetrics)
        printf(",snapshot_bytes,restore_bytes,growth_copy_bytes,invalidation_visits,shared_snapshots,reused_nodes,frozen_nodes,shared_replays");
    printf("\n");
    char[8192] bytes;
    foreach (i, ref c; bytes)
        c = i % 2 ? '+' : '1';
    foreach (n; [16, 32, 64, 128, 256, 512, 1024, 2048])
        foreach (valid; [true, false]) {
            auto input = cast(string)bytes[0 .. n * 2 - (valid ? 1 : 0)];
            if (auto error = run!(DirectChain.opCall)(input, "flat", n, valid))
                return error;
            if (auto error = run!(IndirectChain.opCall)(input, "flat", n, valid))
                return error;
        }
    foreach (n; [16, 32, 64, 128, 256, 512]) {
        foreach (i; 0 .. n)
            bytes[i * 6 .. i * 6 + 6] = "(1+1)+";
        foreach (valid; [true, false])
            if (auto error = run!(NestedChain.opCall)(cast(string)bytes[0 .. n * 6 - (valid ? 1 : 0)],
                    "siblings", n, valid))
                return error;
    }
    foreach (depth; 0 .. 9) {
        size_t length;
        foreach (_; 0 .. depth)
            bytes[length++] = '(';
        bytes[length .. length + 3] = "1+1";
        length += 3;
        foreach (_; 0 .. depth)
            bytes[length++] = ')';
        bytes[length] = '+';
        foreach (valid; [true, false])
            if (auto error = run!(NestedChain.opCall)(cast(string)bytes[0 .. length + (valid ? 0 : 1)],
                    "depth", depth, valid))
                return error;
    }
    enum json = `{"a":[1,true,null],"b":"x"}`;
    enum csv = "a,b,c\n1,2,3\n";
    enum peg = "Start <- 'a'";
    static foreach (valid; [true, false]) {
        if (auto error = run!(and!(JSON.opCall, eoi))(json ~ (valid ? "" : "@"), "control",
                json.length, valid, "JSON"))
            return error;
        if (auto error = run!(and!(CSV.opCall, eoi))(csv ~ (valid ? "" : "\""), "control", csv.length,
                valid, "CSV"))
            return error;
        if (auto error = run!(and!(PEG.opCall, eoi))(peg ~ (valid ? "" : "@"), "control", peg.length, valid,
                "PEG"))
            return error;
    }
    return 0;
}
