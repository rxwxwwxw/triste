module benchmark.runner;

import core.memory : GC;
import core.sys.posix.sys.resource : rusage;
import core.sys.posix.unistd : _exit, fork, pid_t;
import core.time : Duration, MonoTime;
import std.algorithm.searching : canFind;
import std.conv : to;
import std.format : format;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.stdio : stdout, write, writefln, writeln;
import std.string : strip;

import npegged.peg : ParseContext, ParseResult;
import pegged.peg : PeggedParseTree = ParseTree;

// 1. Arithmetic
import NPArith = npegged.examples.arithmetic;
import PArith = pegged.examples.arithmetic;
import HWArith = benchmark.handwritten.arithmetic;

// 2. JSON
import NPJson = npegged.examples.json;
import PJson = pegged.examples.json;
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

extern (C) pid_t wait4(pid_t pid, int* status, int options, rusage* rusage);

struct BenchResult {
    string name;
    size_t inputBytes;
    size_t iterations;

    // Execution time in milliseconds (high-resolution from nanoseconds)
    double peggedTimeMs;
    double npeggedTimeMs;
    double handwrittenTimeMs;
    bool hasHandwritten;

    // Allocations in bytes during the timed loop
    ulong peggedAllocBytes;
    ulong npeggedAllocBytes;
    ulong handwrittenAllocBytes;

    // Memory metrics (when --memory is requested)
    bool measuredMemory;
    long peggedPeakRssKb;
    long npeggedPeakRssKb;
    long handwrittenPeakRssKb;
    size_t npeggedArenaPeakBytes;
    size_t peggedGcPeakBytes;

    double npeggedSpeedup() const pure @safe {
        if (npeggedTimeMs <= 0.0)
            return 0.0;
        return peggedTimeMs / npeggedTimeMs;
    }

    double handwrittenSpeedup() const pure @safe {
        if (!hasHandwritten || handwrittenTimeMs <= 0.0)
            return 0.0;
        return peggedTimeMs / handwrittenTimeMs;
    }

    double npeggedVsHandwritten() const pure @safe {
        if (!hasHandwritten || handwrittenTimeMs <= 0.0)
            return 0.0;
        return npeggedTimeMs / handwrittenTimeMs;
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

    ulong handwrittenBytesPerOp() const pure @safe {
        if (!hasHandwritten || iterations == 0)
            return 0;
        return handwrittenAllocBytes / iterations;
    }
}

alias PeggedFn = void delegate(string);
alias NPeggedFn = void delegate(string, ref ParseContext);
alias HandwrittenFn = void delegate(string);
alias ArenaPeakFn = size_t delegate(string);

struct BenchmarkCase {
    string name;
    string input;
    size_t defaultIterations;
    PeggedFn runPegged;
    NPeggedFn runNPegged;
    HandwrittenFn runHandwritten; // null if no handwritten version
    ArenaPeakFn getNPeggedArenaPeak; // null if not available
}

long measureSubprocessRss(scope void delegate(string) workload, string input, size_t iters) {
    pid_t pid = fork();
    if (pid == 0) {
        for (size_t i = 0; i < iters; ++i) {
            workload(input);
        }
        _exit(0);
    }
    int status;
    rusage usage;
    wait4(pid, &status, 0, &usage);
    return usage.ru_maxrss; // in Kilobytes on Linux
}

BenchResult executeBenchmark(BenchmarkCase bc, size_t iterations, bool measureMemory) {
    const bool hasHW = (bc.runHandwritten !is null);

    // 1. Warmup & correctness verification
    ParseContext verifyCtx;
    bc.runPegged(bc.input);
    bc.runNPegged(bc.input, verifyCtx);
    if (hasHW) {
        bc.runHandwritten(bc.input);
    }

    enum warmup = 5;
    for (size_t i = 0; i < warmup; ++i) {
        bc.runPegged(bc.input);
        ParseContext wCtx;
        bc.runNPegged(bc.input, wCtx);
        if (hasHW) {
            bc.runHandwritten(bc.input);
        }
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
    const double peggedMs = (t1Pegged - t0Pegged).total!"nsecs" / 1_000_000.0;
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
    const double npeggedMs = (t1NPegged - t0NPegged).total!"nsecs" / 1_000_000.0;
    const ulong npeggedAlloc = (gcEndNPegged >= gcStartNPegged) ? (gcEndNPegged - gcStartNPegged) : 0;

    // 4. Measure Handwritten (if present)
    double hwMs = 0.0;
    ulong hwAlloc = 0;
    if (hasHW) {
        GC.collect();
        GC.minimize();
        const ulong gcStartHW = GC.stats().allocatedInCurrentThread;
        // Run enough iterations to get stable microsecond precision
        const size_t hwIters = (iterations < 5000) ? 5000 : iterations;
        const MonoTime t0HW = MonoTime.currTime();
        for (size_t i = 0; i < hwIters; ++i) {
            bc.runHandwritten(bc.input);
        }
        const MonoTime t1HW = MonoTime.currTime();
        const ulong gcEndHW = GC.stats().allocatedInCurrentThread;
        const double avgNsecs = (t1HW - t0HW).total!"nsecs" / cast(double)hwIters;
        hwMs = (avgNsecs * iterations) / 1_000_000.0;
        hwAlloc = (gcEndHW >= gcStartHW) ? (gcEndHW - gcStartHW) : 0;
    }

    // 5. Measure Peak Memory (if requested)
    long pRss = 0;
    long npRss = 0;
    long hwRss = 0;
    size_t npArenaPeak = 0;
    size_t pGcPeak = 0;

    if (measureMemory) {
        const size_t memIters = (iterations < 100) ? iterations : 100;

        pRss = measureSubprocessRss((s) { bc.runPegged(s); }, bc.input, memIters);
        npRss = measureSubprocessRss((s) { ParseContext ctx; bc.runNPegged(s, ctx); }, bc.input, memIters);

        if (hasHW) {
            hwRss = measureSubprocessRss((s) { bc.runHandwritten(s); }, bc.input, memIters);
        }

        if (bc.getNPeggedArenaPeak !is null) {
            npArenaPeak = bc.getNPeggedArenaPeak(bc.input);
        }

        GC.collect();
        GC.minimize();
        const auto gcBefore = GC.stats().usedSize;
        bc.runPegged(bc.input);
        const auto gcAfter = GC.stats().usedSize;
        pGcPeak = (gcAfter > gcBefore) ? (gcAfter - gcBefore) : 0;
    }

    return BenchResult(bc.name, bc.input.length, iterations, peggedMs, npeggedMs, hwMs, hasHW,
            peggedAlloc, npeggedAlloc, hwAlloc, measureMemory, pRss, npRss, hwRss, npArenaPeak, pGcPeak);
}

string formatBytes(ulong bytes) pure @safe {
    if (bytes >= 1024 * 1024)
        return format("%.2f MB", bytes / (1024.0 * 1024.0));
    if (bytes >= 1024)
        return format("%.1f KB", bytes / 1024.0);
    return format("%d B", bytes);
}

void printPerformanceTable(const BenchResult[] results) {
    writeln();
    writeln("===================================================================================================================================================");
    writefln(" %-20s | %-8s | %-6s | %-11s | %-11s | %-12s | %-10s | %-10s | %-12s | %-11s",
            "Benchmark", "Size", "Iters", "Pegged(ms)",
            "NPegged(ms)", "Handwritten", "NPegged vs", "HW vs", "Pegged GC/op", "NPegged GC");
    writefln(" %-20s | %-8s | %-6s | %-11s | %-11s | %-12s | %-10s | %-10s | %-12s | %-11s", "",
            "", "", "", "", "(ms)", "Pegged", "Pegged", "", "");
    writeln("===================================================================================================================================================");

    double totalPeggedMs = 0.0;
    double totalNPeggedMs = 0.0;
    ulong totalPeggedAlloc = 0;
    ulong totalNPeggedAlloc = 0;

    foreach (ref r; results) {
        totalPeggedMs += r.peggedTimeMs;
        totalNPeggedMs += r.npeggedTimeMs;
        totalPeggedAlloc += r.peggedAllocBytes;
        totalNPeggedAlloc += r.npeggedAllocBytes;

        string hwStr = r.hasHandwritten ? format("%10.3f", r.handwrittenTimeMs) : "       N/A";
        string hwSpeedupStr = r.hasHandwritten ? format("%8.1fx", r.handwrittenSpeedup()) : "       N/A";

        writefln(" %-20s | %-8s | %-6d | %11.2f | %11.2f | %12s | %9.2fx | %10s | %12s | %11s",
                r.name, formatBytes(r.inputBytes),
                r.iterations, r.peggedTimeMs, r.npeggedTimeMs, hwStr, r.npeggedSpeedup(),
                hwSpeedupStr, formatBytes(r.peggedBytesPerOp()), formatBytes(r.npeggedBytesPerOp()));
    }

    writeln("===================================================================================================================================================");
    const double overallSpeedup = (totalNPeggedMs > 0.0) ? (totalPeggedMs / totalNPeggedMs) : 0.0;
    writefln(" %-20s | %-8s | %-6s | %11.2f | %11.2f | %12s | %9.2fx | %10s | %12s | %11s",
            "TOTAL / OVERALL", "-", "-", totalPeggedMs,
            totalNPeggedMs,
            "-", overallSpeedup, "-", formatBytes(totalPeggedAlloc), formatBytes(totalNPeggedAlloc));
    writeln("===================================================================================================================================================");
    writeln();
    writefln("Summary:");
    writefln("  - Benchmarks evaluated: %d", results.length);
    writefln("  - Overall Speedup:      %.2fx faster than vendored Pegged", overallSpeedup);
    writefln("  - Pegged GC Churn:      %s", formatBytes(totalPeggedAlloc));
    writefln("  - NPegged GC Churn:     %s (@nogc deterministic lifetime)", formatBytes(totalNPeggedAlloc));
    writeln();
}

void printMemoryTable(const BenchResult[] results) {
    writeln("=========================================================================================================================================");
    writefln(" %-20s | %-8s | %-16s | %-16s | %-14s | %-16s | %-16s", "Benchmark", "Size",
            "Pegged Peak RSS", "NPegged Peak RSS", "HW Peak RSS", "Pegged Heap Live", "NPegged Arena");
    writeln("=========================================================================================================================================");

    foreach (ref r; results) {
        if (!r.measuredMemory)
            continue;

        string hwRssStr = r.hasHandwritten ? format("%10d KB", r.handwrittenPeakRssKb) : "           N/A";
        string arenaStr = (r.npeggedArenaPeakBytes > 0) ? formatBytes(r.npeggedArenaPeakBytes) : "       < 1 KB";

        writefln(" %-20s | %-8s | %13d KB | %13d KB | %14s | %16s | %16s", r.name,
                formatBytes(r.inputBytes), r.peggedPeakRssKb,
                r.npeggedPeakRssKb, hwRssStr, formatBytes(r.peggedGcPeakBytes), arenaStr);
    }

    writeln("=========================================================================================================================================");
    writeln("Memory Measurement Notes:");
    writeln("  - Peak RSS: Process Resident Set Size in isolated subprocesses (ru_maxrss from wait4).");
    writeln("  - Pegged Heap Live: Garbage Collector live heap delta during single parse.");
    writeln("  - NPegged Arena: Exact byte size allocated in RAII Arena (res.arena.used), freed instantly on parse completion.");
    writeln();
}

void printJsonOutput(const BenchResult[] results, bool measureMemory) {
    writeln("{");
    writefln("  \"memoryMeasured\": %s,", measureMemory ? "true" : "false");
    writeln("  \"benchmarks\": [");
    foreach (i, ref r; results) {
        writefln("    {");
        writefln("      \"name\": \"%s\",", r.name);
        writefln("      \"inputBytes\": %d,", r.inputBytes);
        writefln("      \"iterations\": %d,", r.iterations);
        writefln("      \"peggedTimeMs\": %.4f,", r.peggedTimeMs);
        writefln("      \"npeggedTimeMs\": %.4f,", r.npeggedTimeMs);
        writefln("      \"npeggedSpeedup\": %.4f,", r.npeggedSpeedup());
        writefln("      \"hasHandwritten\": %s,", r.hasHandwritten ? "true" : "false");
        if (r.hasHandwritten) {
            writefln("      \"handwrittenTimeMs\": %.4f,", r.handwrittenTimeMs);
            writefln("      \"handwrittenSpeedup\": %.4f,", r.handwrittenSpeedup());
            writefln("      \"npeggedVsHandwritten\": %.4f,", r.npeggedVsHandwritten());
        }
        writefln("      \"peggedAllocBytes\": %d,", r.peggedAllocBytes);
        writefln("      \"npeggedAllocBytes\": %d,", r.npeggedAllocBytes);
        writefln("      \"peggedBytesPerOp\": %d,", r.peggedBytesPerOp());
        writefln("      \"npeggedBytesPerOp\": %d", r.npeggedBytesPerOp());
        if (measureMemory) {
            writefln("      ,\"peggedPeakRssKb\": %d,", r.peggedPeakRssKb);
            writefln("      \"npeggedPeakRssKb\": %d,", r.npeggedPeakRssKb);
            if (r.hasHandwritten)
                writefln("      \"handwrittenPeakRssKb\": %d,", r.handwrittenPeakRssKb);
            writefln("      \"npeggedArenaPeakBytes\": %d,", r.npeggedArenaPeakBytes);
            writefln("      \"peggedGcPeakBytes\": %d", r.peggedGcPeakBytes);
        }
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
    bool measureMemory = false;

    GetoptResult helpInfo;
    try {
        helpInfo = getopt(args, "iterations|n", "Override iteration count for all benchmarks",
                &customIterations,
                "filter|f", "Run only benchmarks whose name contains this substring",
                &filterPattern,
                "memory|m",
                "Enable peak memory measurement (subprocess RSS & allocator high-water mark)",
                &measureMemory, "json", "Output results in JSON format", &jsonOutput);
    } catch (Exception e) {
        writefln("Error: %s", e.msg);
        return 1;
    }

    if (helpInfo.helpWanted) {
        defaultGetoptPrinter("Benchmark Suite: NPegged vs Vendored Pegged vs Handwritten\n\nUsage: benchmark_runner [options]",
                helpInfo.options);
        return 0;
    }

    BenchmarkCase[] benchmarks;

    // 1. Arithmetic Expressions
    benchmarks ~= BenchmarkCase("Arithmetic.Small", "1 + 2 * (3 - 4)", 1000, (string s) {
        auto tree = PArith.Arithmetic(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) {
        auto res = NPArith.Arithmetic(ctx, s);
        assert(res.successful);
    }, (string s) {
        const ok = HWArith.ArithmeticParser.parse(s);
        if (!ok)
            assert(0);
    }, (string s) { ParseContext ctx; auto res = NPArith.Arithmetic(ctx, s); return res.arena.used; });

    benchmarks ~= BenchmarkCase("Arithmetic.Medium",
            "1 + 2 * (3 + 10 / 4) - (5 * 6 + 7) * (8 - 9 / (2 + 3))", 500, (string s) {
        auto tree = PArith.Arithmetic(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) {
        auto res = NPArith.Arithmetic(ctx, s);
        assert(res.successful);
    }, (string s) {
        const ok = HWArith.ArithmeticParser.parse(s);
        if (!ok)
            assert(0);
    }, (string s) { ParseContext ctx; auto res = NPArith.Arithmetic(ctx, s); return res.arena.used; });

    benchmarks ~= BenchmarkCase("Arithmetic.Nested",
            "(((1 + 2) * 3 - 4) / 5 + (6 * (7 - 8))) * (((9 + 10) * 11 - 12) / 13 + (14 * (15 - 16)))",
            500, (string s) { auto tree = PArith.Arithmetic(s); assert(tree.successful); },
            (string s, ref ParseContext ctx) {
        auto res = NPArith.Arithmetic(ctx, s);
        assert(res.successful);
    }, (string s) {
        const ok = HWArith.ArithmeticParser.parse(s);
        if (!ok)
            assert(0);
    }, (string s) { ParseContext ctx; auto res = NPArith.Arithmetic(ctx, s); return res.arena.used; });

    // 2. JSON Documents
    benchmarks ~= BenchmarkCase("JSON.Small",
            `{"name": "test", "id": 12345, "active": true, "score": 98.6}`, 500, (string s) {
        auto tree = PJson.JSON(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) { auto res = NPJson.JSON(ctx, s); assert(res.successful); }, (
            string s) {
        const ok = HWJson.JsonParser.parse(s);
        if (!ok)
            assert(0);
    }, (string s) { ParseContext ctx; auto res = NPJson.JSON(ctx, s); return res.arena.used; });

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
    }, (string s, ref ParseContext ctx) { auto res = NPJson.JSON(ctx, s); assert(res.successful); }, (
            string s) {
        const ok = HWJson.JsonParser.parse(s);
        if (!ok)
            assert(0);
    }, (string s) { ParseContext ctx; auto res = NPJson.JSON(ctx, s); return res.arena.used; });

    // 3. CSV Datasets
    benchmarks ~= BenchmarkCase("CSV.SingleLine", `id,first_name,last_name,email,gender,ip_address`, 1000,
            (string s) { auto tree = PCsv.CSV(s); assert(tree.successful); }, (string s, ref ParseContext ctx) {
        auto res = NPCsv.CSV(ctx, s);
        assert(res.successful);
    }, (string s) {
        const ok = HWCsv.CsvParser.parse(s);
        if (!ok)
            assert(0);
    }, (string s) { ParseContext ctx; auto res = NPCsv.CSV(ctx, s); return res.arena.used; });

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
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) { auto res = NPCsv.CSV(ctx, s); assert(res.successful); }, (string s) {
        const ok = HWCsv.CsvParser.parse(s);
        if (!ok)
            assert(0);
    }, (string s) { ParseContext ctx; auto res = NPCsv.CSV(ctx, s); return res.arena.used; });

    // 4. Numbers Literals
    benchmarks ~= BenchmarkCase("Numbers.Scientific", "123.456e+00", 1000, (string s) {
        auto tree = PNum.Numbers.Scientific(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) {
        auto res = NPNum.Numbers.Scientific(ctx, s);
        assert(res.successful);
    }, (string s) {
        const ok = HWNum.NumbersParser.parseScientific(s);
        if (!ok)
            assert(0);
    }, (string s) {
        ParseContext ctx;
        auto res = NPNum.Numbers.Scientific(ctx, s);
        return res.arena.used;
    });

    // 5. PEG Meta-Grammar Parser (Self-hosting grammars)
    enum samplePegSmall = "Calc:\n  Expr <- Term ('+' Term)*\n  Term <- [0-9]+\n";
    benchmarks ~= BenchmarkCase("PEGGrammar.Small", samplePegSmall, 300, (string s) {
        auto tree = PParser.Pegged(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) { auto res = NPParser.Pegged(ctx, s); assert(res.successful); },
            (string s) {
        const ok = HWPeg.PegParser.parse(s);
        if (!ok)
            assert(0);
    }, (string s) { ParseContext ctx; auto res = NPParser.Pegged(ctx, s); return res.arena.used; });

    enum samplePegMedium = "JSON:\n" ~ "  JSONObject < :'{' (Pair (:',' Pair)*)? :'}'\n"
        ~ "  Pair       < String :':' Value\n" ~ "  Array      < :'[' (Value (:',' Value)*)? :']'\n"
        ~ "  Value      < String / Number / JSONObject / Array / True / False / Null\n"
        ~ "  True       <- 'true'\n" ~ "  False      <- 'false'\n" ~ "  Null       <- 'null'\n";

    benchmarks ~= BenchmarkCase("PEGGrammar.Medium", samplePegMedium, 150, (string s) {
        auto tree = PParser.Pegged(s);
        assert(tree.successful);
    }, (string s, ref ParseContext ctx) { auto res = NPParser.Pegged(ctx, s); assert(res.successful); },
            (string s) {
        const ok = HWPeg.PegParser.parse(s);
        if (!ok)
            assert(0);
    }, (string s) { ParseContext ctx; auto res = NPParser.Pegged(ctx, s); return res.arena.used; });

    BenchResult[] results;
    foreach (ref bc; benchmarks) {
        if (filterPattern.length > 0 && !bc.name.canFind(filterPattern))
            continue;

        size_t iters = (customIterations > 0) ? customIterations : bc.defaultIterations;
        if (!jsonOutput) {
            writefln("Running benchmark: %-20s (%d iterations%s)...", bc.name, iters, measureMemory ? ", +memory" : "");
            stdout.flush();
        }
        results ~= executeBenchmark(bc, iters, measureMemory);
    }

    if (results.length == 0) {
        writefln("No benchmarks matched filter: '%s'", filterPattern);
        return 1;
    }

    if (jsonOutput) {
        printJsonOutput(results, measureMemory);
    } else {
        printPerformanceTable(results);
        if (measureMemory) {
            printMemoryTable(results);
        }
    }

    return 0;
}
