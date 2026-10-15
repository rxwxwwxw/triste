module benchmark.runner;

import core.memory : GC;
import core.stdc.stdio : printf, fprintf, stderr, putchar;
import core.time : MonoTime;
import benchmark.measurement : consume, currentChecksum, expectedChecksum, opaqueInput;
import benchmark.options : Options, OptionStatus, parseOptions;
import npegged.peg : ParseContext, ParseResult;
import npegged.storage : Buffer, Status;
import benchmark.json_output : OutputMode, handwrittenOutput, ambiguousOutput, handwrittenAmbiguous;
import benchmark.json_comparison : Observation, observeHandwritten, observeNPegged, observePegged, verifyOutputs;
import pegged.peg : PeggedParseTree = ParseTree;

// 1. Arithmetic
import NPArith = npegged.examples.arithmetic;
import PArith = pegged.examples.arithmetic;
import HWArith = benchmark.handwritten.arithmetic;

// 2. JSON
import NPJson = benchmark.json_npegged;
import PJson = benchmark.json_pegged;
import HWJson = benchmark.handwritten.json;

// 3. CSV
import NPCsv = npegged.examples.csv;
import PCsv = pegged.examples.csv;
import HWCsv = benchmark.handwritten.csv;

// 4. Numbers
import NPNum = npegged.examples.numbers;
import PNum = pegged.examples.numbers;
import HWNum = benchmark.handwritten.numbers;

// Meta-grammar
import NPParser = npegged.parser;
import PParser = pegged.parser;
import HWPeg = benchmark.handwritten.peg;

alias PeggedFn = bool delegate(string);
alias NPeggedFn = bool delegate(string, ref ParseContext) @nogc nothrow;
alias HandwrittenFn = bool delegate(string) @nogc nothrow;
struct ArenaMetrics {
    size_t calls;
    size_t requestedBytes;
    size_t reservedBytes;
}

alias ArenaPeakFn = ArenaMetrics delegate(string) @nogc nothrow;
struct BenchmarkCase {
    string name;
    string input;
    size_t defaultIterations;
    PeggedFn runPegged;
    NPeggedFn runNPegged;
    HandwrittenFn runHandwritten;
    ArenaPeakFn getNPeggedArenaPeak;
    bool expectedAccepted = true;
}

Observation observeCase(ref BenchmarkCase bc, size_t engine, bool comparison, OutputMode mode) {
    const input = opaqueInput(bc.input);
    if (comparison) {
        if (engine == 0)
            return observePegged(input, mode, contains(bc.name, "Ambiguous."));
        if (engine == 1)
            return observeNPegged(input, mode, contains(bc.name, "Ambiguous."));
        return observeHandwritten(input, mode, contains(bc.name, "Ambiguous."));
    }
    if (contains(bc.name, "Ambiguous.")) {
        if (engine == 0)
            return observePegged(input, OutputMode.validation, true);
        if (engine == 1)
            return observeNPegged(input, OutputMode.validation, true);
        return observeHandwritten(input, OutputMode.validation, true);
    }
    Observation result;
    if (engine == 0)
        result.accepted = bc.runPegged(input);
    else if (engine == 1) {
        ParseContext context;
        result.accepted = bc.runNPegged(input, context);
    } else
        result.accepted = bc.runHandwritten(input);
    return result;
}

unittest {
    BenchmarkCase probe;
    probe.name = "Probe";
    probe.input = "input";
    probe.runPegged = (string input) { return input == "input"; };
    probe.runNPegged = (string input, ref ParseContext context) @nogc nothrow{
        return input == "input";
    };
    probe.runHandwritten = (string input) @nogc nothrow{ return input == "input"; };
    foreach (engine; 0 .. 3)
        assert(observeCase(probe, engine, false, OutputMode.validation).accepted);
    probe.input = "wrong";
    assert(!observeCase(probe, 2, false, OutputMode.validation).accepted);
    probe.name = "JSON.Probe";
    probe.input = "[null]";
    foreach (engine; 0 .. 3)
        assert(observeCase(probe, engine, true, OutputMode.tree).outputNodes == 2);
    probe.name = "Ambiguous.Probe";
    probe.input = "aac";
    foreach (engine; 0 .. 3)
        assert(observeCase(probe, engine, false, OutputMode.validation).accepted);
}

void writeJsonString(string value) @nogc nothrow {
    putchar('"');
    foreach (ubyte c; cast(const(ubyte)[])value) {
        if (c == '"' || c == '\\') {
            putchar('\\');
            putchar(c);
        } else if (c < 32)
            printf("\\u%04x", cast(uint)c);
        else
            putchar(c);
    }
    putchar('"');
}

@nogc nothrow unittest {
    import benchmark.test_output : CapturedStdout;

    auto capture = CapturedStdout.open();
    writeJsonString("\0\t\n\"\\é");
    char[64] text;
    auto length = capture.read(text);
    assert(text[0 .. length] == `"\u0000\u0009\u000a\"\\é"`);
}

void exportJsonCase(string name, string input, bool expected, size_t iterations, bool timed, bool ambiguous = false) @nogc nothrow {
    printf("{\"name\":");
    writeJsonString(name);
    printf(",\"input\":");
    writeJsonString(input);
    printf(",\"grammar\":\"%s\"", (ambiguous ? "ambiguous" : "json").ptr);
    printf(",\"expectedAccepted\":%s,\"iterations\":%zu,\"timed\":%s", (expected ? "true" : "false")
            .ptr, iterations, (timed ? "true" : "false").ptr);
    foreach (mode; [OutputMode.spans, OutputMode.tree]) {
        printf(",\"%s\":[", (mode == OutputMode.spans ? "expectedSpans" : "expectedTree").ptr);
        auto output = ambiguous ? ambiguousOutput(input, mode) : handwrittenOutput(input, mode);
        foreach (i, node; output.nodes) {
            if (i)
                putchar(',');
            printf("[%u,%zu,%zu,%zu]", cast(uint)node.kind, node.begin, node.end, node.parent);
        }
        putchar(']');
    }
    putchar('}');
}

@nogc nothrow unittest {
    import benchmark.test_output : CapturedStdout;

    auto capture = CapturedStdout.open();
    exportJsonCase("A", "\n", false, 1, false);
    char[256] text;
    auto length = capture.read(text);
    assert(text[0 .. length] == `{"name":"A","input":"\u000a","grammar":"json","expectedAccepted":false,"iterations":1,"timed":false,"expectedSpans":[],"expectedTree":[]}`);
}

bool contains(string text, string pattern) @nogc nothrow pure {
    if (pattern.length > text.length)
        return false;
    foreach (i; 0 .. text.length - pattern.length + 1)
        if (text[i .. i + pattern.length] == pattern)
            return true;
    return false;
}

@nogc nothrow unittest {
    assert(contains("JSON.Small", "Small"));
    assert(contains("", ""));
    assert(!contains("a", "aa"));
    assert(!contains("abc", "z"));
}

int main(string[] args) {
    Options options;
    const status = parseOptions(args, options);
    if (status == OptionStatus.invalid) {
        fprintf(stderr, "Invalid benchmark options; use --help\n");
        return 2;
    }
    if (status == OptionStatus.help) {
        printf("Usage: benchmark_runner [--iterations=N|-n N] [--samples=N] [--filter=TEXT|-f TEXT] [--json] [--memory] [--export-corpus] [--mode=validation|spans|tree]\n");
        return 0;
    }
    const customIterations = options.iterations;
    const samples = options.samples;
    const filterPattern = options.filter;
    const jsonOutput = options.json;
    const measureMemory = options.memory;
    const comparison = options.comparison;
    const exportCorpus = options.exportCorpus;
    const mode = options.mode;

    BenchmarkCase[] benchmarks;

    // 1. Arithmetic Expressions
    benchmarks ~= BenchmarkCase("Arithmetic.Small", "1 + 2 * (3 - 4)", 1000, (string s) {
        auto tree = PArith.Arithmetic(s);
        return tree.successful & (tree.end == s.length);
    }, (string s, ref ParseContext ctx) {
        auto res = NPArith.Arithmetic(ctx, s);
        return res.successful & (res.end == s.length);
    }, (string s) { const ok = HWArith.ArithmeticParser.parse(s); return ok; }, (string s) {
        ParseContext ctx;
        auto res = NPArith.Arithmetic(ctx, s);
        return ArenaMetrics(res.arena.allocationCalls, res.arena.requestedBytes, res.arena.used);
    });

    benchmarks ~= BenchmarkCase("Arithmetic.Medium",
            "1 + 2 * (3 + 10 / 4) - (5 * 6 + 7) * (8 - 9 / (2 + 3))", 500, (string s) {
        auto tree = PArith.Arithmetic(s);
        return tree.successful & (tree.end == s.length);
    }, (string s, ref ParseContext ctx) {
        auto res = NPArith.Arithmetic(ctx, s);
        return res.successful & (res.end == s.length);
    }, (string s) { const ok = HWArith.ArithmeticParser.parse(s); return ok; }, (string s) {
        ParseContext ctx;
        auto res = NPArith.Arithmetic(ctx, s);
        return ArenaMetrics(res.arena.allocationCalls, res.arena.requestedBytes, res.arena.used);
    });

    benchmarks ~= BenchmarkCase("Arithmetic.Nested",
            "(((1 + 2) * 3 - 4) / 5 + (6 * (7 - 8))) * (((9 + 10) * 11 - 12) / 13 + (14 * (15 - 16)))",
            500, (string s) {
        auto tree = PArith.Arithmetic(s);
        return tree.successful & (tree.end == s.length);
    }, (string s, ref ParseContext ctx) {
        auto res = NPArith.Arithmetic(ctx, s);
        return res.successful & (res.end == s.length);
    }, (string s) { const ok = HWArith.ArithmeticParser.parse(s); return ok; }, (string s) {
        ParseContext ctx;
        auto res = NPArith.Arithmetic(ctx, s);
        return ArenaMetrics(res.arena.allocationCalls, res.arena.requestedBytes, res.arena.used);
    });

    // 2. JSON Documents
    benchmarks ~= BenchmarkCase("JSON.Small",
            `{"name": "test", "id": 12345, "active": true, "score": 98.6}`, 500, (string s) {
        auto tree = PJson.JSON(s);
        return tree.successful & (tree.end == s.length);
    }, (string s, ref ParseContext ctx) {
        auto res = NPJson.JSON(ctx, s);
        return res.successful & (res.end == s.length);
    }, (string s) { const ok = HWJson.JsonParser.parse(s); return ok; }, (string s) {
        ParseContext ctx;
        auto res = NPJson.JSON(ctx, s);
        return ArenaMetrics(res.arena.allocationCalls, res.arena.requestedBytes, res.arena.used);
    });

    enum mediumJson = `{
  "project": "triste",
  "version": 1,
  "tags": ["druntime", "nogc", "parser", "peg"],
  "maintainers": [
    {"name": "Alex", "role": "lead", "active": true, "commits": 120},
    {"name": "Agent", "role": "pair", "active": false, "commits": 45}
  ],
  "meta": {"created": 2026, "verified": true, "score": 0.995}
}`;

    benchmarks ~= BenchmarkCase("JSON.Medium", mediumJson, 200, (string s) {
        auto tree = PJson.JSON(s);
        return tree.successful & (tree.end == s.length);
    }, (string s, ref ParseContext ctx) {
        auto res = NPJson.JSON(ctx, s);
        return res.successful & (res.end == s.length);
    }, (string s) { const ok = HWJson.JsonParser.parse(s); return ok; }, (string s) {
        ParseContext ctx;
        auto res = NPJson.JSON(ctx, s);
        return ArenaMetrics(res.arena.allocationCalls, res.arena.requestedBytes, res.arena.used);
    });

    // 3. CSV Datasets
    benchmarks ~= BenchmarkCase("CSV.SingleLine", `id,first_name,last_name,email,gender,ip_address`, 1000,
            (string s) { auto tree = PCsv.CSV(s); return tree.successful & (tree.end == s.length); }, (
            string s, ref ParseContext ctx) {
        auto res = NPCsv.CSV(ctx, s);
        return res.successful & (res.end == s.length);
    }, (string s) { const ok = HWCsv.CsvParser.parse(s); return ok; }, (string s) {
        ParseContext ctx;
        auto res = NPCsv.CSV(ctx, s);
        return ArenaMetrics(res.arena.allocationCalls, res.arena.requestedBytes, res.arena.used);
    });

    enum multiLineCsv = "id,name,role,department,score\n"
        ~ "1,Alice_Smith,Engineer,Platform,94.5\n"
        ~ "2,Bob_Jones,Manager,\"Operations, HQ\",88.0\n" ~ "3,Charlie_Brown,Analyst,Data,91.2\n"
        ~ "4,Diana_Prince,Architect,\"Security & Trust\",99.0\n"
        ~ "5,Evan_Wright,Developer,Frontend,85.7\n" ~ "6,Fiona_Gallagher,QA,Verification,92.3\n"
        ~ "7,George_Clark,DevOps,Infrastructure,89.1\n"
        ~ "8,Hannah_Abbott,Support,\"Customer Success, US\",87.4\n"
        ~ "9,Ian_Malcolm,Consultant,Chaos,96.8\n" ~ "10,Julia_Roberts,Designer,Product,90.0";

    benchmarks ~= BenchmarkCase("CSV.MultiLine", multiLineCsv, 300, (string s) {
        auto tree = PCsv.CSV(s);
        return tree.successful & (tree.end == s.length);
    }, (string s, ref ParseContext ctx) {
        auto res = NPCsv.CSV(ctx, s);
        return res.successful & (res.end == s.length);
    }, (string s) { const ok = HWCsv.CsvParser.parse(s); return ok; }, (string s) {
        ParseContext ctx;
        auto res = NPCsv.CSV(ctx, s);
        return ArenaMetrics(res.arena.allocationCalls, res.arena.requestedBytes, res.arena.used);
    });

    // 4. Numbers Literals
    benchmarks ~= BenchmarkCase("Numbers.Scientific", "123.456e+00", 1000, (string s) {
        auto tree = PNum.Numbers.Scientific(s);
        return tree.successful & (tree.end == s.length);
    }, (string s, ref ParseContext ctx) {
        auto res = NPNum.Numbers.Scientific(ctx, s);
        return res.successful & (res.end == s.length);
    }, (string s) { const ok = HWNum.NumbersParser.parseScientific(s); return ok; }, (string s) {
        ParseContext ctx;
        auto res = NPNum.Numbers.Scientific(ctx, s);
        return ArenaMetrics(res.arena.allocationCalls, res.arena.requestedBytes, res.arena.used);
    });

    // 5. PEG Meta-Grammar Parser (Self-hosting grammars)
    enum samplePegSmall = "Calc:\n  Expr <- Term ('+' Term)*\n  Term <- [0-9]+\n";
    benchmarks ~= BenchmarkCase("PEGGrammar.Small", samplePegSmall, 300, (string s) {
        auto tree = PParser.Pegged(s);
        return tree.successful & (tree.end == s.length);
    }, (string s, ref ParseContext ctx) {
        auto res = NPParser.Pegged(ctx, s);
        return res.successful & (res.end == s.length);
    }, (string s) { const ok = HWPeg.PegParser.parse(s); return ok; }, (string s) {
        ParseContext ctx;
        auto res = NPParser.Pegged(ctx, s);
        return ArenaMetrics(res.arena.allocationCalls, res.arena.requestedBytes, res.arena.used);
    });

    enum samplePegMedium = "JSON:\n" ~ "  JSONObject < :'{' (Pair (:',' Pair)*)? :'}'\n"
        ~ "  Pair       < String :':' Value\n" ~ "  Array      < :'[' (Value (:',' Value)*)? :']'\n"
        ~ "  Value      < String / Number / JSONObject / Array / True / False / Null\n"
        ~ "  True       <- 'true'\n" ~ "  False      <- 'false'\n" ~ "  Null       <- 'null'\n";

    benchmarks ~= BenchmarkCase("PEGGrammar.Medium", samplePegMedium, 150, (string s) {
        auto tree = PParser.Pegged(s);
        return tree.successful & (tree.end == s.length);
    }, (string s, ref ParseContext ctx) {
        auto res = NPParser.Pegged(ctx, s);
        return res.successful & (res.end == s.length);
    }, (string s) { const ok = HWPeg.PegParser.parse(s); return ok; }, (string s) {
        ParseContext ctx;
        auto res = NPParser.Pegged(ctx, s);
        return ArenaMetrics(res.arena.allocationCalls, res.arena.requestedBytes, res.arena.used);
    });

    // Reuse identical adapters for stress and rejection workloads.
    auto jsonBase = benchmarks[3];
    {
        auto entry = jsonBase;
        entry.name = "JSON.LargeString";
        entry.input = "{\"text\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}";
        entry.defaultIterations = 10;
        entry.expectedAccepted = true;
        benchmarks ~= entry;
    }
    {
        auto entry = jsonBase;
        entry.name = "JSON.EscapeHeavy";
        entry.input = "{\"text\":\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\\n\\t\\u0041\\\"\"}";
        entry.defaultIterations = 10;
        entry.expectedAccepted = true;
        benchmarks ~= entry;
    }
    {
        auto entry = jsonBase;
        entry.name = "JSON.WhitespaceHeavy";
        entry.input = "                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                {\n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \n \"a\"                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                : 1}";
        entry.defaultIterations = 10;
        entry.expectedAccepted = true;
        benchmarks ~= entry;
    }
    {
        auto entry = jsonBase;
        entry.name = "JSON.DeepNesting";
        entry.input = "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[0]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]";
        entry.defaultIterations = 10;
        entry.expectedAccepted = true;
        benchmarks ~= entry;
    }
    {
        auto entry = jsonBase;
        entry.name = "JSON.InvalidEscape";
        entry.input = "{\"a\":\"\\q\"}";
        entry.defaultIterations = 10;
        entry.expectedAccepted = false;
        benchmarks ~= entry;
    }
    {
        auto entry = jsonBase;
        entry.name = "JSON.InvalidNumber";
        entry.input = "{\"a\":01}";
        entry.defaultIterations = 10;
        entry.expectedAccepted = false;
        benchmarks ~= entry;
    }
    {
        auto entry = jsonBase;
        entry.name = "JSON.InvalidTrailing";
        entry.input = "{}garbage";
        entry.defaultIterations = 10;
        entry.expectedAccepted = false;
        benchmarks ~= entry;
    }
    {
        auto entry = jsonBase;
        entry.name = "JSON.InvalidTruncated";
        entry.input = "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[0]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]";
        entry.defaultIterations = 10;
        entry.expectedAccepted = false;
        benchmarks ~= entry;
    }

    foreach (ending; "bcd") {
        auto entry = jsonBase;
        entry.name = ending == 'b' ? "Ambiguous.First" : ending == 'c' ? "Ambiguous.Retry" : "Ambiguous.Invalid";
        entry.input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ~ ending;
        entry.defaultIterations = 100;
        entry.expectedAccepted = ending != 'd';
        benchmarks ~= entry;
    }

    // Differential acceptance gate, independent of the timed corpus/filter.
    static immutable string[] jsonValid = [
        "{}", "[]", "null", "-0.995e+2", `{"a":[true,false,null,"\u0041\n\/",-12.5E-2]}`, " \t[0]\r\n"
    ];
    static immutable string[] jsonInvalid = [
        "", "01", "1.", "1e", "+1", "[1,]", `{"a":1,}`, `"\q"`, "\"raw\nnewline\"", "{}garbage", "[",
        `"\u123"`
    ];
    foreach (expected; 0 .. 2) {
        foreach (input; expected ? jsonValid : jsonInvalid) {
            ParseContext context;
            auto np = NPJson.JSON(context, input);
            auto p = PJson.JSON(input);
            const want = expected != 0;
            if ((np.successful && np.end == input.length) != want || (p.successful
                    && p.end == input.length) != want || HWJson.JsonParser.parse(input) != want) {
                fprintf(stderr, "JSON differential acceptance gate failed: input=%.*s expected=%d NP=%d/%zu Pegged=%d/%zu HW=%d\n",
                        cast(int)input.length, input.ptr, want, np.successful, np.end,
                        p.successful, p.end, HWJson.JsonParser.parse(input));
                return 1;
            }
        }
    }

    if (exportCorpus) {
        putchar('[');
        size_t count;
        foreach (ref bc; benchmarks) {
            if (!contains(bc.name, "JSON.") && !contains(bc.name, "Ambiguous."))
                continue;
            if (count++)
                putchar(',');
            exportJsonCase(bc.name, bc.input, bc.expectedAccepted, bc.defaultIterations, true,
                    contains(bc.name, "Ambiguous."));
        }
        foreach (expected; 0 .. 2) {
            foreach (input; expected ? jsonValid : jsonInvalid) {
                if (count++)
                    putchar(',');
                exportJsonCase("AcceptanceGate", input, expected != 0, 1, false);
            }
        }
        printf("]\n");
        return 0;
    }

    size_t matched;
    if (jsonOutput)
        printf("{\"schemaVersion\":2,\"benchmarks\":[");
    else
        printf("Times include output construction, consumption, and disposal. Execution modes identify internal tree projection.\n");
    foreach (ref bc; benchmarks) {
        if (!contains(bc.name, filterPattern) || (comparison && !contains(bc.name, "JSON.")
                && !contains(bc.name, "Ambiguous.")))
            continue;
        size_t iterations = customIterations ? customIterations : bc.defaultIterations;
        // Checks deliberately remain outside timing and do not depend on assert.
        if (comparison && !verifyOutputs(bc.input, mode, bc.expectedAccepted, contains(bc.name, "Ambiguous."))) {
            fprintf(stderr, "JSON output records differ: %.*s\n", cast(int)bc.name.length, bc.name
                    .ptr);
            return 1;
        }
        const reference = observeCase(bc, 2, comparison, mode);
        foreach (engine; 0 .. 3) {
            const actual = observeCase(bc, engine, comparison, mode);
            if (actual.status != Status.ok || actual.accepted != bc.expectedAccepted || (comparison
                    && (actual.outputHash != reference.outputHash || actual.outputNodes != reference
                    .outputNodes))) {
                fprintf(stderr, "Acceptance/output equivalence failure: %.*s engine=%zu\n",
                        cast(int)bc.name.length, bc.name.ptr, cast(size_t)engine);
                return 1;
            }
        }
        foreach (engine; 0 .. 3) {
            // Identical iteration counts for timing and allocation normalization.
            double minimum = double.max, maximum = 0, sum = 0;
            ulong gcBytes;
            Buffer!double sampleTimes;
            foreach (sample; 0 .. samples + 1) {
                GC.collect();
                GC.minimize();
                auto before = GC.stats().allocatedInCurrentThread;
                const seed = currentChecksum();
                auto start = MonoTime.currTime;
                foreach (i; 0 .. iterations) {
                    const observation = observeCase(bc, engine, comparison, mode);
                    consume(observation.accepted, observation.outputHash, observation.outputNodes, observation
                            .status);
                }
                auto elapsed = (MonoTime.currTime - start).total!"nsecs" / 1_000_000.0;
                auto after = GC.stats().allocatedInCurrentThread;
                if (currentChecksum() != expectedChecksum(seed, reference, iterations)) {
                    fprintf(stderr, "Timed result checksum differs: %.*s engine=%zu\n",
                            cast(int)bc.name.length, bc.name.ptr, cast(size_t)engine);
                    return 1;
                }
                if (sample == 0)
                    continue; // untimed warmup sample
                if (elapsed < minimum)
                    minimum = elapsed;
                if (elapsed > maximum)
                    maximum = elapsed;
                sum += elapsed;
                if (!sampleTimes.put(elapsed))
                    return 1;
                gcBytes += after >= before ? after - before : 0;
            }
            const mean = sum / samples;
            const throughput = mean > 0 ? bc.input.length * cast(double)iterations / (mean * 1000) : 0;
            const gcPerOp = gcBytes / samples / iterations;
            string engineName = engine == 0 ? "Pegged" : engine == 1 ? "NPegged" : "Handwritten";
            string obligation = comparison ? (mode == OutputMode.validation
                    ? "validation" : mode == OutputMode.spans ? "spans" : "tree") : engine == 2
                ? "validation" : "full-tree";
            const observed = comparison || contains(bc.name, "Ambiguous.") ? observeCase(bc, engine,
                    comparison, mode) : Observation.init;
            const arenaMeasured = measureMemory && (comparison ? observed.allocatorMeasured : engine == 1);
            const arena = !measureMemory ? ArenaMetrics.init : comparison || contains(bc.name,
                    "Ambiguous.") ? ArenaMetrics(observed.allocationCalls,
                    observed.payloadBytes, observed.reservedBytes) : engine == 1
                ? bc.getNPeggedArenaPeak(bc.input) : ArenaMetrics.init;
            string execution = engine == 2 ? "direct" : comparison && engine == 1
                && mode == OutputMode.validation
                ? "recognition" : comparison ? "native-tree-projection" : "native-tree";
            if (jsonOutput) {
                if (matched)
                    printf(",");
                printf("{\"name\":\"%.*s\",\"engine\":\"%.*s\",\"output\":\"%.*s\",\"inputBytes\":%zu,\"iterations\":%zu,\"samples\":%zu,\"meanMs\":%.9f,\"minMs\":%.9f,\"maxMs\":%.9f,\"MBps\":%.6f,\"gcBytesPerOp\":%llu,\"execution\":\"%.*s\",\"expectedAccepted\":%s,\"outputHash\":%llu,\"outputNodes\":%zu,\"arenaMeasured\":%s,\"allocatorCallsPerOp\":%zu,\"payloadBytesPerOp\":%zu,\"reservedBytesPerOp\":%zu,\"arenaCumulativeBytes\":%zu",
                        cast(int)bc.name.length, bc.name.ptr, cast(int)engineName.length,
                        engineName.ptr, cast(int)obligation.length, obligation.ptr,
                        bc.input.length, iterations, samples, mean, minimum, maximum, throughput,
                        gcPerOp, cast(int)execution.length, execution.ptr, (bc.expectedAccepted
                            ? "true" : "false").ptr, observed.outputHash, observed.outputNodes,
                        (arenaMeasured ? "true" : "false")
                            .ptr, arena.calls, arena.requestedBytes, arena.reservedBytes, arena
                            .reservedBytes);
                printf(",\"allocatorMeasured\":%s,\"allocationScope\":\"%s\",\"sampleMs\":[",
                        (arenaMeasured ? "true" : "false")
                            .ptr, (engine == 0 ? "output-adapter" : comparison ? "parser+output" : "parser")
                            .ptr);
                foreach (i, elapsed; sampleTimes.data) {
                    if (i)
                        putchar(',');
                    printf("%.9f", elapsed);
                }
                printf("]}");
            } else
                printf("%.*s %.*s output=%.*s mean=%.6f ms range=[%.6f,%.6f] MB/s=%.3f GC/op=%llu allocator calls=%zu payload=%zu reserved=%zu arena measured=%d\n",
                        cast(int)bc.name.length, bc.name.ptr, cast(int)engineName.length,
                        engineName.ptr, cast(int)obligation.length, obligation.ptr, mean, minimum,
                        maximum, throughput, gcPerOp, arena.calls, arena.requestedBytes,
                        arena.reservedBytes, arenaMeasured);
            ++matched;
        }
    }
    if (jsonOutput)
        printf("],\"checksum\":%llu}\n", currentChecksum());
    else
        printf("Checksum: %llu\n", currentChecksum());
    return matched ? 0 : 1;
}

unittest {
    string[2] args = ["benchmark_runner", "--help"];
    assert(main(args[]) == 0);
    args[1] = "--invalid";
    assert(main(args[]) == 2);
}
