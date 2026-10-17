/** Left-recursion scaling probe. CSV samples include construction and disposal. */
module benchmark.recursion_scaling;

import npegged.grammar;
import benchmark.measurement : consume, opaqueInput;
import core.stdc.stdio : printf;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;

uint selected(string name) @nogc nothrow pure {
    return name.length ? 1 : uint.max;
}

version (NPeggedDirect)
    enum backend = ParserBackend.direct;
else
    enum backend = ParserBackend.combinators;

version (NPeggedFullMemo)
    enum memoization = Memoization.yes;
else
    enum memoization = Memoization.selective;

mixin(grammar!(memoization, selected, backend)(`
LeftChain:
    Root <- Expr :eoi
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));
mixin(grammar!(memoization, selected, backend)(`
IndirectChain:
    Root <- Expr :eoi
    Expr <- Sum / Number
    Sum <- Expr '+' Number
    Number <- ~[0-9]+
`));

private ulong now() @nogc nothrow {
    timespec value;
    return clock_gettime(CLOCK_MONOTONIC, &value) ? 0 : cast(ulong)value.tv_sec * 1_000_000_000 + value
        .tv_nsec;
}

version (NPeggedMetrics)
    private enum sampleCount = 1;
else
    private enum sampleCount = 7;

int main() @nogc nothrow {
    version (NPeggedMetrics)
        printf("grammar,mode,valid,terms,memo_calls,memo_hits,seed_growths,invalidation_visits,invalidated_entries,snapshot_bytes\n");
    else
        printf("grammar,mode,valid,terms,sample,ns,allocation_calls,requested_bytes,reserved_bytes\n");
    Arena inputOwner;
    auto bytes = inputOwner.allocate!char(1024);
    if (bytes.length != 1024)
        return 2;
    foreach (i, ref b; bytes)
        b = i % 2 ? '+' : '1';
    static foreach (Parser; AliasSeq!(LeftChain, IndirectChain)) {
        foreach (terms; [8, 16, 32, 64, 128, 256, 512]) {
            foreach (valid; [true, false]) {
                const input = cast(string)bytes[0 .. 2 * terms - (valid ? 1 : 0)];
                static foreach (mode; ["validation", "records", "tree"]) {
                    foreach (sample; 0 .. sampleCount) {
                        ParseContext context;
                        version (NPeggedMetrics) {
                            ParseMetrics metrics;
                            context.metrics = &metrics;
                        }
                        context.stepLimit = size_t.max;
                        size_t calls, requested, reserved;
                        bool ok;
                        Status status;
                        const start = now();
                        {
                            static if (mode == "validation")
                                auto result = check!(Parser.opCall)(context, opaqueInput(input));
                            else static if (mode == "records")
                                auto result = parseRecords!(Parser.opCall, selected, false)(context, opaqueInput(
                                        input));
                            else
                                auto result = Parser(context, opaqueInput(input));
                            ok = result.successful;
                            status = result.status;
                            calls = result.arena.allocationCalls;
                            requested = result.arena.requestedBytes;
                            reserved = result.arena.used;
                            static if (mode == "records") {
                                calls += result.outputArena.allocationCalls;
                                requested += result.outputArena.requestedBytes;
                                reserved += result.outputArena.used;
                                consume(ok, result.end, result.nodes.length, status);
                            } else
                                consume(ok, result.end, 0, status);
                        }
                        const stop = now();
                        if (!start || stop <= start || status != (valid ? Status.ok : Status.mismatch) || ok != valid)
                            return 3;
                        version (NPeggedMetrics)
                            printf("%s,%s,%u,%u,%llu,%llu,%llu,%llu,%llu,%llu\n",
                                    (Parser.stringof ~ "\0")
                                        .ptr, (mode ~ "\0").ptr, cast(uint)valid, cast(uint)terms,
                                    metrics.memoCalls, metrics.memoHits, metrics.seedGrowths,
                                    metrics.invalidationVisits,
                                    metrics.invalidatedEntries, metrics.snapshotBytes);
                        else
                            printf("%s,%s,%u,%u,%u,%llu,%llu,%llu,%llu\n", (Parser.stringof ~ "\0")
                                    .ptr, (mode ~ "\0").ptr, cast(uint)valid, cast(uint)terms,
                                    cast(uint)sample, stop - start, cast(ulong)calls,
                                    cast(ulong)requested, cast(ulong)reserved);
                    }
                }
            }
        }
    }
    return 0;
}

private template AliasSeq(T...) {
    alias AliasSeq = T;
}
