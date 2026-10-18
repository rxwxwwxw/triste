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
    static assert(Candidate.scannerRuleNames.length == Candidate.scannerRegionCounts.length);
    static assert(Candidate.scannerRuleNames.length == Candidate.scannerRootProven.length);
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
            version (NPeggedScannerMetrics)
                assert(!report.truncated);
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
    }
    printf("scanner report oracle passed\n");
    return 0;
}
