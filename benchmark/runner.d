module benchmark.runner;

import core.memory : GC;
import core.time : Duration, MonoTime;
import std.algorithm.searching : canFind;
import std.conv : to;
import std.format : format;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.stdio : stdout, write, writefln, writeln;
import std.string : strip;

import npegged.peg : ParseContext, ParseResult;
import pegged.peg : PeggedParseTree = ParseTree;

import NPArith = npegged.examples.arithmetic;
import PArith = pegged.examples.arithmetic;

import NPJson = npegged.examples.json;
import PJson = pegged.examples.json;

import NPCsv = npegged.examples.csv;
import PCsv = pegged.examples.csv;

import NPParser = npegged.parser;
import PParser = pegged.parser;

struct BenchResult {
    string name;
    size_t inputBytes;
    size_t iterations;
    double peggedTimeMs;
    double npeggedTimeMs;
    ulong peggedAllocBytes;
    ulong npeggedAllocBytes;

    double speedup() const pure @safe {
        if (npeggedTimeMs <= 0.0)
            return 0.0;
        return peggedTimeMs / npeggedTimeMs;
    }

    double peggedAvgUs() const pure @safe {
        if (iterations == 0)
            return 0.0;
        return (peggedTimeMs * 1000.0) / iterations;
    }

    double npeggedAvgUs() const pure @safe {
        if (iterations == 0)
            return 0.0;
        return (npeggedTimeMs * 1000.0) / iterations;
    }

    ulong peggedBytesPerOp() const pure @safe {
        if (iterations == 0)
            return 0;
        return peggedAllocBytes / iterations;
    }

    ulong npeggedBytesPerOp() const pure @safe {
        if (iterations == 0)
            return 0;
        return npeggedAllocBytes / iterations;
    }

    double peggedThroughput() const pure @safe {
        if (peggedTimeMs <= 0.0)
            return 0.0;
        return (iterations * 1000.0) / peggedTimeMs;
    }

    double npeggedThroughput() const pure @safe {
        if (npeggedTimeMs <= 0.0)
            return 0.0;
        return (iterations * 1000.0) / npeggedTimeMs;
    }
}

alias PeggedFn = void delegate(string);
alias NPeggedFn = void delegate(string, ref ParseContext);

struct BenchmarkCase {
    string name;
    string input;
    size_t defaultIterations;
    PeggedFn runPegged;
    NPeggedFn runNPegged;
}

BenchResult executeBenchmark(BenchmarkCase bc, size_t iterations) {
    // 1. Warmup & correctness verification
    ParseContext verifyCtx;
    bc.runPegged(bc.input);
    bc.runNPegged(bc.input, verifyCtx);

    // Warmup cycles
    enum warmup = 5;
    for (size_t i = 0; i < warmup; ++i) {
        bc.runPegged(bc.input);
        ParseContext wCtx;
        bc.runNPegged(bc.input, wCtx);
    }

    // 2. Measure Pegged
    GC.collect();
    GC.minimize();
    const ulong gcStartPegged = GC.stats().allocatedInCurrentThread;
    const MonoTime t0Pegged = MonoTime.currTime();
    for (size_t i = 0; i < iterations; ++i) {
        bc.runPegged(bc.input);
    }
    const MonoTime t1Pegged = MonoTime.currTime();
    const ulong gcEndPegged = GC.stats().allocatedInCurrentThread;
    const double peggedMs = (t1Pegged - t0Pegged).total!"usecs" / 1000.0;
    const ulong peggedAlloc = (gcEndPegged >= gcStartPegged) ? (gcEndPegged - gcStartPegged) : 0;

    // 3. Measure NPegged
    GC.collect();
    GC.minimize();
    const ulong gcStartNPegged = GC.stats().allocatedInCurrentThread;
    const MonoTime t0NPegged = MonoTime.currTime();
    for (size_t i = 0; i < iterations; ++i) {
        ParseContext ctx;
        bc.runNPegged(bc.input, ctx);
    }
    const MonoTime t1NPegged = MonoTime.currTime();
    const ulong gcEndNPegged = GC.stats().allocatedInCurrentThread;
    const double npeggedMs = (t1NPegged - t0NPegged).total!"usecs" / 1000.0;
    const ulong npeggedAlloc = (gcEndNPegged >= gcStartNPegged) ? (gcEndNPegged - gcStartNPegged) : 0;

    return BenchResult(bc.name, bc.input.length, iterations, peggedMs, npeggedMs, peggedAlloc, npeggedAlloc);
}

string formatBytes(ulong bytes) pure @safe {
    if (bytes >= 1024 * 1024)
        return format("%.2f MB", bytes / (1024.0 * 1024.0));
    if (bytes >= 1024)
        return format("%.1f KB", bytes / 1024.0);
    return format("%d B", bytes);
}

void printAsciiTable(const BenchResult[] results) {
    writeln();
    writeln("======================================================================================================================");
    writefln(" %-22s | %-8s | %-6s | %-12s | %-12s | %-8s | %-12s | %-12s", "Benchmark", "Size",
            "Iters", "Pegged (ms)", "NPegged (ms)", "Speedup", "Pegged GC/op", "NPegged GC/op");
    writeln("======================================================================================================================");

    double totalPeggedMs = 0.0;
    double totalNPeggedMs = 0.0;
    ulong totalPeggedAlloc = 0;
    ulong totalNPeggedAlloc = 0;

    foreach (ref r; results) {
        totalPeggedMs += r.peggedTimeMs;
        totalNPeggedMs += r.npeggedTimeMs;
        totalPeggedAlloc += r.peggedAllocBytes;
        totalNPeggedAlloc += r.npeggedAllocBytes;

        writefln(" %-22s | %-8s | %-6d | %12.2f | %12.2f | %7.2fx | %12s | %12s", r.name,
                formatBytes(r.inputBytes), r.iterations, r.peggedTimeMs, r.npeggedTimeMs,
                r.speedup(), formatBytes(r.peggedBytesPerOp()), formatBytes(r.npeggedBytesPerOp()));
    }

    writeln("======================================================================================================================");
    const double overallSpeedup = (totalNPeggedMs > 0.0) ? (totalPeggedMs / totalNPeggedMs) : 0.0;
    writefln(" %-22s | %-8s | %-6s | %12.2f | %12.2f | %7.2fx | %12s | %12s", "TOTAL / OVERALL",
            "-", "-", totalPeggedMs, totalNPeggedMs,
            overallSpeedup, formatBytes(totalPeggedAlloc), formatBytes(totalNPeggedAlloc));
    writeln("======================================================================================================================");
    writeln();
    writefln("Summary:");
    writefln("  - Benchmarks evaluated: %d", results.length);
    writefln("  - Overall Speedup:      %.2fx faster than vendored Pegged", overallSpeedup);
    writefln("  - Pegged GC Churn:      %s", formatBytes(totalPeggedAlloc));
    writefln("  - NPegged GC Churn:     %s (@nogc deterministic lifetime)", formatBytes(totalNPeggedAlloc));
    writeln();
}

void printJsonOutput(const BenchResult[] results) {
    writeln("{");
    writeln("  \"benchmarks\": [");
    foreach (i, ref r; results) {
        writefln("    {");
        writefln("      \"name\": \"%s\",", r.name);
        writefln("      \"inputBytes\": %d,", r.inputBytes);
        writefln("      \"iterations\": %d,", r.iterations);
        writefln("      \"peggedTimeMs\": %.4f,", r.peggedTimeMs);
        writefln("      \"npeggedTimeMs\": %.4f,", r.npeggedTimeMs);
        writefln("      \"speedup\": %.4f,", r.speedup());
        writefln("      \"peggedAvgUs\": %.4f,", r.peggedAvgUs());
        writefln("      \"npeggedAvgUs\": %.4f,", r.npeggedAvgUs());
        writefln("      \"peggedThroughput\": %.2f,", r.peggedThroughput());
        writefln("      \"npeggedThroughput\": %.2f,", r.npeggedThroughput());
        writefln("      \"peggedAllocBytes\": %d,", r.peggedAllocBytes);
        writefln("      \"npeggedAllocBytes\": %d,", r.npeggedAllocBytes);
        writefln("      \"peggedBytesPerOp\": %d,", r.peggedBytesPerOp());
        writefln("      \"npeggedBytesPerOp\": %d", r.npeggedBytesPerOp());
        if (i + 1 < results.length)
            writeln("    },");
        else
            writeln("    }");
    }
    writeln("  ]");
    writeln("}");
}

int main(string[] args) {
    size_t customIterations = 0;
    string filterPattern = "";
    bool jsonOutput = false;

    GetoptResult helpInfo;
    try {
        helpInfo = getopt(args, "iterations|n", "Override iteration count for all benchmarks",
                &customIterations, "filter|f",
                "Run only benchmarks whose name contains this substring",
                &filterPattern, "json", "Output results in JSON format", &jsonOutput);
    } catch (Exception e) {
        writefln("Error: %s", e.msg);
        return 1;
    }

    if (helpInfo.helpWanted) {
        defaultGetoptPrinter(
                "Benchmark Suite: NPegged vs Vendored Pegged\n\nUsage: benchmark_runner [options]",
                helpInfo.options);
        return 0;
    }

    // Benchmark definitions
    BenchmarkCase[] benchmarks;

    // 1. Arithmetic
    benchmarks ~= BenchmarkCase("Arithmetic.Small", "1 + 2 * (3 - 4)", 1000, (string s) {
        auto tree = PArith.Arithmetic(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) {
        auto res = NPArith.Arithmetic(ctx, s);
        assert(res.successful);
    });

    benchmarks ~= BenchmarkCase("Arithmetic.Medium",
            "1 + 2 * (3 + 10 / 4) - (5 * 6 + 7) * (8 - 9 / (2 + 3))", 500, (string s) {
        auto tree = PArith.Arithmetic(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) {
        auto res = NPArith.Arithmetic(ctx, s);
        assert(res.successful);
    });

    benchmarks ~= BenchmarkCase("Arithmetic.Nested",
            "(((1 + 2) * 3 - 4) / 5 + (6 * (7 - 8))) * (((9 + 10) * 11 - 12) / 13 + (14 * (15 - 16)))",
            500, (string s) { auto tree = PArith.Arithmetic(s); assert(tree.successful); },
            (string s, ref ParseContext ctx) {
        auto res = NPArith.Arithmetic(ctx, s);
        assert(res.successful);
    });

    // 2. JSON
    benchmarks ~= BenchmarkCase("JSON.Small",
            `{"name": "test", "id": 12345, "active": true, "score": 98.6}`, 500, (string s) {
        auto tree = PJson.JSON(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) { auto res = NPJson.JSON(ctx, s); assert(res.successful); });

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
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) { auto res = NPJson.JSON(ctx, s); assert(res.successful); });

    // 3. CSV
    benchmarks ~= BenchmarkCase("CSV.SingleLine", `id,first_name,last_name,email,gender,ip_address`, 1000,
            (string s) { auto tree = PCsv.CSV(s); assert(tree.successful); }, (string s, ref ParseContext ctx) {
        auto res = NPCsv.CSV(ctx, s);
        assert(res.successful);
    });

    enum multiLineCsv = "id,name,role,department,score\n"
        ~ "1,Alice Smith,Engineer,Platform,94.5\n"
        ~ "2,Bob Jones,Manager,\"Operations, HQ\",88.0\n" ~ "3,Charlie Brown,Analyst,Data,91.2\n"
        ~ "4,Diana Prince,Architect,\"Security & Trust\",99.0\n"
        ~ "5,Evan Wright,Developer,Frontend,85.7\n" ~ "6,Fiona Gallagher,QA,Verification,92.3\n"
        ~ "7,George Clark,DevOps,Infrastructure,89.1\n"
        ~ "8,Hannah Abbott,Support,\"Customer Success, US\",87.4\n"
        ~ "9,Ian Malcolm,Consultant,Chaos,96.8\n" ~ "10,Julia Roberts,Designer,Product,90.0\n";

    benchmarks ~= BenchmarkCase("CSV.MultiLine", multiLineCsv, 300, (string s) {
        auto tree = PCsv.CSV(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) { auto res = NPCsv.CSV(ctx, s); assert(res.successful); });

    // 4. PEG Meta-Grammar Parser
    enum samplePegSmall = "Calc:\n  Expr <- Term ('+' Term)*\n  Term <- [0-9]+\n";
    benchmarks ~= BenchmarkCase("PEGGrammar.Small", samplePegSmall, 300, (string s) {
        auto tree = PParser.Pegged(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) { auto res = NPParser.Pegged(ctx, s); assert(res.successful); });

    enum samplePegMedium = "JSON:\n" ~ "  JSONObject < :'{' (Pair (:',' Pair)*)? :'}'\n"
        ~ "  Pair       < String :':' Value\n" ~ "  Array      < :'[' (Value (:',' Value)*)? :']'\n"
        ~ "  Value      < String / Number / JSONObject / Array / True / False / Null\n"
        ~ "  True       <- 'true'\n" ~ "  False      <- 'false'\n" ~ "  Null       <- 'null'\n";

    benchmarks ~= BenchmarkCase("PEGGrammar.Medium", samplePegMedium, 150, (string s) {
        auto tree = PParser.Pegged(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) { auto res = NPParser.Pegged(ctx, s); assert(res.successful); });

    BenchResult[] results;
    foreach (ref bc; benchmarks) {
        if (filterPattern.length > 0 && !bc.name.canFind(filterPattern))
            continue;

        size_t iters = (customIterations > 0) ? customIterations : bc.defaultIterations;
        if (!jsonOutput) {
            writefln("Running benchmark: %-22s (%d iterations)...", bc.name, iters);
            stdout.flush();
        }
        results ~= executeBenchmark(bc, iters);
    }

    if (results.length == 0) {
        writefln("No benchmarks matched filter: '%s'", filterPattern);
        return 1;
    }

    if (jsonOutput) {
        printJsonOutput(results);
    } else {
        printAsciiTable(results);
    }

    return 0;
}
