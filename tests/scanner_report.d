module tests.scanner_report;
import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

uint selected(string name) @nogc nothrow pure {
    return name.length ? 1 : uint.max;
}

private State!(CT, Check).Node external(bool CT, int Check)(ref State!(CT, Check) s, size_t p) @nogc nothrow {
    return literal!"!"(s, p);
}

struct Suite(ParserBackend backend) {
    mixin(grammar!(Memoization.selective, selected, backend)(`
ScannerFixture:
    Root <- Digits eoi
    Digits <~ [0-9]+
    Discard <: [ ]+
    Inner <- Digits+
    Eof <- [a-z]+ eoi
    Unsafe <- 'a'* 'a'
    Opaque <- external
    Fixed <- 'x'
`));
}

alias Candidate = Suite!(ParserBackend.direct).ScannerFixture;
alias Combinators = Suite!(ParserBackend.combinators).ScannerFixture;
version (NPeggedScannerMetrics) {
    static assert(Candidate.scannerRuleNames == [
        "ScannerFixture.Root", "ScannerFixture.Digits", "ScannerFixture.Discard",
        "ScannerFixture.Inner", "ScannerFixture.Eof", "ScannerFixture.Unsafe",
        "ScannerFixture.Opaque", "ScannerFixture.Fixed"
    ]);
    static assert(Candidate.scannerRegionCounts == [1, 1, 1, 1, 1, 1, 0, 0]);
    static assert(Candidate.scannerRootProven == [true, true, true, true, true, false, false, true]);
    static assert(Combinators.scannerRuleNames == Candidate.scannerRuleNames);
    static assert(Combinators.scannerRegionCounts == Candidate.scannerRegionCounts);
    static assert(Combinators.scannerRootProven == Candidate.scannerRootProven);
}
private ulong treeHash(scope const ref ParseTree tree) @nogc nothrow {
    ulong hash = tree.begin * 3 + tree.end * 7 + tree.failEnd * 11 + tree.successful;
    foreach (c; tree.name)
        hash = hash * 33 + cast(ubyte)c;
    foreach (c; tree.input)
        hash = hash * 33 + cast(ubyte)c;
    foreach (match; tree.matches) {
        hash = hash * 33 + match.length;
        foreach (c; match)
            hash = hash * 33 + cast(ubyte)c;
    }
    foreach (child; tree.children)
        hash = hash * 33 + treeHash(child);
    foreach (child; tree.failedChild)
        hash = hash * 33 + treeHash(child);
    return hash;
}

private ulong traceHash;
private void trace(string name, size_t p, bool successful, void*) @nogc nothrow {
    foreach (c; name)
        traceHash = traceHash * 33 + cast(ubyte)c;
    traceHash = traceHash * 33 + p * 3 + successful;
}

private void run(alias parser)(string input, ParseContext context) @nogc nothrow {
    static foreach (mode; 0 .. 4) {
        {
            version (NPeggedScannerMetrics) {
                ScannerStats[64] storage;
                ScannerReport report;
                report.rows = storage[];
                context.scannerReport = &report;
            }
            traceHash = 0;
            static if (mode == 0)
                auto result = check!parser(context, input);
            else static if (mode == 3)
                auto result = parse!parser(context, input);
            else
                auto result = parseRecords!(parser, selected, mode == 2)(context, input, context
                        .memoryLimit);
            ulong hash = result.end * 3 + result.failEnd * 7 + cast(ulong)result.status;
            static if (mode == 3)
                hash = treeHash(result.tree);
            else static if (mode != 0)
                foreach (node; result.nodes)
                    hash = hash * 33 + node.kind + node.begin * 3 + node.end * 7 + node.parent * 11;
            printf("%.*s,%u,%llu,%u,%llu,%llu,%llu,%llu,%llu,%llu\n", cast(int)__traits(identifier,
                    parser).length, __traits(identifier, parser).ptr, cast(uint)mode,
                    cast(ulong)input.length, cast(uint)result.status, cast(ulong)result.end,
                    cast(ulong)result.failEnd, hash, traceHash, cast(ulong)result.arena.used,
                    cast(ulong)result.arena.requestedBytes);
            version (NPeggedScannerMetrics) {
                assert(!report.truncated);
                ScannerStats summed;
                foreach (row; report.rows[0 .. report.length]) {
                    summed.calls += row.calls;
                    summed.eligible += row.eligible;
                    summed.scanCalls += row.scanCalls;
                    summed.scanSuccess += row.scanSuccess;
                    summed.scanFailure += row.scanFailure;
                    summed.fastSuccess += row.fastSuccess;
                    summed.fastFailure += row.fastFailure;
                    summed.originalCalls += row.originalCalls;
                    summed.replays += row.replays;
                    summed.examinedBytes += row.examinedBytes;
                    summed.originalBytes += row.originalBytes;
                    summed.replayedBytes += row.replayedBytes;
                    foreach (r; 0 .. cast(size_t)ScannerReason.count)
                        summed.reasons[r] += row.reasons[r];
                }
                summed.rule = report.total.rule;
                assert(summed == report.total);
            }
        }
    }
}

int main() @nogc nothrow {
    alarm(45);
    ParseContext context;
    foreach (input; ["", "1", "123!", " ", "  x", "abc", "abc!", "a", "aaa", "!", "\0", "é"]) {
        static foreach (entry; [
            "Root", "Digits", "Discard", "Inner", "Eof", "Unsafe", "Opaque", "Fixed"
        ]) {
            {
                run!(__traits(getMember, Candidate, entry))(input, context);
                run!(__traits(getMember, Combinators, entry))(input, context);
            }
        }
        foreach (limit; [0, 1, 2, 4, 16, 64, 1024]) {
            auto limited = context;
            limited.stepLimit = limit;
            run!(Candidate.Root)(input, limited);
            limited = context;
            limited.depthLimit = limit;
            run!(Candidate.Root)(input, limited);
            limited = context;
            limited.memoryLimit = limit;
            run!(Candidate.Root)(input, limited);
        }
        auto traced = context;
        traced.trace = &trace;
        run!(Candidate.Root)(input, traced);
    }
    version (NPeggedScannerMetrics) {
        ScannerStats[64] storage;
        ScannerReport report;
        report.rows = storage[];
        context.scannerReport = &report;
        auto result = check!(Candidate.Root)(context, "123");
        assert(result.successful && report.total.calls > 0);
        assert(report.total.scanCalls > 0 || report.total.originalCalls > 0);
        assert(!report.truncated && report.length > 0);
        ScannerStats[1] tinyStorage;
        ScannerReport tiny;
        tiny.rows = tinyStorage[];
        context.scannerReport = &tiny;
        assert(parseRecords!(Candidate.Root, selected, false)(context, "123").successful);
        assert(tiny.truncated && tiny.length == 1 && tiny.total.calls >= 2);
        context.scannerReport = null;
        assert(check!(Candidate.Root)(context, "123").successful);
        ScannerStats[16] testStorage;
        ScannerReport testReport;
        testReport.rows = testStorage[];
        context.scannerReport = &testReport;
        assert(!parseRecords!(Candidate.Digits, selected, false)(context, "xyz").successful);
        assert(testReport.total.fastFailure == 1);
        assert(testReport.total.replays == 0);
        assert(testReport.total.reasons[ScannerReason.failureDiagnostic] == 0);

        // 2. EOF on terminal rule: fastFailure, 0 replays, exact failEnd == 0
        testReport.total = ScannerStats.init;
        foreach (ref row; testStorage)
            row = ScannerStats.init;
        auto eofRes = parseRecords!(Candidate.Digits, selected, false)(context, "");
        assert(!eofRes.successful && eofRes.failEnd == 0);
        assert(testReport.total.fastFailure == 1);
        assert(testReport.total.replays == 0);

        // 3. Truncated/Anchored rule needing eoi: fastFailure, 0 replays
        testReport.total = ScannerStats.init;
        foreach (ref row; testStorage)
            row = ScannerStats.init;
        auto truncRes = parseRecords!(Candidate.Eof, selected, false)(context, "abc!");
        assert(!truncRes.successful && truncRes.failEnd == 3);
        assert(testReport.total.fastFailure == 1);
        assert(testReport.total.replays == 0);

        // 4. Token WITH inner records (Candidate.Inner): MUST fall back to combinator execution
        testReport.total = ScannerStats.init;
        foreach (ref row; testStorage)
            row = ScannerStats.init;
        auto innerRes = parseRecords!(Candidate.Inner, selected, false)(context, "xyz");
        assert(!innerRes.successful && innerRes.failEnd == 0);
        assert(testReport.total.fastFailure == 1);
        assert(testReport.total.replays == 0);
        assert(testReport.total.reasons[ScannerReason.recordLowering] == 1);

        // 5. BudgetEdge on step limit: must not take fast failure shortcut
        testReport.total = ScannerStats.init;
        foreach (ref row; testStorage)
            row = ScannerStats.init;
        auto budgetCtx = context;
        budgetCtx.stepLimit = 2;
        auto budgetRes = parseRecords!(Candidate.Digits, selected, false)(budgetCtx, "12345");
        assert(!budgetRes.successful);
        assert(testReport.total.fastFailure == 0);
        assert(testReport.total.reasons[ScannerReason.budgetEdge] == 1);
    }
    printf("scanner report oracle passed\n");
    return 0;
}
