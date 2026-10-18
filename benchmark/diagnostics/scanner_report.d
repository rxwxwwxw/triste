/** Scanner eligibility, bypass and replay profile (H06). Diagnostic counters only; not a timing benchmark. */
module benchmark.diagnostics.scanner_report;

import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private enum workloadSource = import("benchmark/workload_grammars.d");
private enum jsonSource = import("benchmark/json_grammar.d");

private size_t find(string text, string needle, size_t start = 0) @nogc nothrow pure {
    foreach (i; start .. text.length)
        if (text.length - i >= needle.length && text[i .. i + needle.length] == needle)
            return i;
    assert(0, "Missing grammar delimiter");
}

private enum pegStart = find(workloadSource, "enum pegGrammar = `") + "enum pegGrammar = `".length;
private enum pegEnd = find(workloadSource, "`;", pegStart);
private enum pegGrammar = workloadSource[pegStart .. pegEnd];

private enum csvStart = find(workloadSource, "enum csvGrammar = `") + "enum csvGrammar = `".length;
private enum csvEnd = find(workloadSource, "`;", csvStart);
private enum csvGrammar = workloadSource[csvStart .. csvEnd];

private enum jsonStart = find(jsonSource, "enum jsonGrammar = `") + "enum jsonGrammar = `".length;
private enum jsonEnd = find(jsonSource, "`;", jsonStart);
private enum jsonGrammar = jsonSource[jsonStart .. jsonEnd];

uint pegTag(string name) @nogc nothrow pure {
    switch (name) {
    case "BenchPEG.Root":
        return 0;
    case "BenchPEG.Definition":
        return 1;
    case "BenchPEG.TopExpression":
    case "BenchPEG.Expression":
        return 2;
    case "BenchPEG.TopSequence":
    case "BenchPEG.Sequence":
        return 3;
    case "BenchPEG.Prefix":
        return 4;
    case "BenchPEG.Primary":
        return 5;
    default:
        return uint.max;
    }
}

uint jsonTag(string name) @nogc nothrow pure {
    switch (name) {
    case "JSON.Object":
        return 1;
    case "JSON.Array":
        return 2;
    case "JSON.String":
        return 3;
    case "JSON.Number":
        return 4;
    case "JSON.True":
        return 5;
    case "JSON.False":
        return 6;
    case "JSON.Null":
        return 7;
    default:
        return uint.max;
    }
}

uint csvTag(string name) @nogc nothrow pure {
    return name == "BenchCSV.Root" ? 0 : name == "BenchCSV.Field" ? 6 : uint.max;
}

version (NPeggedDirect)
    enum backend = ParserBackend.direct;
else
    enum backend = ParserBackend.combinators;

version (NPeggedFullMemo)
    enum memo = Memoization.yes;
else
    enum memo = Memoization.selective;

struct PegSuite {
    mixin(grammar!(memo, pegTag, backend)(pegGrammar));
}

struct JsonSuite {
    mixin(grammar!(memo, jsonTag, backend)(jsonGrammar));
}

struct CsvSuite {
    mixin(grammar!(memo, csvTag, backend)(csvGrammar));
}

private void noopTrace(string, size_t, bool, void*) @nogc nothrow {
}

private void emitStatic(alias Parser)(string grammarName) @nogc nothrow {
    static foreach (i; 0 .. Parser.scannerRuleNames.length) {
        printf("static,%.*s,%.*s,%llu,%u\n", cast(int)grammarName.length, grammarName.ptr,
                cast(int)Parser.scannerRuleNames[i].length, Parser.scannerRuleNames[i].ptr,
                cast(ulong)Parser.scannerRegionCounts[i], Parser.scannerRootProven[i] ? 1u : 0u);
    }
}

private void emitRow(string cohort, string grammarName, string caseName, string modeName, bool accepted,
        size_t inputBytes, scope const ref ScannerStats row) @nogc nothrow {
    printf("row,%.*s,%.*s,%.*s,%.*s,%u,%llu,%.*s,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu",
            cast(int)cohort.length, cohort.ptr, cast(int)grammarName.length, grammarName.ptr,
            cast(int)caseName.length, caseName.ptr, cast(int)modeName.length, modeName.ptr,
            accepted ? 1u : 0u, cast(ulong)inputBytes, cast(int)row.rule.length, row.rule.ptr,
            row.calls, row.eligible, row.scanCalls, row.scanSuccess, row.scanFailure,
            row.fastSuccess, row.fastFailure, row.originalCalls, row.replays, row.examinedBytes,
            row.originalBytes, row.replayedBytes);
    foreach (r; 0 .. cast(size_t)ScannerReason.count)
        printf(",%llu", row.reasons[r]);
    printf("\n");
}

private void runCase(alias Parser, alias Selector)(string cohort, string grammarName, string caseName,
        string input) @nogc nothrow {
    static immutable string[6] modeNames = [
        "check", "records", "owned-records", "tree", "check-budget64", "check-traced"
    ];
    static foreach (mode; 0 .. 6) {
        {
            ScannerStats[128] storage;
            ScannerReport report;
            report.rows = storage[];
            ParseContext context;
            context.scannerReport = &report;
            static if (mode == 4)
                context.stepLimit = 64;
            else static if (mode == 5)
                context.trace = &noopTrace;
            static if (mode == 0 || mode == 4 || mode == 5)
                auto result = check!(Parser.opCall)(context, input);
            else static if (mode == 1)
                auto result = parseRecords!(Parser.opCall, Selector, false)(context, input);
            else static if (mode == 2)
                auto result = parseRecords!(Parser.opCall, Selector, true)(context, input);
            else
                auto result = parse!(Parser.opCall)(context, input);
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
                emitRow(cohort, grammarName, caseName, modeNames[mode], result.successful, input
                        .length, row);
            }
            assert(summed == report.total);
            ScannerStats total = report.total;
            total.rule = "<total>";
            emitRow(cohort, grammarName, caseName, modeNames[mode], result.successful, input.length, total);
        }
    }
}

int main() @nogc nothrow {
    alarm(45);
    enum cohort = (backend == ParserBackend.direct ? "direct-" : "combinators-") ~ (
                memo == Memoization.yes ? "full" : "selective");
    emitStatic!(PegSuite.BenchPEG)("BenchPEG");
    emitStatic!(JsonSuite.JSON)("JSON");
    emitStatic!(CsvSuite.BenchCSV)("BenchCSV");

    char[139] deep;
    deep[0 .. 8] = "G: R <- ";
    deep[8 .. 72] = '(';
    deep[72 .. 75] = "'x'";
    deep[75 .. $] = ')';

    runCase!(PegSuite.BenchPEG, pegTag)(cohort, "BenchPEG", "Permissive", "G: A <-- / []**");
    runCase!(PegSuite.BenchPEG, pegTag)(cohort, "BenchPEG", "Truncated", "G: A <- ('a'");
    runCase!(PegSuite.BenchPEG, pegTag)(cohort, "BenchPEG", "Trailing", "G: A <- 'a' )");
    runCase!(PegSuite.BenchPEG, pegTag)(cohort, "BenchPEG", "Deep", cast(string)deep[]);
    runCase!(PegSuite.BenchPEG, pegTag)(cohort, "BenchPEG", "SelfGrammar", pegGrammar);

    runCase!(JsonSuite.JSON, jsonTag)(cohort, "JSON", "ValidObject",
            `{"name":"triste","values":[1,23,456,-7.8e+9,true,false,null],"escaped":"a\"b\\c\u0041"}`);
    runCase!(JsonSuite.JSON, jsonTag)(cohort, "JSON", "InvalidNumber", `{"bad":123.}`);
    runCase!(JsonSuite.JSON, jsonTag)(cohort, "JSON", "UnterminatedString", `{"bad":"unterminated`);

    runCase!(CsvSuite.BenchCSV, csvTag)(cohort, "BenchCSV", "ValidRows",
            "alpha,beta,gamma\r\n\"quoted \"\"field\"\"\",123,456\n");
    runCase!(CsvSuite.BenchCSV, csvTag)(cohort, "BenchCSV", "InvalidQuote", "alpha,\"unterminated,gamma\n");
    runCase!(CsvSuite.BenchCSV, csvTag)(cohort, "BenchCSV", "FirstQuoteInvalid", "\"unterminated,gamma\n");
    runCase!(CsvSuite.BenchCSV, csvTag)(cohort, "BenchCSV", "ClosedTrailing", "alpha,\"closed\"trailing,gamma\n");
    return 0;
}
