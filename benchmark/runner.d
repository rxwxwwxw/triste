module benchmark.runner;

import core.memory : GC;
import core.stdc.stdio : printf, fprintf, stderr, putchar;
import core.time : MonoTime;
import benchmark.measurement : consume, currentChecksum, expectedChecksum, opaqueInput;
import benchmark.workload_grammars : observeWorkload, observeWorkloadAccept;
import benchmark.workload_output : observeWorkloadOutput, verifyWorkloadOutput,
    supportsWorkloadOutput, arithmeticOutput, csvOutput;
import benchmark.scalar_output : handwrittenScalarOutput;
import benchmark.options : Options, OptionStatus, parseOptions;
import benchmark.corpus_index : CorpusRow, parseCorpusRow, readWholeFile, isValidUtf8;
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
    bool workloadPair;
    bool largeInput;
}

/// `--accept`: the workload suite's validation obligation is answered by `accept!` (decision D3).
__gshared bool acceptObligation;

Observation observeCase(ref BenchmarkCase bc, size_t engine, bool comparison, OutputMode mode) {
    const input = opaqueInput(bc.input);
    if (bc.workloadPair) {
        if (mode == OutputMode.validation)
            return acceptObligation ? observeWorkloadAccept(bc.name, input, engine == 2)
                : observeWorkload(bc.name, input, engine == 2);
        return observeWorkloadOutput(bc.name, input, mode, engine == 2);
    }
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

/// `latin1` escapes every byte >= 0x80 as \u00XX so that bytes that are not valid UTF-8 survive a JSON round trip.
void writeJsonString(string value, bool latin1 = false) @nogc nothrow {
    putchar('"');
    foreach (ubyte c; cast(const(ubyte)[])value) {
        if (c == '"' || c == '\\') {
            putchar('\\');
            putchar(c);
        } else if (c < 32 || latin1 && c >= 0x80)
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

@nogc nothrow unittest {
    import benchmark.test_output : CapturedStdout;

    auto capture = CapturedStdout.open();
    writeJsonString("a\xFF\xC3\xA9", true);
    char[64] text;
    auto length = capture.read(text);
    assert(text[0 .. length] == `"a\u00ff\u00c3\u00a9"`);
}

void exportJsonCase(string name, string input, bool expected, size_t iterations, bool timed, bool ambiguous = false) @nogc nothrow {
    printf("{\"name\":");
    writeJsonString(name);
    const latin1 = !isValidUtf8(input);
    printf(",\"input\":");
    writeJsonString(input, latin1);
    if (latin1)
        printf(",\"inputLatin1\":true");
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

/// Q2: benchmark cases for the G7 corpora. `JSON.corpus.<label>.<name>` joins the JSON suite and
/// `Arithmetic.corpus...`/`CSV.corpus...` the handwritten-workload suite, so every case is compared with its
/// handwritten twin and its output is verified before timing. Entries whose file is missing (large, uncommitted)
/// are skipped; a row whose file length differs from the index is a hard error (stale corpus).
bool addCorpusCases(ref BenchmarkCase[] benchmarks, string indexPath, bool workloadSuite, ref size_t skipped) {
    const text = readWholeFile(indexPath);
    if (text is null) {
        fprintf(stderr, "Cannot read corpus index %.*s\n", cast(int)indexPath.length, indexPath.ptr);
        return false;
    }
    size_t begin;
    bool header = true;
    foreach (i; 0 .. text.length + 1) {
        if (i != text.length && text[i] != '\n')
            continue;
        const line = text[begin .. i];
        begin = i + 1;
        if (header) {
            header = false;
            continue;
        }
        if (!line.length)
            continue;
        CorpusRow row;
        if (!parseCorpusRow(line, row)) {
            fprintf(stderr, "Malformed corpus index row: %.*s\n", cast(int)line.length, line.ptr);
            return false;
        }
        const prefix = row.family == "json" ? "JSON." : row.family == "arithmetic"
            ? "Arithmetic." : row.family == "csv" ? "CSV." : null;
        if (prefix is null || (row.family == "json") == workloadSuite)
            continue;
        const input = readWholeFile(row.path);
        if (input is null) {
            ++skipped;
            continue;
        }
        if (input.length != row.bytes) {
            fprintf(stderr, "Corpus file %.*s has %zu bytes, index says %zu\n",
                    cast(int)row.path.length, row.path.ptr, input.length, row.bytes);
            return false;
        }
        BenchmarkCase bc;
        bc.name = prefix ~ "corpus." ~ row.label ~ "." ~ row.name;
        bc.input = input;
        bc.expectedAccepted = row.valid;
        bc.defaultIterations = input.length >= 65536 ? 20 : input.length >= 4096 ? 200 : 1000;
        bc.largeInput = input.length >= 65536;
        benchmarks ~= bc;
    }
    return true;
}

int main(string[] args) {
    Options options;
    const status = parseOptions(args, options);
    if (status == OptionStatus.invalid) {
        fprintf(stderr, "Invalid benchmark options; use --help\n");
        return 2;
    }
    if (status == OptionStatus.help) {
        printf("Default: canonical full trees; --mode selects an explicit comparison cohort.\n");
        printf("Usage: benchmark_runner [--iterations=N|-n N] [--samples=N] [--filter=TEXT|-f TEXT] [--json] [--memory] [--export-corpus] [--target-engines] [--workloads] [--mode=validation|spans|tree] [--corpus-index=PATH] [--families] [--accept]\n");
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
    if (options.accept && (!options.workloads || options.mode != OutputMode.validation)) {
        fprintf(stderr, "--accept applies to the workload suite in validation mode (--workloads --mode=validation)\n");
        return 2;
    }
    acceptObligation = options.accept;

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

    if (options.families && !options.workloads) {
        // Q2: families the earlier registry lacked. Names are `JSON.family.<family>.<Case>`.
        enum medium = mediumJson;
        string spaced = "  ";
        foreach (_; 0 .. 11)
            spaced ~= spaced;
        struct FamilyInput {
            string name, input;
            bool accepted;
        }

        static immutable utf8Valid = "[\"\u00e9\", \"\xE6\x97\xA5\xE6\x9C\xAC\", \"\xF0\x9F\x98\x80\", {\"k\xC3\xA9y\": \"v\xC3\xA9\"}]";
        FamilyInput[] additions = [
            FamilyInput("JSON.family.lex_utf8.Multibyte",
                    utf8Valid,
                    true), FamilyInput("JSON.family.lex_utf8.TruncatedTail", "[\"abc\xC3", false),
            FamilyInput("JSON.family.lex_utf8.RawInvalidBytes", "[\"\xFF\xFE\xC0\x80\"]", true),
            FamilyInput("JSON.family.failure.FirstByte", "}", false),
            FamilyInput("JSON.family.failure.LastByte", medium[0 .. $ - 1] ~ ")", false),
            FamilyInput("JSON.family.pathological.WhitespaceThenError", spaced ~ "x", false)
        ];
        foreach (addition; additions) {
            auto entry = jsonBase;
            entry.name = addition.name;
            entry.input = addition.input;
            entry.defaultIterations = 200;
            entry.expectedAccepted = addition.accepted;
            benchmarks ~= entry;
        }
    }

    if (options.workloads) {
        struct WorkloadInput {
            string name, input;
            bool accepted;
        }

        static immutable extra = [
            WorkloadInput("Arithmetic.Unary", "a_1 + -+2.3", true),
            WorkloadInput("Arithmetic.Truncated", "1 + 2 * (3 -", false),
            WorkloadInput("Arithmetic.Trailing", "1 + 2)", false),
            WorkloadInput("Arithmetic.InvalidNumber", "1.", false),
            WorkloadInput("Arithmetic.Empty", "", false), WorkloadInput("CSV.Empty", "", true),
            WorkloadInput("CSV.EmptyQuoted", `"","a""b",`, true),
            WorkloadInput("CSV.MultilineQuoted", "a,\"line\nbreak\"\r\n1,2\r", true),
            WorkloadInput("CSV.Truncated", `a,"unterminated`, false),
            WorkloadInput("CSV.InvalidSpacing", "a b,c", false),
            WorkloadInput("CSV.Trailing", `"a"x`, false),
            WorkloadInput("Numbers.ScientificTruncated", "123e+", false),
            WorkloadInput("Numbers.ScientificTrailing", "123.4x", false),
            WorkloadInput("Numbers.ScientificEmpty", "", false),
            WorkloadInput("Numbers.Hexa", "deadBEEF0123456789", true),
            WorkloadInput("Numbers.HexaInvalid", "0x12", false),
            WorkloadInput("Numbers.Binary", "0b1010_0101_", true),
            WorkloadInput("Numbers.BinaryInvalid", "0b_1", false),
            WorkloadInput("PEGGrammar.Permissive", "G: A <-- / []**", true),
            WorkloadInput("PEGGrammar.Truncated", "G: A <- ('a'", false),
            WorkloadInput("PEGGrammar.Trailing", "G: A <- 'a' )", false),
            WorkloadInput("PEGGrammar.Empty", "G:", false),
            WorkloadInput("Ops.Short", "<= == != ++ --", true), WorkloadInput("Ops.Empty", "",
                    true), WorkloadInput("Ops.Invalid", "<= a", false),
            WorkloadInput("Ops.Pairs", "== = =", true), WorkloadInput("Ops.Truncated", "<<=<x",
                    false), WorkloadInput("LeftExpr.Small",
                    "1 + 2 * (3 - 4)", true), WorkloadInput("LeftExpr.Empty", "", false),
            WorkloadInput("LeftExpr.Trailing", "1 + 2 +", false),
            WorkloadInput("LeftExpr.Unbalanced", "((1 + 2) * 3", false)
        ];
        foreach (entry; extra) {
            BenchmarkCase bc;
            bc.name = entry.name;
            bc.input = entry.input;
            bc.expectedAccepted = entry.accepted;
            bc.defaultIterations = 2000;
            benchmarks ~= bc;
        }
        char[] digits = new char[8192];
        digits[] = '7';
        const longDigits = cast(string)digits.idup;
        string flatArithmetic = "x", flatCsv = "a", manyRules = "G:";
        foreach (i; 0 .. 512) {
            flatArithmetic ~= "+x";
            flatCsv ~= ",a";
        }
        foreach (i; 0 .. 128)
            manyRules ~= "\nR <- [a-z]+";
        string flatLeft = "1", nestedLeft = "1";
        foreach (i; 0 .. 512)
            flatLeft ~= i % 3 == 0 ? " + 2" : i % 3 == 1 ? " * 3" : " - 4";
        // The memoized left-recursive evaluation exhausts the default depth limit at about 16 nesting levels (P8).
        foreach (i; 0 .. 8)
            nestedLeft = "(" ~ nestedLeft ~ " + 1)";
        string longOperators;
        foreach (i; 0 .. 256)
            longOperators ~= "<<= == != && || ++ -- += -= *= /= < > ! & | + - * / ";
        string nestedArithmetic = "x", nestedPeg = "'x'";
        foreach (i; 0 .. 64) {
            nestedArithmetic = "(" ~ nestedArithmetic ~ ")";
            nestedPeg = "(" ~ nestedPeg ~ ")";
        }
        char[] bits = new char[8192];
        bits[] = '1';
        const longBits = cast(string)bits.idup;
        foreach (entry; [
            WorkloadInput("Arithmetic.Flat", flatArithmetic, true),
            WorkloadInput("Arithmetic.Deep", nestedArithmetic, true),
            WorkloadInput("Arithmetic.LongNumber", longDigits, true),
            WorkloadInput("CSV.Flat", flatCsv, true), WorkloadInput("CSV.LongField", longDigits,
                    true), WorkloadInput("CSV.LongQuoted", "\"" ~ longDigits ~ "\"", true),
            WorkloadInput("CSV.LongTruncated", "\"" ~ longDigits, false),
            WorkloadInput("Numbers.ScientificLong", longDigits ~ "." ~ longDigits ~ "e+123", true),
            WorkloadInput("Numbers.HexaLong", longDigits, true),
            WorkloadInput("Numbers.BinaryLong", "0b" ~ longBits, true),
            WorkloadInput("PEGGrammar.ManyRules", manyRules, true),
            WorkloadInput("PEGGrammar.Deep", "G: R <- " ~ nestedPeg, true),
            WorkloadInput("PEGGrammar.LongLiteral", "G: R <- '" ~ longDigits ~ "'", true),
            WorkloadInput("PEGGrammar.LongTruncated", "G: R <- '" ~ longDigits, false),
            WorkloadInput("Ops.Long", longOperators, true),
            WorkloadInput("Ops.LongInvalid", longOperators ~ "a", false),
            WorkloadInput("LeftExpr.Flat", flatLeft, true),
            WorkloadInput("LeftExpr.Deep", nestedLeft, true),
            WorkloadInput("LeftExpr.FlatInvalid", flatLeft ~ "+", false)
        ]) {
            BenchmarkCase bc;
            bc.name = entry.name;
            bc.input = entry.input;
            bc.expectedAccepted = entry.accepted;
            bc.defaultIterations = 2000;
            benchmarks ~= bc;
        }

    }

    if (options.corpusIndex.length) {
        size_t skippedCorpora;
        if (!addCorpusCases(benchmarks, options.corpusIndex, options.workloads, skippedCorpora))
            return 2;
        if (skippedCorpora)
            fprintf(stderr, "corpus: %zu index entries skipped (file not present)\n", skippedCorpora);
    }

    foreach (ref bc; benchmarks)
        bc.workloadPair = (options.workloads || !options.explicitMode && !options.exportCorpus)
            && !contains(bc.name, "JSON.") && !contains(bc.name, "Ambiguous.");

    if (exportCorpus) {
        putchar('[');
        size_t count;
        foreach (ref bc; benchmarks) {
            if (options.workloads ? !bc.workloadPair : !contains(bc.name, "JSON.") && !contains(bc
                    .name, "Ambiguous."))
                continue;
            if (bc.workloadPair && mode != OutputMode.validation && !supportsWorkloadOutput(bc.name))
                continue;
            if (count++)
                putchar(',');
            if (bc.workloadPair) {
                printf("{\"name\":");
                writeJsonString(bc.name);
                const latin1 = !isValidUtf8(bc.input);
                printf(",\"input\":");
                writeJsonString(bc.input, latin1);
                if (latin1)
                    printf(",\"inputLatin1\":true");
                const obligation = mode == OutputMode.validation ? (acceptObligation
                        ? "accept" : "validation") : mode == OutputMode.spans ? "spans" : "tree";
                printf(",\"grammar\":\"workload\",\"output\":\"%s\",\"expectedAccepted\":%s,\"iterations\":%zu,\"timed\":true",
                        obligation.ptr, (bc.expectedAccepted ? "true" : "false").ptr, bc
                            .defaultIterations);
                if (mode != OutputMode.validation) {
                    if (contains(bc.name, "Numbers.") || contains(bc.name, "PEGGrammar.")) {
                        auto output = handwrittenScalarOutput(bc.name, bc.input, mode);
                        printf(",\"expectedRecords\":[");
                        foreach (i, node; output.nodes) {
                            if (i)
                                putchar(',');
                            printf("[%u,%zu,%zu,%zu]", node.kind, node.begin, node.end, node.parent);
                        }
                        putchar(']');
                    } else {
                        auto output = contains(bc.name, "Arithmetic.") ? arithmeticOutput(bc.input, mode) : csvOutput(
                                bc.input, mode);
                        printf(",\"expectedRecords\":[");
                        foreach (i, node; output.nodes) {
                            if (i)
                                putchar(',');
                            printf("[%u,%zu,%zu,%zu]", node.kind, node.begin, node.end, node.parent);
                        }
                        putchar(']');
                    }
                }
                putchar('}');
            } else
                exportJsonCase(bc.name, bc.input, bc.expectedAccepted, bc.defaultIterations, true,
                        contains(bc.name, "Ambiguous."));
        }
        if (!options.workloads)
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
        if (options.workloads && (!bc.workloadPair || mode != OutputMode.validation && !supportsWorkloadOutput(
                bc.name)))
            continue;
        if (!contains(bc.name, filterPattern) || (comparison && !bc.workloadPair
                && !contains(bc.name, "JSON.") && !contains(bc.name, "Ambiguous.")))
            continue;
        size_t iterations = customIterations ? customIterations : bc.defaultIterations;
        if (bc.largeInput && iterations > 16)
            iterations /= 16;
        // Checks deliberately remain outside timing and do not depend on assert.
        if (comparison && !bc.workloadPair && !verifyOutputs(bc.input, mode, bc.expectedAccepted,
                contains(bc.name, "Ambiguous."))) {
            fprintf(stderr, "JSON output records differ: %.*s\n", cast(int)bc.name.length, bc.name
                    .ptr);
            return 1;
        }
        if (bc.workloadPair && mode != OutputMode.validation && !verifyWorkloadOutput(bc.name,
                bc.input, mode, bc.expectedAccepted)) {
            fprintf(stderr, "Workload output records differ: %.*s\n", cast(int)bc.name.length, bc
                    .name.ptr);
            return 1;
        }
        const reference = observeCase(bc, 2, comparison, mode);
        foreach (engine; 0 .. 3) {
            if (bc.workloadPair && engine == 0)
                continue;
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
            if ((options.targetEngines || bc.workloadPair) && engine == 0)
                continue;
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
            string obligation = comparison ? (mode == OutputMode.validation ? (acceptObligation
                    ? "accept" : "validation") : mode == OutputMode.spans ? "spans" : "tree")
                : engine == 2 ? "validation" : "full-tree";
            const observed = comparison || contains(bc.name, "Ambiguous.") ? observeCase(bc, engine,
                    comparison, mode) : Observation.init;
            const arenaMeasured = measureMemory && (comparison ? observed.allocatorMeasured : engine == 1);
            const arena = !measureMemory ? ArenaMetrics.init : comparison || contains(bc.name,
                    "Ambiguous.") ? ArenaMetrics(observed.allocationCalls,
                    observed.payloadBytes, observed.reservedBytes) : engine == 1
                ? bc.getNPeggedArenaPeak(bc.input) : ArenaMetrics.init;
            string execution = engine == 2 ? "direct" : comparison && engine == 1
                ? (mode == OutputMode.validation
                        ? "recognition" : "compact-records-borrowed") : comparison
                ? "native-tree-projection" : "native-tree";
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
