module benchmark.p11_flat_bench;

import npegged.grammar;
import npegged.examples.json : JSON;
import npegged.examples.csv : CSV;
import core.stdc.stdio : printf;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;
import core.sys.posix.unistd : alarm;

mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(`
DirectChain:
    Root <- Expr eoi
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));

private uint selectAll(string name) @nogc nothrow pure {
    return 0;
}

private ulong now() @nogc nothrow {
    timespec ts;
    return clock_gettime(CLOCK_MONOTONIC, &ts) ? 0 : cast(ulong)ts.tv_sec * 1_000_000_000 + ts
        .tv_nsec;
}

int main() @nogc nothrow {
    alarm(60);

    enum jsonInput = `{"a":[1,true,null],"b":"x"}`;
    enum csvInput = "a,b,c\n1,2,3\n4,5,6\n";

    // 1. Benchmark JSON
    const jsonIters = 50_000;
    ParseContext ctx;
    // Warmup
    foreach (_; 0 .. 500)
        parseRecords!(JSON.JSONObject, selectAll)(ctx, jsonInput, size_t.max);

    ulong t0 = now();
    foreach (_; 0 .. jsonIters) {
        auto r = parseRecords!(JSON.JSONObject, selectAll)(ctx, jsonInput, size_t.max);
        assert(r.status == Status.ok);
    }
    ulong t1 = now();
    ulong jsonNs = (t1 - t0) / jsonIters;

    // 2. Benchmark CSV
    const csvIters = 50_000;
    foreach (_; 0 .. 500)
        parseRecords!(CSV.CsvFile, selectAll)(ctx, csvInput, size_t.max);

    ulong t2 = now();
    foreach (_; 0 .. csvIters) {
        auto r = parseRecords!(CSV.CsvFile, selectAll)(ctx, csvInput, size_t.max);
        assert(r.status == Status.ok);
    }
    ulong t3 = now();
    ulong csvNs = (t3 - t2) / csvIters;

    // 3. Benchmark Depth 2048 DirectChain with sharedOutput = true
    char[4096] buf;
    foreach (i; 0 .. 2048) {
        buf[i * 2] = '1';
        buf[i * 2 + 1] = '+';
    }
    buf[2048 * 2 - 1] = '1';
    string recInput = cast(string)buf[0 .. 2048 * 2 - 1];

    ParseContext ctxRec;
    version (NPeggedSharedOutput)
        ctxRec.sharedOutput = true;

    parseRecords!(DirectChain.Root, selectAll)(ctxRec, recInput, size_t.max);

    const recIters = 10;
    ulong t4 = now();
    foreach (_; 0 .. recIters) {
        auto r = parseRecords!(DirectChain.Root, selectAll)(ctxRec, recInput, size_t.max);
        assert(r.status == Status.ok);
    }
    ulong t5 = now();
    ulong recNs = (t5 - t4) / recIters;

    printf("json_ns=%llu,csv_ns=%llu,rec_depth2048_ns=%llu\n", jsonNs, csvNs, recNs);
    return 0;
}
