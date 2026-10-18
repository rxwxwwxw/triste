module benchmark.diagnostics.pure_islands;
import tests.pure_islands : Candidate, selected, Effects;
import npegged.grammar;
import npegged.examples.json : JSON;
import npegged.examples.csv : CSV;
import npegged.examples.PEG : PEG;
import benchmark.measurement : opaqueInput, consume;
import core.stdc.stdio : printf;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;

private ulong now() @nogc nothrow {
    timespec value;
    return clock_gettime(CLOCK_MONOTONIC, &value) ? 0 : cast(ulong)value.tv_sec * 1_000_000_000 + value
        .tv_nsec;
}

private ulong bytesHash(string bytes) @nogc nothrow {
    ulong hash = 5381;
    foreach (b; bytes)
        hash = hash * 33 + cast(ubyte)b;
    return hash;
}

private ulong treeHash(scope const ref ParseTree tree) @nogc nothrow {
    ulong hash = bytesHash(tree.name) + tree.begin * 3 + tree.end * 7 + tree.failEnd * 11 + tree
        .successful;
    foreach (match; tree.matches)
        hash = hash * 33 + bytesHash(match);
    foreach (child; tree.children)
        hash = hash * 33 + treeHash(child);
    foreach (child; tree.failedChild)
        hash = hash * 33 + treeHash(child);
    return hash;
}

private int run(alias parser, int mode)(string input, string label, size_t size, bool valid, bool finite = false) @nogc nothrow {
    version (NPeggedMetrics)
        enum samples = 1;
    else
        enum samples = 7;
    version (NPeggedMetrics)
        const iterations = 1;
    else
        const iterations = size <= 64 ? 256 : 16;
    version (NPeggedMetrics)
        const warmup = 0;
    else
        const warmup = size <= 64 ? 64 : 16;
    foreach (sample; 0 .. samples) {
        ParseContext context;
        context.memoryLimit = finite ? 256 * 1024 * 1024 : size_t.max;
        context.depthLimit = finite ? 1024 : size_t.max;
        context.stepLimit = finite ? 1_000_000 : size_t.max;
        Effects effects;
        context.userData = &effects;
        version (NPeggedMetrics) {
            ParseMetrics metrics;
            context.metrics = &metrics;
        }
        size_t peak, requested, allocations, nodes, end, failEnd, actions;
        ulong hash, start;
        foreach (iteration; 0 .. iterations + warmup) {
            if (iteration == warmup)
                start = now();
            effects.length = 0;
            static if (mode == 0)
                auto result = check!parser(context, opaqueInput(input));
            else static if (mode == 3)
                auto result = parse!parser(context, opaqueInput(input));
            else
                auto result = parseRecords!(parser, selected, mode == 2)(context,
                        opaqueInput(input), finite ? 256 * 1024 * 1024 : size_t.max);
            if (result.status != (valid ? Status.ok : Status.mismatch) || result.successful != valid)
                return 2;
            peak = result.arena.used;
            requested = result.arena.requestedBytes;
            allocations = result.arena.allocationCalls;
            hash = result.end * 3 + result.failEnd * 7 + cast(ulong)result.status;
            static if (mode == 1 || mode == 2) {
                peak += result.outputArena.used;
                requested += result.outputArena.requestedBytes;
                allocations += result.outputArena.allocationCalls;
                nodes = result.nodes.length;
                foreach (node; result.nodes)
                    hash = hash * 33 + node.kind + node.begin * 3 + node.end * 7 + node.parent * 11;
            } else static if (mode == 3)
                hash = treeHash(result.tree);
            end = result.end;
            failEnd = result.failEnd;
            actions = effects.length;
            foreach (event; effects.events[0 .. effects.length])
                hash = hash * 33 + bytesHash(event.name) + event.position + event.steps * 3 + event
                    .depth * 7;
            consume(result.successful, hash, nodes, result.status);
        }
        const stop = now();
        if (!start || stop <= start)
            return 3;
        printf("%.*s,%u,%llu,%u,%u,%u,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu",
                cast(int)label.length, label.ptr, cast(uint)mode, cast(ulong)size, cast(uint)valid,
                cast(uint)finite, cast(uint)sample, cast(ulong)iterations, stop - start,
                cast(ulong)peak, cast(ulong)requested, cast(ulong)allocations, cast(ulong)nodes,
                cast(ulong)end, cast(ulong)failEnd, hash, cast(ulong)actions);
        version (NPeggedMetrics) {
            ulong entries, fallbacks;
            version (NPeggedPureIslands) {
                entries = metrics.pureIslandEntries;
                fallbacks = metrics.pureIslandFallbacks;
            }
            printf(",%llu,%llu,%llu,%llu", entries, fallbacks, metrics.memoCalls, metrics.memoHits);
        }
        printf("\n");
    }
    return 0;
}

int main() @nogc nothrow {
    printf("case,mode,size,valid,finite,sample,iterations,ns,peak,requested,allocations,nodes,end,fail_end,hash,actions");
    version (NPeggedMetrics)
        printf(",island_entries,island_fallbacks,memo_calls,memo_hits");
    printf("\n");
    char[8192] bytes = 'a';
    foreach (n; [16, 64, 256, 1024])
        foreach (finite; [false, true])
            foreach (valid; [true, false]) {
                bytes[0] = valid ? 'a' : '!';
                static foreach (mode; [0, 1, 2])
                    if (auto error = run!(Candidate.Identifier, mode)(cast(string)bytes[0 .. n],
                            "Identifier", n, valid, finite))
                        return error;
            }
    foreach (n; [0, 16, 256])
        foreach (finite; [false, true]) {
            bytes[0 .. n] = ' ';
            static foreach (mode; [0, 2])
                if (auto error = run!(Candidate.Whitespace, mode)(cast(string)bytes[0 .. n],
                        "Whitespace", n, true, finite))
                    return error;
        }
    foreach (words; [1, 16, 128])
        foreach (finite; [false, true])
            foreach (valid; [true, false]) {
                foreach (i; 0 .. words)
                    bytes[i * 4 .. i * 4 + 4] = "abc ";
                bytes[words * 4] = '!';
                auto input = cast(string)bytes[0 .. words * 4 + (valid ? 0 : 1)];
                static foreach (mode; [0, 1, 2, 3])
                    if (auto error = run!(Candidate.Root, mode)(input, "Root", words, valid, finite))
                        return error;
                if (auto error = run!(Candidate.ActRoot, 0)(input, "ActRoot", words, valid, finite))
                    return error;
            }
    enum json = `{"a":[1,true,null],"b":"x"}`;
    enum csv = "a,b,c\n1,2,3\n";
    enum peg = "Start <- 'a'";
    static foreach (valid; [true, false]) {
        if (auto error = run!(and!(JSON.opCall, eoi), 0)(json ~ (valid ? "" : "@"), "JSON", json
                .length, valid))
            return error;
        if (auto error = run!(and!(CSV.opCall, eoi), 0)(csv ~ (valid ? "" : "\""), "CSV", csv.length, valid))
            return error;
        if (auto error = run!(and!(PEG.opCall, eoi), 0)(peg ~ (valid ? "" : "@"), "PEG", peg.length, valid))
            return error;
    }
    return 0;
}
