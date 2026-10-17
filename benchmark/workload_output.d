/** Equal-output arithmetic and CSV adapters. Input is borrowed synchronously. */
module benchmark.workload_output;

import npegged.grammar;
import npegged.records : CompactNode, RecordBuffer;
import benchmark.scalar_output : generatedScalarOutput, handwrittenScalarOutput, verifyScalarOutput;
import benchmark.workload_grammars : arithmeticGrammar, csvGrammar;
import benchmark.handwritten.arithmetic : ArithmeticLexer, Token, TokenType, ArithmeticParser;
import benchmark.handwritten.csv : CsvParser;
import benchmark.json_output : OutputMode, fingerprint;
import benchmark.measurement : Observation;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;

/// Tree kinds match selected grammar rules. Spans retain number/identifier/field leaves.
enum WorkloadKind : uint {
    root,
    term,
    factor,
    primary,
    number,
    identifier,
    field
}

uint arithmeticTreeTag(string name) @nogc nothrow pure {
    switch (name) {
    case "BenchArithmetic.Root":
        return WorkloadKind.root;
    case "BenchArithmetic.Term":
        return WorkloadKind.term;
    case "BenchArithmetic.Factor":
        return WorkloadKind.factor;
    case "BenchArithmetic.Primary":
        return WorkloadKind.primary;
    case "BenchArithmetic.Number":
        return WorkloadKind.number;
    case "BenchArithmetic.Identifier":
        return WorkloadKind.identifier;
    default:
        return uint.max;
    }
}

@nogc nothrow unittest {
    assert(arithmeticTreeTag("BenchArithmetic.Root") == WorkloadKind.root);
    assert(arithmeticTreeTag("BenchArithmetic.Number") == WorkloadKind.number);
    assert(arithmeticTreeTag("BenchArithmetic.Space") == uint.max);
}

uint arithmeticSpanTag(string name) @nogc nothrow pure {
    const tag = arithmeticTreeTag(name);
    return tag == WorkloadKind.number || tag == WorkloadKind.identifier ? tag : uint.max;
}

@nogc nothrow unittest {
    assert(arithmeticSpanTag("BenchArithmetic.Number") == WorkloadKind.number);
    assert(arithmeticSpanTag("BenchArithmetic.Identifier") == WorkloadKind.identifier);
    assert(arithmeticSpanTag("BenchArithmetic.Root") == uint.max);
}

uint csvTreeTag(string name) @nogc nothrow pure {
    return name == "BenchCSV.Root" ? WorkloadKind.root : name == "BenchCSV.Field" ? WorkloadKind
        .field : uint.max;
}

@nogc nothrow unittest {
    assert(csvTreeTag("BenchCSV.Root") == WorkloadKind.root);
    assert(csvTreeTag("BenchCSV.Field") == WorkloadKind.field);
    assert(csvTreeTag("BenchCSV.Sep") == uint.max);
}

uint csvSpanTag(string name) @nogc nothrow pure {
    return name == "BenchCSV.Field" ? WorkloadKind.field : uint.max;
}

@nogc nothrow unittest {
    assert(csvSpanTag("BenchCSV.Field") == WorkloadKind.field);
    assert(csvSpanTag("BenchCSV.Root") == uint.max);
}

private struct ArithmeticTree {
    mixin(grammar!(Memoization.selective, arithmeticTreeTag, backend)(arithmeticGrammar));
}

private struct ArithmeticSpans {
    mixin(grammar!(Memoization.selective, arithmeticSpanTag, backend)(arithmeticGrammar));
}

private struct CsvTree {
    mixin(grammar!(Memoization.selective, csvTreeTag, backend)(csvGrammar));
}

private struct CsvSpans {
    mixin(grammar!(Memoization.selective, csvSpanTag, backend)(csvGrammar));
}

/// Result owns all record memory; the writer remains local so moves retain no self pointers.
struct WorkloadOutput {
    Arena arena;
    CompactNode[] nodes;
    bool accepted;
    Status status = Status.invalidInput;
    @disable this(this);
    @disable this(ref WorkloadOutput);
}

@nogc nothrow unittest {
    static assert(!__traits(compiles, { WorkloadOutput original; auto copy = original; }));
    auto output = arithmeticOutput("1", OutputMode.tree);
    assert(output.accepted && output.nodes.length == 5 && output.arena.used > 0);
}

/// Uses the existing handwritten lexer, but emits the same concrete rule intervals.
private struct ArithmeticWriter {
    ArithmeticLexer lexer;
    Token token;
    RecordBuffer* output; // Borrowed for this parse only.
    OutputMode mode;
    size_t depth;
    Status status;

    void advance() @nogc nothrow {
        token = lexer.nextToken();
    }

    size_t position() const @nogc nothrow {
        return lexer.pos - token.text.length;
    }

    size_t open(WorkloadKind kind) @nogc nothrow {
        return output.openKind(mode == OutputMode.spans && kind < WorkloadKind.number ? uint.max
                : cast(uint)kind, position());
    }

    bool enter() @nogc nothrow {
        if (output.status != Status.ok)
            return false;
        if (depth >= 1024) {
            status = Status.resourceLimit;
            return false;
        }
        ++depth;
        return output.status == Status.ok;
    }

    bool term() @nogc nothrow {
        if (!enter())
            return false;
        scope (exit)
            --depth;
        const parent = output.parent;
        scope (exit)
            output.parent = parent;
        const index = open(WorkloadKind.term);
        if (!factor())
            return false;
        while (token.type == TokenType.plus || token.type == TokenType.minus) {
            advance();
            if (!factor())
                return false;
        }
        output.finish(index, position());
        return output.status == Status.ok;
    }

    bool factor() @nogc nothrow {
        if (!enter())
            return false;
        scope (exit)
            --depth;
        const parent = output.parent;
        scope (exit)
            output.parent = parent;
        const index = open(WorkloadKind.factor);
        if (!primary())
            return false;
        while (token.type == TokenType.star || token.type == TokenType.slash) {
            advance();
            if (!primary())
                return false;
        }
        output.finish(index, position());
        return output.status == Status.ok;
    }

    bool primary() @nogc nothrow {
        if (!enter())
            return false;
        scope (exit)
            --depth;
        const parent = output.parent;
        scope (exit)
            output.parent = parent;
        const index = open(WorkloadKind.primary);
        if (token.type == TokenType.openParen) {
            advance();
            if (!term() || token.type != TokenType.closeParen)
                return false;
            advance();
        } else if (token.type == TokenType.minus || token.type == TokenType.plus) {
            advance();
            if (!primary())
                return false;
        } else if (token.type == TokenType.number || token.type == TokenType.identifier) {
            const leafParent = output.parent;
            const leaf = open(token.type == TokenType.number ? WorkloadKind.number : WorkloadKind
                    .identifier);
            output.finish(leaf, lexer.pos);
            output.parent = leafParent;
            advance();
        } else
            return false;
        output.finish(index, position());
        return output.status == Status.ok;
    }
}

@nogc nothrow unittest {
    Arena owner;
    RecordBuffer records;
    records.arena = &owner;
    ArithmeticWriter parser;
    parser.output = &records;
    parser.mode = OutputMode.spans;
    parser.lexer = ArithmeticLexer("-x * (1+2)", 0);
    parser.advance();
    assert(parser.term() && parser.token.type == TokenType.eof && parser.depth == 0);
    assert(records.nodes.length == 3);
    parser.depth = 1024;
    assert(!parser.enter() && parser.status == Status.resourceLimit && parser.depth == 1024);
    Arena exhausted;
    exhausted.limit = 0;
    RecordBuffer empty;
    empty.arena = &exhausted;
    assert(empty.openKind(1, 0) == size_t.max);
    parser.output = &empty;
    parser.depth = 0;
    assert(!parser.enter() && parser.depth == 0);
}

WorkloadOutput arithmeticOutput(string input, OutputMode mode, size_t memoryLimit = 256 * 1024 * 1024) @nogc nothrow {
    WorkloadOutput result;
    if (mode != OutputMode.spans && mode != OutputMode.tree)
        return result;
    result.arena.limit = memoryLimit;
    RecordBuffer output;
    output.arena = &result.arena;
    const root = output.openKind(mode == OutputMode.tree ? cast(uint)WorkloadKind.root : uint.max, 0);
    ArithmeticWriter parser;
    parser.output = &output;
    parser.mode = mode;
    parser.lexer = ArithmeticLexer(input, 0);
    parser.advance();
    result.accepted = parser.term() && parser.token.type == TokenType.eof;
    result.status = parser.status != Status.ok ? parser.status : output.status != Status.ok
        ? output.status : result.accepted ? Status.ok : Status.mismatch;
    result.accepted = result.status == Status.ok;
    if (result.accepted)
        output.finish(root, input.length);
    else
        output.rollback(0);
    result.nodes = output.nodes;
    return result;
}

@nogc nothrow unittest {
    auto spans = arithmeticOutput(" 12 + x ", OutputMode.spans);
    assert(spans.accepted && spans.nodes.length == 2);
    assert(spans.nodes[0] == CompactNode(WorkloadKind.number, 1, 3, size_t.max));
    assert(spans.nodes[1] == CompactNode(WorkloadKind.identifier, 6, 7, size_t.max));
    auto tree = arithmeticOutput("1", OutputMode.tree);
    assert(tree.accepted && tree.nodes.length == 5);
    foreach (i, node; tree.nodes) {
        assert(node.begin == 0 && node.end == 1);
        assert(node.parent == (i ? i - 1 : size_t.max));
    }
    assert(!arithmeticOutput("1+", OutputMode.tree).nodes.length);
    assert(arithmeticOutput("1", OutputMode.spans, 0).status == Status.resourceLimit);
    assert(arithmeticOutput("1", OutputMode.validation).status == Status.invalidInput);
}

WorkloadOutput csvOutput(string input, OutputMode mode, size_t memoryLimit = 256 * 1024 * 1024) @nogc nothrow {
    WorkloadOutput result;
    if (mode != OutputMode.spans && mode != OutputMode.tree)
        return result;
    result.arena.limit = memoryLimit;
    RecordBuffer output;
    output.arena = &result.arena;
    const root = output.openKind(mode == OutputMode.tree ? cast(uint)WorkloadKind.root : uint.max, 0);
    size_t pos;
    bool accepted;
    while (output.status == Status.ok) {
        const field = output.openKind(WorkloadKind.field, pos);
        if (output.status != Status.ok)
            break;
        while (pos < input.length && (input[pos] == ' ' || input[pos] == '\t'))
            ++pos;
        if (pos < input.length && input[pos] == '"') {
            ++pos;
            bool closed;
            while (pos < input.length) {
                if (input[pos++] != '"')
                    continue;
                if (pos < input.length && input[pos] == '"')
                    ++pos;
                else {
                    closed = true;
                    break;
                }
            }
            if (!closed)
                break;
        } else {
            while (pos < input.length && input[pos] != ',' && input[pos] != '"' && input[pos] != ' '
                    && input[pos] != '\t' && input[pos] != '\r' && input[pos] != '\n')
                ++pos;
        }
        while (pos < input.length && (input[pos] == ' ' || input[pos] == '\t'))
            ++pos;
        output.finish(field, pos);
        output.parent = mode == OutputMode.tree ? root : size_t.max;
        if (pos == input.length) {
            accepted = true;
            break;
        }
        const delimiter = input[pos++];
        if (delimiter == '\r') {
            if (pos < input.length && input[pos] == '\n')
                ++pos;
        } else if (delimiter != ',' && delimiter != '\n')
            break;
    }
    result.status = output.status != Status.ok ? output.status : accepted ? Status.ok : Status
        .mismatch;
    result.accepted = result.status == Status.ok;
    if (result.accepted)
        output.finish(root, input.length);
    else
        output.rollback(0);
    result.nodes = output.nodes;
    return result;
}

@nogc nothrow unittest {
    auto spans = csvOutput(" a ,\n", OutputMode.spans);
    assert(spans.accepted && spans.nodes.length == 3);
    assert(spans.nodes[0] == CompactNode(WorkloadKind.field, 0, 3, size_t.max));
    assert(spans.nodes[1] == CompactNode(WorkloadKind.field, 4, 4, size_t.max));
    assert(spans.nodes[2] == CompactNode(WorkloadKind.field, 5, 5, size_t.max));
    auto empty = csvOutput("", OutputMode.tree);
    assert(empty.accepted && empty.nodes.length == 2 && empty.nodes[1].parent == 0);
    assert(!csvOutput("\"open", OutputMode.tree).nodes.length);
    assert(csvOutput("a", OutputMode.tree, 0).status == Status.resourceLimit);
    assert(csvOutput("a", OutputMode.validation).status == Status.invalidInput);
}

bool supportsWorkloadOutput(string name) @nogc nothrow pure {
    return name.length >= 11 && (name[0 .. 11] == "Arithmetic." || name[0 .. 11] == "PEGGrammar.")
        || name.length >= 4 && name[0 .. 4] == "CSV." || name.length >= 8 && name[0 .. 8] == "Numbers.";
}

@nogc nothrow unittest {
    assert(supportsWorkloadOutput("Arithmetic.Small") && supportsWorkloadOutput("CSV.Empty"));
    assert(supportsWorkloadOutput("Numbers.Binary") && supportsWorkloadOutput("PEGGrammar.Test")
            && !supportsWorkloadOutput(""));
}

CompactResult generatedWorkloadOutput(string name, string input, OutputMode mode) @nogc nothrow {
    if (mode != OutputMode.spans && mode != OutputMode.tree)
        return CompactResult.init;
    ParseContext context;
    if (name.length >= 11 && name[0 .. 11] == "Arithmetic.") {
        if (mode == OutputMode.spans)
            return parseRecords!(ArithmeticSpans.BenchArithmetic.opCall, arithmeticSpanTag, false)(context,
                    input);
        return parseRecords!(ArithmeticTree.BenchArithmetic.opCall, arithmeticTreeTag, false)(context,
                input);
    }
    if (name.length >= 4 && name[0 .. 4] == "CSV.") {
        if (mode == OutputMode.spans)
            return parseRecords!(CsvSpans.BenchCSV.opCall, csvSpanTag, false)(context, input);
        return parseRecords!(CsvTree.BenchCSV.opCall, csvTreeTag, false)(context, input);
    }
    return generatedScalarOutput(name, input, mode);
}

@nogc nothrow unittest {
    foreach (mode; [OutputMode.spans, OutputMode.tree]) {
        auto arithmetic = generatedWorkloadOutput("Arithmetic.Test", "1", mode);
        auto csv = generatedWorkloadOutput("CSV.Test", "", mode);
        assert(arithmetic.successful && csv.successful);
        assert(arithmetic.nodes.length == (mode == OutputMode.spans ? 1 : 5));
        assert(csv.nodes.length == (mode == OutputMode.spans ? 1 : 2));
        assert(arithmetic.input is null && csv.input is null);
    }
    assert(generatedWorkloadOutput("Unknown", "", OutputMode.tree).status == Status.invalidInput);
    assert(generatedWorkloadOutput("CSV.Test", "", OutputMode.validation).status == Status
            .invalidInput);
}

bool verifyWorkloadOutput(string name, string input, OutputMode mode, bool expected) @nogc nothrow {
    if (name.length >= 8 && name[0 .. 8] == "Numbers." || name.length >= 11 && name[0 .. 11] == "PEGGrammar.")
        return verifyScalarOutput(name, input, mode, expected);
    auto generated = generatedWorkloadOutput(name, input, mode);
    auto handwritten = name.length >= 11 && name[0 .. 11] == "Arithmetic." ? arithmeticOutput(input,
            mode) : csvOutput(input, mode);
    return (generated.status == Status.ok || generated.status == Status.mismatch)
        && (handwritten.status == Status.ok
                || handwritten.status == Status.mismatch)
        && generated.successful == expected && handwritten.accepted == expected && generated.nodes == handwritten
            .nodes;
}

@nogc nothrow unittest {
    foreach (mode; [OutputMode.spans, OutputMode.tree]) {
        foreach (input; ["1", "1 + 2 * (3 - 4)", "a + -+2.3", " 1 ", "", "1+", "1.", "1 2", "((1)"])
            assert(verifyWorkloadOutput("Arithmetic.Test", input, mode, ArithmeticParser.parse(input)));
        foreach (input; [
            "", "a,b", " , , ", "\"a\"\"b\",c\n", "\"line\nbreak\"", "a b", "\"open", "\"closed\"x",
            "\r\n"
        ])
            assert(verifyWorkloadOutput("CSV.Test", input, mode, CsvParser.parse(input)));
        assert(generatedWorkloadOutput("Unknown", "", mode).status == Status.invalidInput);
    }
}

Observation observeWorkloadOutput(string name, string input, OutputMode mode, bool handwritten) @nogc nothrow {
    if (!supportsWorkloadOutput(name) || (mode != OutputMode.spans && mode != OutputMode.tree)) {
        Observation invalid;
        invalid.status = Status.invalidInput;
        return invalid;
    }
    if (!handwritten) {
        auto result = generatedWorkloadOutput(name, input, mode);
        return Observation(result.successful, result.successful ? fingerprint(result.nodes) : 0,
                result.nodes.length,
                result.arena.allocationCalls + result.outputArena.allocationCalls,
                result.arena.requestedBytes + result.outputArena.requestedBytes,
                result.arena.used + result.outputArena.used,
                true, result.status == Status.mismatch ? Status.ok : result.status);
    }
    if (name.length >= 8 && name[0 .. 8] == "Numbers." || name.length >= 11 && name[0 .. 11] == "PEGGrammar.") {
        auto result = handwrittenScalarOutput(name, input, mode);
        return Observation(result.successful, result.successful ? fingerprint(result.nodes) : 0,
                result.nodes.length, result.outputArena.allocationCalls,
                result.outputArena.requestedBytes,
                result.outputArena.used, true, result.status == Status.mismatch ? Status.ok : result
                    .status);
    }
    auto result = name.length >= 11 && name[0 .. 11] == "Arithmetic." ? arithmeticOutput(input,
            mode) : csvOutput(input, mode);
    return Observation(result.accepted, result.accepted ? fingerprint(result.nodes) : 0,
            result.nodes.length, result.arena.allocationCalls, result.arena.requestedBytes,
            result.arena.used, true, result.status == Status.mismatch ? Status.ok : result.status);
}

@nogc nothrow unittest {
    foreach (mode; [OutputMode.spans, OutputMode.tree])
        foreach (name; ["Arithmetic.Test", "CSV.Test"]) {
            auto generated = observeWorkloadOutput(name, "1", mode, false);
            auto handwritten = observeWorkloadOutput(name, "1", mode, true);
            assert(generated.accepted && handwritten.accepted && generated.outputHash == handwritten
                    .outputHash);
            assert(generated.outputNodes == handwritten.outputNodes && generated.allocatorMeasured);
        }
}

// Exhaustive short-input output comparison exercises rejection rollback and
// empty/quoted CSV fields as well as arithmetic precedence and unary nesting.
@nogc nothrow unittest {
    char[4] bytes;
    foreach (csv; [false, true]) {
        const alphabet = csv ? "a,\" \n" : "1+a()";
        size_t combinations = 1;
        foreach (length; 0 .. bytes.length + 1) {
            foreach (encoded; 0 .. combinations) {
                size_t value = encoded;
                foreach (ref c; bytes[0 .. length]) {
                    c = alphabet[value % alphabet.length];
                    value /= alphabet.length;
                }
                const input = cast(string)bytes[0 .. length];
                const expected = csv ? CsvParser.parse(input) : ArithmeticParser.parse(input);
                foreach (mode; [OutputMode.spans, OutputMode.tree])
                    assert(verifyWorkloadOutput(csv ? "CSV.Test" : "Arithmetic.Test", input, mode, expected));
            }
            combinations *= alphabet.length;
        }
    }
}
