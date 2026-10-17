/** R03 nested/flat/sibling recognition experiment; no counters in timing builds. */
module benchmark.diagnostics.narrow_invalidation;
import npegged.grammar;
import benchmark.measurement : opaqueInput, consume;
import core.stdc.stdio : printf;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
mixin(grammar!(Memoization.selective, void, backend)(`NarrowProbe:
    Root <- Expr eoi
    Expr <- Expr '+' Atom / Atom
    Atom <- '(' Expr ')' / 'n'
`));
private ulong now() @nogc nothrow {
    timespec ts;
    return clock_gettime(CLOCK_MONOTONIC, &ts) ? 0 : cast(ulong)ts.tv_sec * 1_000_000_000 + ts
        .tv_nsec;
}

private string makeInput(char[] buffer, uint shape, size_t size) @nogc nothrow {
    if (shape == 2) {
        buffer[0 .. size] = '(';
        buffer[size] = 'n';
        buffer[size + 1 .. size * 2 + 1] = ')';
        return cast(string)buffer[0 .. size * 2 + 1];
    }
    size_t pos;
    foreach (i; 0 .. size) {
        if (i)
            buffer[pos++] = '+';
        if (shape == 1)
            buffer[pos++] = '(';
        buffer[pos++] = 'n';
        if (shape == 1)
            buffer[pos++] = ')';
    }
    return cast(string)buffer[0 .. pos];
}

version (NPeggedMetrics) {
    private enum samples = 1;
    private enum iterations = 1;
} else {
    private enum samples = 7;
    private enum iterations = 32;
}
int main() @nogc nothrow {
    char[32768] bytes;
    printf("shape,size,sample,iterations,ns,end,fail_end,arena_used,memo_calls,invalidation_visits,retired_entries,narrow_calls,narrow_kept,rehashes,rehashed_entries,bucket_visits,unlink_visits\n");
    foreach (shape; 0 .. 3) {
        foreach (size; [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192
        ]) {
            if (shape < 2 && size < 16 || shape == 1 && size > 512 || shape == 2 && size > 8)
                continue;
            auto input = makeInput(bytes[], shape, size);
            foreach (sample; 0 .. samples) {
                ParseContext context;
                context.stepLimit = context.depthLimit = context.memoryLimit = size_t.max;
                version (NPeggedNarrowInvalidation)
                    version (NPeggedNarrowOptIn)
                        context.narrowInvalidation = true;
                version (NPeggedMetrics) {
                    ParseMetrics metrics;
                    context.metrics = &metrics;
                }
                size_t end, failEnd, retained;
                auto start = now();
                foreach (_; 0 .. iterations) {
                    auto result = check!(NarrowProbe.opCall)(context, opaqueInput(input));
                    if (!result.successful || result.status != Status.ok || result.end != input
                            .length)
                        return 2;
                    end = result.end;
                    failEnd = result.failEnd;
                    retained = result.arena.used;
                    consume(result.successful, result.end, 0, result.status);
                }
                auto stop = now();
                if (!start || stop <= start)
                    return 3;
                ulong calls, visits, retired, narrow, kept, rehashes, rehashed, buckets, unlinks;
                version (NPeggedMetrics) {
                    calls = metrics.memoCalls;
                    visits = metrics.invalidationVisits;
                    retired = metrics.invalidatedEntries;
                    rehashes = metrics.memoRehashes;
                    rehashed = metrics.memoRehashedEntries;
                    buckets = metrics.memoBucketVisits;
                    unlinks = metrics.memoUnlinkVisits;
                    version (NPeggedNarrowInvalidation) {
                        narrow = metrics.narrowCalls;
                        kept = metrics.narrowKept;
                    }
                }
                printf(
                        "%u,%zu,%u,%u,%llu,%zu,%zu,%zu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu\n",
                        cast(uint)shape,
                        cast(size_t)size, cast(uint)sample, cast(uint)iterations, stop - start, end,
                        failEnd, retained, calls, visits, retired, narrow, kept, rehashes, rehashed, buckets,
                        unlinks);
            }
        }
    }
    return 0;
}
