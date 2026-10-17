/** Recognition-only scaling: timing and metric builds are separate cohorts. */
module benchmark.diagnostics.recursion_recognition;
import npegged.grammar;
import benchmark.measurement : opaqueInput, consume;
import core.stdc.stdio : printf;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
version (NPeggedFullMemo)
    private enum memo = Memoization.yes;
else
    private enum memo = Memoization.selective;
mixin(grammar!(memo, void, backend)(`
DirectChain:
    Root <- Expr eoi
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));
mixin(grammar!(memo, void, backend)(`
IndirectChain:
    Root <- Expr eoi
    Expr <- Sum / Number
    Sum <- Expr '+' Number
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
    private enum iterations = 64;
}
int main() @nogc nothrow {
    char[16384] bytes;
    foreach (i, ref c; bytes)
        c = i % 2 ? '+' : '1';
    printf("grammar,valid,terms,sample,iterations,ns,arena_used,requested_bytes,allocations");
    version (NPeggedMetrics)
        printf(",memo_calls,memo_hits,seed_growths,invalidation_visits,retired_entries,bucket_visits,unlink_visits,rehashes,rehashed_entries,snapshot_bytes");
    printf("\n");
    static foreach (Parser; AliasSeq!(DirectChain, IndirectChain)) {
        foreach (terms; [16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192])
            foreach (valid; [true, false]) {
                const input = cast(string)bytes[0 .. 2 * terms - (valid ? 1 : 0)];
                foreach (sample; 0 .. samples) {
                    ParseContext context;
                    context.stepLimit = size_t.max;
                    version (NPeggedMetrics) {
                        ParseMetrics metrics;
                        context.metrics = &metrics;
                    }
                    size_t retained, requested, allocations;
                    const start = now();
                    foreach (_; 0 .. iterations) {
                        auto result = check!(Parser.opCall)(context, opaqueInput(input));
                        if (result.status != (valid ? Status.ok : Status.mismatch) || result
                                .successful != valid)
                            return 2;
                        retained = result.arena.used;
                        requested = result.arena.requestedBytes;
                        allocations = result.arena.allocationCalls;
                        consume(result.successful, result.end, 0, result.status);
                    }
                    const stop = now();
                    if (!start || stop <= start)
                        return 3;
                    printf("%s,%u,%u,%u,%u,%llu,%llu,%llu,%llu", (Parser.stringof ~ "\0").ptr,
                            cast(uint)valid, cast(uint)terms, cast(uint)sample,
                            cast(uint)iterations, stop - start, cast(ulong)retained,
                            cast(ulong)requested, cast(ulong)allocations);
                    version (NPeggedMetrics)
                        printf(",%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu",
                                metrics.memoCalls, metrics.memoHits, metrics.seedGrowths,
                                metrics.invalidationVisits,
                                metrics.invalidatedEntries,
                                metrics.memoBucketVisits, metrics.memoUnlinkVisits,
                                metrics.memoRehashes,
                                metrics.memoRehashedEntries, metrics.snapshotBytes);
                    printf("\n");
                }
            }
    }
    return 0;
}

private template AliasSeq(T...) {
    alias AliasSeq = T;
}
