// Legacy single-batch probe; use scripts/d01_pure_islands.py for promotion evidence.
module tests.pure_islands_perf;

import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;
import core.sys.posix.unistd : alarm;

private uint selected(string name) @nogc nothrow pure {
    if (!name.length)
        return uint.max;
    return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : 1;
}

ParseTree dummyAction(bool CT)(ref State!CT state, ParseTree tree) @nogc nothrow {
    return tree;
}

private void traceCallback(string name, size_t pos, bool succ, void* data) @nogc nothrow {
}

enum grammarDef = `
PerfIslands:
    Root <- [a-z]+ eoi
    Mixed <- Root Act
    Act <- '!' {dummyAction}
`;

struct Suite(ParserBackend backend) {
    mixin(grammar!(Memoization.selective, selected, backend)(grammarDef));
}

alias Reference = Suite!(ParserBackend.combinators).PerfIslands;
alias Candidate = Suite!(ParserBackend.direct).PerfIslands;

private ulong now() @nogc nothrow {
    timespec ts;
    return clock_gettime(CLOCK_MONOTONIC, &ts) ? 0 : cast(ulong)ts.tv_sec * 1_000_000_000 + ts
        .tv_nsec;
}

private void makeInput(char[] buf, size_t len) @nogc nothrow {
    foreach (i; 0 .. len)
        buf[i] = cast(char)('a' + (i % 26));
}

int main() @nogc nothrow {
    alarm(30);
    version (NPeggedPureIslands)
        version (NPeggedMetrics) {
            ParseContext proof;
            proof.stepLimit = proof.depthLimit = proof.memoryLimit = size_t.max;
            ParseMetrics metrics;
            proof.metrics = &metrics;
            auto recognized = check!(Candidate.Root)(proof, "abc");
            assert(recognized.successful && metrics.pureIslandEntries > 0);
            metrics = ParseMetrics.init;
            auto records = parseRecords!(Candidate.Root, selected)(proof, "abc", size_t.max);
            assert(records.successful && metrics.pureIslandEntries > 0);
        }

    char[1024] buf;
    const size_t[4] sizes = [16, 64, 256, 1024];
    const size_t[4] iters = [50_000, 20_000, 5_000, 2_000];

    printf("size,mode,ref_ns,cand_ns,ratio\n");

    // 1. Check mode unbounded
    foreach (idx, sz; sizes) {
        makeInput(buf[0 .. sz], sz);
        string input = cast(string)buf[0 .. sz];
        const iter = iters[idx];

        ParseContext ctx;
        ctx.stepLimit = ctx.depthLimit = ctx.memoryLimit = size_t.max;
        // Warmup
        foreach (_; 0 .. 500) {
            check!(Reference.Root)(ctx, input);
            check!(Candidate.Root)(ctx, input);
        }

        // Measure Reference
        ulong t0 = now();
        foreach (_; 0 .. iter) {
            auto r = check!(Reference.Root)(ctx, input);
            assert(r.status == Status.ok);
        }
        ulong t1 = now();
        ulong refTime = (t1 - t0) / iter;

        // Measure Candidate
        ulong t2 = now();
        foreach (_; 0 .. iter) {
            auto r = check!(Candidate.Root)(ctx, input);
            assert(r.status == Status.ok);
        }
        ulong t3 = now();
        ulong candTime = (t3 - t2) / iter;

        double ratio = cast(double)candTime / cast(double)(refTime ? refTime : 1);
        printf("%zu,check_unbounded,%llu,%llu,%.4f\n", sz, refTime, candTime, ratio);
    }

    // 2. Records mode unbounded
    foreach (idx, sz; sizes) {
        makeInput(buf[0 .. sz], sz);
        string input = cast(string)buf[0 .. sz];
        const iter = iters[idx];

        ParseContext ctx;
        ctx.stepLimit = ctx.depthLimit = ctx.memoryLimit = size_t.max;
        ulong t0 = now();
        foreach (_; 0 .. iter) {
            auto r = parseRecords!(Reference.Root, selected)(ctx, input, size_t.max);
            assert(r.status == Status.ok);
        }
        ulong t1 = now();
        ulong refTime = (t1 - t0) / iter;

        ulong t2 = now();
        foreach (_; 0 .. iter) {
            auto r = parseRecords!(Candidate.Root, selected)(ctx, input, size_t.max);
            assert(r.status == Status.ok);
        }
        ulong t3 = now();
        ulong candTime = (t3 - t2) / iter;

        double ratio = cast(double)candTime / cast(double)(refTime ? refTime : 1);
        printf("%zu,records_unbounded,%llu,%llu,%.4f\n", sz, refTime, candTime, ratio);
    }

    // 3. Check mode with finite budget (stepLimit = 2) -> early resourceLimit
    const size_t[2] smallSizes = [16, 64];
    foreach (idx, sz; smallSizes) {
        makeInput(buf[0 .. sz], sz);
        string input = cast(string)buf[0 .. sz];
        const iter = 50_000;

        ParseContext ctx;
        ctx.stepLimit = 2;

        ulong t0 = now();
        foreach (_; 0 .. iter) {
            auto r = check!(Reference.Root)(ctx, input);
            assert(r.status == Status.resourceLimit);
        }
        ulong t1 = now();
        ulong refTime = (t1 - t0) / iter;

        ulong t2 = now();
        foreach (_; 0 .. iter) {
            auto r = check!(Candidate.Root)(ctx, input);
            assert(r.status == Status.resourceLimit);
        }
        ulong t3 = now();
        ulong candTime = (t3 - t2) / iter;

        double ratio = cast(double)candTime / cast(double)(refTime ? refTime : 1);
        printf("%zu,check_budgeted,%llu,%llu,%.4f\n", sz, refTime, candTime, ratio);
    }

    // 4. Check mode with tracing
    foreach (idx, sz; smallSizes) {
        makeInput(buf[0 .. sz], sz);
        string input = cast(string)buf[0 .. sz];
        const iter = 20_000;

        ParseContext ctx;
        ctx.trace = &traceCallback;

        ulong t0 = now();
        foreach (_; 0 .. iter) {
            auto r = check!(Reference.Root)(ctx, input);
            assert(r.status == Status.ok);
        }
        ulong t1 = now();
        ulong refTime = (t1 - t0) / iter;

        ulong t2 = now();
        foreach (_; 0 .. iter) {
            auto r = check!(Candidate.Root)(ctx, input);
            assert(r.status == Status.ok);
        }
        ulong t3 = now();
        ulong candTime = (t3 - t2) / iter;

        double ratio = cast(double)candTime / cast(double)(refTime ? refTime : 1);
        printf("%zu,check_traced,%llu,%llu,%.4f\n", sz, refTime, candTime, ratio);
    }

    return 0;
}
