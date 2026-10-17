/** R04: diagnostic record work, never used as a timing cohort. */
module benchmark.diagnostics.record_copying;
import npegged.grammar;
import npegged.records : CompactNode;
import core.stdc.stdio : printf;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
version (NPeggedFullMemo)
    private enum memo = Memoization.yes;
else
    private enum memo = Memoization.selective;
private uint selection(string name) @nogc nothrow pure {
    version (RootOnly) {
        return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : uint.max;
    } else
        return 0;
}

mixin(grammar!(memo, selection, backend)(`
DirectChain:
    Root <- Expr eoi
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));
mixin(grammar!(memo, selection, backend)(`
IndirectChain:
    Root <- Expr eoi
    Expr <- Sum / Number
    Sum <- Expr '+' Number
    Number <- ~[0-9]+
`));
private template Types(T...) {
    alias Types = T;
}

int main() @nogc nothrow {
    char[4096] bytes;
    foreach (i, ref c; bytes)
        c = i % 2 ? '+' : '1';
    printf("grammar,terms,valid,output_nodes,logical_bytes,parse_requested,output_requested,parse_peak,output_peak,snapshot_calls,snapshot_nodes,snapshot_bytes,restore_calls,restore_nodes,restore_bytes,growth_copy_bytes,end,fail_end\n");
    static foreach (Parser; Types!(DirectChain, IndirectChain)) {
        foreach (n; [16, 32, 64, 128, 256, 512, 1024, 2048]) {
            foreach (valid; [true, false]) {
                ParseContext context;
                context.stepLimit = size_t.max;
                context.memoryLimit = 2UL * 1024 * 1024 * 1024;
                ParseMetrics metrics;
                context.metrics = &metrics;
                auto result = parseRecords!(Parser.opCall, selection)(context,
                        cast(string)bytes[0 .. n * 2 - (valid ? 1 : 0)], 1024UL * 1024 * 1024);
                if (result.status != (valid ? Status.ok : Status.mismatch) || result.successful != valid)
                    return 2;
                if (valid && result.nodes.length == 0)
                    return 3;
                if (metrics.snapshotBytes != metrics.output.snapshotBytes)
                    return 4;
                printf("%s,%u,%u,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu\n",
                        (Parser.stringof ~ "\0").ptr, cast(uint)n, cast(uint)valid,
                        cast(ulong)result.nodes.length,
                        cast(ulong)(result.nodes.length * CompactNode.sizeof),
                        cast(ulong)result.arena.requestedBytes,
                        cast(ulong)result.outputArena.requestedBytes,
                        cast(ulong)result.arena.used, cast(ulong)result.outputArena.used,
                        metrics.output.snapshotCalls,
                        metrics.output.snapshotNodes, metrics.output.snapshotBytes,
                        metrics.output.restoreCalls,
                        metrics.output.restoreNodes, metrics.output.restoreBytes,
                        metrics.output.growthCopyBytes,
                        cast(ulong)result.end, cast(ulong)result.failEnd);
            }
        }
    }
    return 0;
}
