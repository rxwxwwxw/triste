/** Equal-output numeric tokens and PEG syntax trees; input spans are borrowed. */
module benchmark.scalar_output;
import npegged.grammar;
import npegged.records : RecordBuffer;
import benchmark.workload_grammars : numbersGrammar, pegGrammar;
import benchmark.handwritten.numbers : NumbersParser;
import benchmark.handwritten.peg : PegKind, parsePegTree;
import benchmark.json_output : OutputMode;
import benchmark.measurement : Observation;
import benchmark.json_output : fingerprint;

version (NPeggedLL1)
    private enum backend = ParserBackend.ll1;
else version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;

uint numberTag(string name) @nogc nothrow pure {
    return name == "BenchNumbers.Scientific" ? 200 : name == "BenchNumbers.Hexa"
        ? 201 : name == "BenchNumbers.Binary" ? 202 : uint.max;
}

@nogc nothrow pure unittest {
    assert(numberTag("BenchNumbers.Scientific") == 200);
    assert(numberTag("BenchNumbers.Hexa") == 201 && numberTag("BenchNumbers.Binary") == 202);
    assert(numberTag("") == uint.max);
}

uint pegTag(string name) @nogc nothrow pure {
    switch (name) {
    case "BenchPEG.Root":
        return PegKind.root;
    case "BenchPEG.Definition":
        return PegKind.definition;
    case "BenchPEG.TopExpression":
    case "BenchPEG.Expression":
        return PegKind.expression;
    case "BenchPEG.TopSequence":
    case "BenchPEG.Sequence":
        return PegKind.sequence;
    case "BenchPEG.Prefix":
        return PegKind.prefix;
    case "BenchPEG.Primary":
        return PegKind.primary;
    default:
        return uint.max;
    }
}

@nogc nothrow pure unittest {
    assert(pegTag("BenchPEG.Root") == PegKind.root && pegTag("BenchPEG.Expression") == PegKind
            .expression);
    assert(pegTag("BenchPEG.Sp") == uint.max);
}

uint pegSpanTag(string name) @nogc nothrow pure {
    return name == "BenchPEG.Primary" ? cast(uint)PegKind.primary : uint.max;
}

@nogc nothrow pure unittest {
    assert(pegSpanTag("BenchPEG.Primary") == PegKind.primary && pegSpanTag("BenchPEG.Root") == uint
            .max);
}

private struct NumbersTree {
    mixin(grammar!(Memoization.selective, numberTag, backend)(numbersGrammar));
}

private struct PegTree {
    mixin(grammar!(Memoization.selective, pegTag, backend)(pegGrammar));
}

private struct PegSpans {
    mixin(grammar!(Memoization.selective, pegSpanTag, backend)(pegGrammar));
}

CompactResult generatedScalarOutput(string name, string input, OutputMode mode) @nogc nothrow {
    ParseContext context;
    if (mode != OutputMode.tree && mode != OutputMode.spans)
        return CompactResult.init;
    if (name.length >= 11 && name[0 .. 11] == "PEGGrammar.") {
        if (mode == OutputMode.spans)
            return parseRecords!(PegSpans.BenchPEG.opCall, pegSpanTag, false)(context, input);
        return parseRecords!(PegTree.BenchPEG.opCall, pegTag, false)(context, input);
    }
    if (name.length >= 12 && name[0 .. 12] == "Numbers.Hexa")
        return parseRecords!(NumbersTree.BenchNumbers.Hexa, numberTag, false)(context, input);
    if (name.length >= 14 && name[0 .. 14] == "Numbers.Binary")
        return parseRecords!(NumbersTree.BenchNumbers.Binary, numberTag, false)(context, input);
    if (name.length >= 18 && name[0 .. 18] == "Numbers.Scientific")
        return parseRecords!(NumbersTree.BenchNumbers.Scientific, numberTag, false)(context, input);
    return CompactResult.init;
}

@nogc nothrow unittest {
    ParseContext context;
    auto tree = generatedScalarOutput("PEGGrammar.Test", "G: A <- ('a' / B)+", OutputMode.tree);
    assert(tree.successful && tree.nodes.length > 6);
    assert(generatedScalarOutput("Numbers.Binary", "0b10", OutputMode.tree).nodes.length == 1);
    assert(generatedScalarOutput("unknown", "", OutputMode.tree).status == Status.invalidInput);
}

CompactResult handwrittenScalarOutput(string name, string input, OutputMode mode, size_t limit = 256 * 1024 * 1024) @nogc nothrow {
    CompactResult result;
    if (mode != OutputMode.tree && mode != OutputMode.spans)
        return result;
    if (name.length >= 11 && name[0 .. 11] == "PEGGrammar.") {
        auto parsed = parsePegTree(input, mode == OutputMode.spans, limit);
        // Transfer arena ownership without copying it or retaining builder pointers.
        import core.lifetime : move;

        move(parsed.arena, result.outputArena);
        result.nodes = parsed.nodes;
        result.successful = parsed.accepted;
        result.status = parsed.status;
        result.end = parsed.accepted ? input.length : 0;
        return result;
    }
    uint kind;
    bool accepted;
    if (name.length >= 12 && name[0 .. 12] == "Numbers.Hexa") {
        kind = 201;
        accepted = NumbersParser.parseHexa(input);
    } else if (name.length >= 14 && name[0 .. 14] == "Numbers.Binary") {
        kind = 202;
        accepted = NumbersParser.parseBinary(input);
    } else if (name.length >= 18 && name[0 .. 18] == "Numbers.Scientific") {
        kind = 200;
        accepted = NumbersParser.parseScientific(input);
    } else
        return result;
    result.outputArena.limit = limit;
    RecordBuffer output;
    output.arena = &result.outputArena;
    if (accepted)
        output.put(CompactNode(kind, 0, input.length));
    result.status = output.status != Status.ok ? output.status : accepted ? Status.ok : Status
        .mismatch;
    result.successful = result.status == Status.ok;
    result.end = result.successful ? input.length : 0;
    if (result.successful)
        result.nodes = output.nodes;
    return result;
}

@nogc nothrow unittest {
    assert(handwrittenScalarOutput("Numbers.Scientific", "12.3e+1", OutputMode.tree).nodes.length == 1);
    assert(handwrittenScalarOutput("Numbers.Hexa", "ff", OutputMode.tree, 0).status == Status
            .resourceLimit);
    assert(!handwrittenScalarOutput("PEGGrammar.Test", "G: A <- (", OutputMode.tree).nodes.length);
}

bool verifyScalarOutput(string name, string input, OutputMode mode, bool accepted) @nogc nothrow {
    auto a = generatedScalarOutput(name, input, mode);
    auto b = handwrittenScalarOutput(name, input, mode);
    return a.successful == accepted && b.successful == accepted && (a.status == Status.ok
            || a.status == Status.mismatch) && (b.status == Status.ok || b.status == Status.mismatch) && a
        .nodes == b.nodes;
}

@nogc nothrow unittest {
    foreach (mode; [OutputMode.tree, OutputMode.spans]) {
        foreach (input; [
            "G: A <- 'a'", "G: A <- ('a' / B)+", "G: A <-- / []**", "G: A <- x\nB <- 'b'", "",
            "G: A <- ("
        ])
            assert(verifyScalarOutput("PEGGrammar.Test", input, mode, input.length && input != "G: A <- ("));
        assert(verifyScalarOutput("Numbers.Binary", "0b10", mode, true));
    }
}

@nogc nothrow unittest {
    import benchmark.handwritten.peg : PegParser;

    static immutable parts = [
        "x", "'a'", "[]", "(", ")", "/", "|", "!", "*", "{a}", "B <-", "B(p) <-", "B(\"(\") <-",
        "x.y", "x(a)", "# c\n", " "
    ];
    char[128] storage;
    foreach (a; parts)
        foreach (b; parts)
            foreach (c; parts) {
                size_t length;
                foreach (part; ["G: A <- ", a, " ", b, " ", c]) {
                    storage[length .. length + part.length] = part[];
                    length += part.length;
                }
                auto input = cast(string)storage[0 .. length];
                foreach (mode; [OutputMode.tree, OutputMode.spans])
                    assert(verifyScalarOutput("PEGGrammar.Test", input, mode, PegParser.parse(input)));
            }
    foreach (input; ["", "1", "-12.3e+4", "1e", "0b101_", "0b", "ff", "xyz"]) {
        assert(verifyScalarOutput("Numbers.Scientific", input, OutputMode.tree, NumbersParser
                .parseScientific(input)));
        assert(verifyScalarOutput("Numbers.Hexa", input, OutputMode.tree, NumbersParser.parseHexa(input)));
        assert(verifyScalarOutput("Numbers.Binary", input, OutputMode.tree, NumbersParser.parseBinary(
                input)));
    }
}
