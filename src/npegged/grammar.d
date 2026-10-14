/** Grammar frontend derived from Pegged's extended PEG syntax (Boost 1.0).
    Runtime code generation is a cold path using selective druntime GC. */
module npegged.grammar;
public import npegged.peg;
import npegged.io;

nothrow:

struct Diagnostic {
    size_t offset;
    string message;
}

enum Memoization {
    no,
    yes
}

private string number(size_t value) pure nothrow {
    char[32] digits;
    size_t start = digits.length;
    do {
        digits[--start] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value);
    return digits[start .. $].idup;
}

unittest {
    assert(number(0) == "0");
    assert(number(123) == "123");
}

private string quoted(string text) pure nothrow {
    string result = "\"";
    foreach (c; text) {
        switch (c) {
        case '\\':
            result ~= "\\\\";
            break;
        case '"':
            result ~= "\\\"";
            break;
        case '\n':
            result ~= "\\n";
            break;
        case '\r':
            result ~= "\\r";
            break;
        case '\t':
            result ~= "\\t";
            break;
        case '\0':
            result ~= "\\0";
            break;
        default:
            if (cast(ubyte)c < 32 || cast(ubyte)c >= 127) {
                enum hex = "0123456789ABCDEF";
                result ~= "\\x" ~ hex[(cast(ubyte)c) >> 4] ~ hex[(cast(ubyte)c) & 15];
            } else
                result ~= c;
            break;
        }
    }
    return result ~ "\"";
}

unittest {
    assert(quoted("a\n\"\\") == "\"a\\n\\\"\\\\\"");
}

/// Cold grammar frontend. Runtime generation selectively uses druntime GC; emitted parsers never do.
private struct Frontend {
    string input;
    size_t pos;
    Diagnostic error;
    bool spaced;
    struct Rule {
        string name, params, body;
    }

    Rule[] rules;
    string name, params;
    bool memoize = true;
    void skip() nothrow {
        while (pos < input.length) {
            if (input[pos] == ' ' || input[pos] == '\t' || input[pos] == '\n' || input[pos] == '\r')
                ++pos;
            else if (input[pos] == '#') {
                while (pos < input.length && input[pos] != '\n')
                    ++pos;
            } else
                break;
        }
    }

    bool accept(char c) nothrow {
        skip();
        if (pos < input.length && input[pos] == c) {
            ++pos;
            return true;
        }
        return false;
    }

    void require(char c) nothrow {
        if (!accept(c))
            problem("Expected '" ~ c ~ "'");
    }

    void problem(string message) nothrow {
        if (!error.message.length)
            error = Diagnostic(pos, message);
    }

    string ident() nothrow {
        skip();
        size_t start = pos;
        if (pos >= input.length || !isInitial(input[pos]))
            return null;
        ++pos;
        while (pos < input.length && (isInitial(input[pos]) || (input[pos] >= '0' && input[pos] <= '9')))
            ++pos;
        return input[start .. pos];
    }

    static bool isInitial(char c) @nogc nothrow pure {
        return c == '_' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z';
    }

    string parameters() nothrow {
        if (!accept('('))
            return null;
        string result = "(";
        do {
            auto id = ident();
            if (!id.length) {
                problem("Expected parameter name");
                break;
            }
            result ~= "alias " ~ id;
            if (accept('='))
                result ~= " = " ~ expression();
            if (!accept(','))
                break;
            result ~= ", ";
        }
        while (!error.message.length);
        require(')');
        return result ~ ")";
    }

    bool definitionAhead() nothrow {
        size_t saved = pos;
        auto id = ident();
        if (!id.length) {
            pos = saved;
            return false;
        }
        if (accept('(')) {
            size_t depth = 1;
            while (pos < input.length && depth) {
                auto c = input[pos++];
                if (c == '\'' || c == '"') {
                    auto delimiter = c;
                    while (pos < input.length && input[pos] != delimiter) {
                        if (input[pos++] == '\\' && pos < input.length)
                            ++pos;
                    }
                    if (pos < input.length)
                        ++pos;
                    continue;
                }
                if (c == '(')
                    ++depth;
                if (c == ')')
                    --depth;
            }
        }
        skip();
        bool result = pos < input.length && input[pos] == '<';
        pos = saved;
        return result;
    }

    string expression() nothrow {
        skip();
        char kind = 0;
        if (pos < input.length && (input[pos] == '/' || input[pos] == '|'))
            kind = input[pos++];
        string[] choices;
        choices ~= sequence();
        while (!error.message.length) {
            skip();
            if (pos >= input.length || (input[pos] != '/' && input[pos] != '|'))
                break;
            char next = input[pos++];
            if (kind && kind != next) {
                problem("Cannot mix / and | in one expression");
                break;
            }
            kind = next;
            choices ~= sequence();
        }
        if (choices.length == 1)
            return choices[0];
        string result = kind == '|' ? "longest_match!(" : "or!(";
        foreach (i, choice; choices)
            result ~= (i ? ", " : "") ~ choice;
        return result ~ ")";
    }

    string sequence() nothrow {
        string[] pieces;
        while (!error.message.length) {
            skip();
            if (pos >= input.length || input[pos] == ')' || input[pos] == ',' || input[pos] == '/'
                    || input[pos] == '|' || definitionAhead())
                break;
            auto before = pos;
            auto piece = prefix();
            if (pos == before) {
                problem("Expected parsing expression");
                break;
            }
            pieces ~= piece;
        }
        if (!pieces.length) {
            problem("Empty sequence");
            return "eps";
        }
        if (pieces.length == 1)
            return pieces[0];
        string result = "and!(";
        foreach (i, piece; pieces)
            result ~= (i ? ", " : "") ~ piece;
        return result ~ ")";
    }

    string prefix() nothrow {
        skip();
        string operators;
        while (pos < input.length && isPrefix(input[pos])) {
            operators ~= input[pos++];
            skip();
        }
        auto result = primary();
        while (!error.message.length) {
            if (accept('?'))
                result = "option!(" ~ result ~ ")";
            else if (accept('*'))
                result = "zeroOrMore!(" ~ result ~ ")";
            else if (accept('+'))
                result = "oneOrMore!(" ~ result ~ ")";
            else if (accept('{'))
                result = actions(result);
            else
                break;
        }
        foreach (c; operators)
            result = operation(c) ~ "!(" ~ result ~ ")";
        return result;
    }

    static bool isPrefix(char c) @nogc nothrow pure {
        return c == '&' || c == '!' || c == '~' || c == ':' || c == '^' || c == ';' || c == '%';
    }

    static string operation(char c) @nogc nothrow pure {
        switch (c) {
        case '&':
            return "posLookahead";
        case '!':
            return "negLookahead";
        case '~':
            return "fuse";
        case ':':
            return "discard";
        case '^':
            return "keep";
        case ';':
            return "drop";
        case '%':
            return "propagate";
        default:
            assert(false);
        }
    }

    string primary() nothrow {
        skip();
        string result;
        if (accept('(')) {
            result = expression();
            require(')');
        } else if (accept('.'))
            result = "any";
        else if (accept('[')) {
            string[] ranges;
            while (pos < input.length && input[pos] != ']' && !error.message.length) {
                bool byteEscape = input[pos] == '\\' && pos + 1 < input.length
                    && (input[pos + 1] == 'x' || input[pos + 1] >= '0' && input[pos + 1] <= '7');
                auto first = character();
                if (pos < input.length && input[pos] == '-' && pos + 1 < input.length && input[pos + 1] != ']') {
                    ++pos;
                    auto last = character();
                    ranges ~= "charRange!(" ~ number(first) ~ ", " ~ number(last) ~ ")";
                } else if (byteEscape)
                    ranges ~= "literal!(" ~ quoted([cast(char)first].idup) ~ ")";
                else
                    ranges ~= "charRange!(" ~ number(first) ~ ", " ~ number(first) ~ ")";
            }
            require(']');
            result = ranges.length ? "or!(" : "fail";
            foreach (i, range; ranges)
                result ~= (i ? ", " : "") ~ range;
            if (ranges.length)
                result ~= ")";
        } else if (pos < input.length && (input[pos] == '\'' || input[pos] == '"')) {
            auto delimiter = input[pos++];
            string text;
            while (pos < input.length && input[pos] != delimiter && !error.message.length) {
                bool byteEscape = input[pos] == '\\' && pos + 1 < input.length
                    && (input[pos + 1] == 'x' || input[pos + 1] >= '0' && input[pos + 1] <= '7');
                auto scalar = character(true);
                text ~= byteEscape ? [cast(char)scalar].idup : encode(scalar);
            }
            if (pos == input.length)
                problem("Unterminated literal");
            else
                ++pos;
            bool insensitive = pos < input.length && input[pos] == 'i';
            if (insensitive)
                ++pos;
            result = (insensitive ? "caseInsensitiveLiteral!(" : "literal!(") ~ quoted(text) ~ ")";
        } else {
            result = ident();
            if (!result.length) {
                problem("Expected literal, range, group, or rule name");
                return "fail";
            }
            while (!error.message.length) {
                size_t beforeArguments = pos;
                if (pos < input.length && input[pos] == '(') {
                    ++pos;
                    result ~= "!(";
                    size_t count;
                    do {
                        result ~= (count++ ? ", " : "") ~ expression();
                    }
                    while (accept(','));
                    require(')');
                    result ~= ")";
                } else {
                    pos = beforeArguments;
                    // Qualified rule names cannot have whitespace around the dot.
                    size_t saved = pos;
                    if (pos + 1 < input.length && input[pos] == '.' && isInitial(input[pos + 1])) {
                        ++pos;
                        auto id = ident();
                        result ~= "." ~ id;
                    } else {
                        pos = saved;
                        break;
                    }
                }
            }
        }
        if (spaced)
            result = "wrapAround!(Spacing, " ~ result ~ ", Spacing)";
        return result;
    }

    dchar character(bool literalMode = false) nothrow {
        if (pos == input.length) {
            problem("Expected character");
            return 0;
        }
        if (input[pos] != '\\') {
            dchar value;
            if (!decode(input, pos, value))
                problem("Invalid UTF-8");
            return value;
        }
        ++pos;
        if (pos == input.length) {
            problem("Incomplete escape");
            return 0;
        }
        auto c = input[pos++];
        switch (c) {
        case 'n':
            return '\n';
        case 'r':
            return '\r';
        case 't':
            return '\t';
        case 'b':
            return '\b';
        case 'f':
            return '\f';
        case 'v':
            return '\v';
        case 'x':
        case 'u':
        case 'U': {
                uint value;
                uint count = c == 'x' ? 2 : c == 'u' ? 4 : 8;
                foreach (i; 0 .. count) {
                    if (pos == input.length) {
                        problem("Incomplete hex escape");
                        return 0;
                    }
                    auto digit = input[pos++];
                    uint n = digit >= '0' && digit <= '9' ? digit - '0' : digit >= 'a' && digit <= 'f'
                        ? digit - 'a' + 10 : digit >= 'A' && digit <= 'F' ? digit - 'A' + 10 : 16;
                    if (n == 16) {
                        problem("Invalid hex escape");
                        return 0;
                    }
                    value = value * 16 + n;
                }
                if (value > 0x10FFFF || value >= 0xD800 && value <= 0xDFFF)
                    problem("Invalid Unicode scalar");
                return cast(dchar)value;
            }
        default:
            if (c >= '0' && c <= '7') {
                uint value = c - '0';
                foreach (i; 0 .. (literalMode || c <= '2' ? 2 : 1)) {
                    if (pos == input.length || input[pos] < '0' || input[pos] > '7')
                        break;
                    value = value * 8 + input[pos++] - '0';
                }
                return cast(dchar)value;
            }
            return c;
        }
    }

    string actions(string result) nothrow {
        size_t start = pos, depth;
        char quote = 0;
        bool escaped;
        while (pos < input.length) {
            char c = input[pos++];
            if (!quote && c == '/' && pos < input.length) {
                if (input[pos] == '/') {
                    while (pos < input.length && input[pos] != '\n')
                        ++pos;
                    continue;
                }
                if (input[pos] == '*') {
                    ++pos;
                    while (pos + 1 < input.length && !(input[pos] == '*' && input[pos + 1] == '/'))
                        ++pos;
                    if (pos + 1 == input.length) {
                        problem("Unterminated action comment");
                        return result;
                    }
                    pos += 2;
                    continue;
                }
                if (input[pos] == '+') {
                    ++pos;
                    size_t nesting = 1;
                    while (pos + 1 < input.length && nesting) {
                        if (input[pos] == '/' && input[pos + 1] == '+') {
                            ++nesting;
                            pos += 2;
                        } else if (input[pos] == '+' && input[pos + 1] == '/') {
                            --nesting;
                            pos += 2;
                        } else
                            ++pos;
                    }
                    if (nesting) {
                        problem("Unterminated nested action comment");
                        return result;
                    }
                    continue;
                }
            }
            if (quote) {
                if (escaped)
                    escaped = false;
                else if (c == '\\' && quote != '`')
                    escaped = true;
                else if (c == quote)
                    quote = 0;
                continue;
            }
            if (c == '\'' || c == '"' || c == '`') {
                quote = c;
                continue;
            }
            if (c == '(' || c == '[' || c == '{')
                ++depth;
            else if ((c == ')' || c == ']' || c == '}') && depth)
                --depth;
            else if (!depth && (c == ',' || c == '}')) {
                auto expression = input[start .. pos - 1];
                result = "action!(" ~ result ~ ", " ~ expression ~ ")";
                if (c == '}')
                    return result;
                start = pos;
            }
        }
        problem("Unterminated semantic action");
        return result;
    }

    void read() nothrow {
        name = ident();
        params = parameters();
        require(':');
        if (!name.length)
            problem("Expected grammar name");
        while (!error.message.length) {
            skip();
            if (pos == input.length)
                break;
            auto ruleName = ident();
            auto ruleParams = parameters();
            require('<');
            char arrow = 0;
            string arrowActions;
            if (pos < input.length) {
                if (input[pos] == '-')
                    ++pos;
                else if (isPrefix(input[pos]) && input[pos] != '!' && input[pos] != '&')
                    arrow = input[pos++];
                else if (input[pos] == '{') {
                    ++pos;
                    arrowActions = actions("__BODY__");
                } else
                    arrow = ' ';
            }
            spaced = arrow == ' ';
            auto body = expression();
            spaced = false;
            if (arrow && arrow != ' ')
                body = operation(arrow) ~ "!(" ~ body ~ ")";
            if (arrowActions.length) {
                string replaced;
                for (size_t i; i < arrowActions.length;) {
                    if (i + 8 <= arrowActions.length && arrowActions[i .. i + 8] == "__BODY__") {
                        replaced ~= body;
                        i += 8;
                    } else
                        replaced ~= arrowActions[i++];
                }
                body = replaced;
            }
            rules ~= Rule(ruleName, ruleParams, body);
        }
        if (!rules.length)
            problem("Grammar needs at least one rule");
    }

    string emit() nothrow {
        string result = "struct " ~ name ~ params ~ " {\n";
        bool spacingDefined;
        foreach (rule; rules)
            if (rule.name == "Spacing")
                spacingDefined = true;
        if (!spacingDefined)
            result ~= "alias Spacing = npegged.peg.spacing;\n";
        foreach (rule; rules) {
            if (rule.params.length)
                result ~= "template " ~ rule.name ~ rule.params ~ " {\n";
            string r = rule.name;
            string entryName = rule.params.length ? "_entry" : r;
            result ~= "private static ParseTree _" ~ r
                ~ "(bool CT)(ref State!CT s, size_t p) nothrow { return defined!("
                ~ rule.body ~ ", " ~ quoted(name ~ "." ~ r) ~ ")(s,p); }\n";
            // Concrete overloads break recursive attribute-inference cycles.
            foreach (mode; ["false", "true"]) {
                auto attributes = mode == "false" ? " @nogc nothrow" : " nothrow";
                result ~= "static ParseTree " ~ entryName ~ (mode == "true"
                        ? "(CompileTime = void)" : "") ~ "(ref State!" ~ mode
                    ~ " s, size_t p)" ~ attributes ~ " { return s.rule!(_" ~ r ~ "!" ~ mode ~ ", "
                    ~ quoted(name ~ "." ~ r) ~ ", " ~ (memoize ? "true" : "false") ~ ")(p); }\n";
            }
            result ~= "static ParseResult " ~ entryName ~ "(Context)(ref Context ctx, string input) @nogc nothrow if (is(Context == ParseContext)) { return parse!(" ~ entryName ~ ")(ctx,input); }\n";
            result ~= "static ParseTree " ~ entryName
                ~ "(Input)(Input input) nothrow if (is(Input == string)) { return parseCT!("
                ~ entryName ~ ")(input); }\n";
            if (rule.params.length)
                result ~= "alias " ~ r ~ " = _entry;\n}\n";
        }
        if (!rules[0].params.length) {
            auto first = rules[0].name;
            foreach (mode; ["false", "true"]) {
                result ~= "static ParseTree opCall" ~ (mode == "true"
                        ? "(CompileTime = void)" : "") ~ "(ref State!" ~ mode ~ " s, size_t p)" ~ (
                        mode == "false" ? " @nogc" : "") ~ " nothrow { auto t = " ~ first
                    ~ "(s,p); t.name = " ~ quoted(name) ~ "; return t; }\n";
            }
            result ~= "static ParseResult opCall(Context)(ref Context ctx, string input) @nogc nothrow if (is(Context == ParseContext)) { return parse!(opCall)(ctx,input); }\n";
            result ~= "static ParseTree opCall(Input)(Input input) nothrow if (is(Input == string)) { return parseCT!(opCall)(input); }\n";
        }
        result ~= "}\n";
        return result;
    }
}

unittest {
    foreach (definition; [
        "Test(Token = 'x'): A <- List(Token, ',') List(T, S = ',') < T (:S T)*",
        "Test: A <~ '\\u00E9' / '\\U0001F600' / '\\x80' / '\\377'",
        "Test: A <- [a-zé-ê] | 'ABC'i",
        "Test: A <: 'x' B <^ 'y' C <; 'z' D <% A E <{act} 'a'",
        "Test: A <- 'x'{ p => { /* }, */ return p; }, p => p }",
        "Test: A <- 'x'{ p => { /+ }, /+ nested +/ +/ return p; } }",
        "Test: A <- 'x'{ p => { // },\n return p; } }", "Test: A <- ^'x' %B :eoi B <- 'x'",
        "Test: A <- &'a' !'b' ~'c'? :'d'* ;'e'+ %'f' ^'g'",
        "Test: A <- Other.Rule('x') Other2.Thing",
        "Test: A <- 'x' B(X = '(') <- X", "Test: A <- '' / []",
    ]) {
        Frontend parser;
        parser.input = definition;
        parser.read();
        assert(!parser.error.message.length, parser.error.message);
        assert(parser.emit().length);
    }
    foreach (definition; [
        "", "Test:", "Test: A <-", "Test: A <- (", "Test: A <- 'x", "Test: A <- '\\'",
        "Test: A <- '\\uX000'", "Test: A <- '\\UFFFFFFFF'", "Test: A <- '\\u12'",
        "Test: A <- 'a' / 'b' | 'c'", "Test: A <- 'x'{ act", "Test: A(,) <- 'x'",
        "Test: A <- '\xff'", "Test: A <- 'x'{p => { /*", "Test: A <- 'x'{p => { /+"
    ]) {
        Frontend parser;
        parser.input = definition;
        parser.read();
        assert(parser.error.message.length);
    }
    assert(quoted("\0\r\t\x01\x80") == "\"\\0\\r\\t\\x01\\x80\"");
}

nothrow unittest {
    foreach (definition; [
        "Test:\r\t A <- 'a' # trailing comment", "Test: A <- / 'a' / 'b'",
        "Test: A <- | 'a' | 'b'", "Test: A <- [-a-]",
        "Test: A <- '\\b\\f\\v\\uFaBc\\xAf\\0\\07\\078'",
        "Test: A <- 'x'{p => foo('x', [1, 2], `raw`)}", "Test: A <- 'x'{p => p / 2}",
    ])
        assert(generate(definition).status == Status.ok);
    foreach (definition; [
        "Test: A <- @", "Test: A <- [a-", "Test: A <- '\\uD800'", "Test: A <- '\\u12",
        "Test: A <- '\\x", "Test: A <- '\\", "Test: A <- 'x'{p /", "Test: A(X='\\'",
        "Test: A <- 'x'{ // trailing"
    ])
        assert(generate(definition).status == Status.invalidInput);
    auto cached = grammar("Test: A <- 'a'");
    assert(cached.length);
    auto invalid = grammar("Test:");
    assert(invalid.length);
    auto uncached = generate!(Memoization.no)("Test: A <- 'a'");
    assert(uncached.status == Status.ok);
}

private string encode(dchar value) pure nothrow {
    if (value < 0x80)
        return [cast(char)value].idup;
    if (value < 0x800)
        return [cast(char)(0xC0 | value >> 6), cast(char)(0x80 | value & 0x3F)].idup;
    if (value < 0x10000)
        return [
        cast(char)(0xE0 | value >> 12), cast(char)(0x80 | value >> 6 & 0x3F),
        cast(char)(0x80 | value & 0x3F)
    ].idup;
    return [
        cast(char)(0xF0 | value >> 18), cast(char)(0x80 | value >> 12 & 0x3F),
        cast(char)(0x80 | value >> 6 & 0x3F), cast(char)(0x80 | value & 0x3F)
    ].idup;
}

unittest {
    assert(encode('a') == "a");
    assert(encode('é') == "é");
    assert(encode('€') == "€");
    assert(encode('😀') == "😀");
}

/// Returns D source for mixin() or cold runtime generation. Grammar errors become static diagnostics.
string grammar(Memoization memo = Memoization.yes)(string definition) nothrow {
    Frontend frontend;
    frontend.input = definition;
    frontend.memoize = memo == Memoization.yes;
    frontend.read();
    if (frontend.error.message.length)
        return "static assert(false, " ~ quoted(
                frontend.error.message ~ " at byte " ~ number(frontend.error.offset)) ~ ");";
    return frontend.emit();
}

unittest {
    enum generated = grammar("Tiny: A <- 'x'+ eoi");
    static assert(generated.length > 0);
    mixin(generated);
    enum result = Tiny("xxx");
    static assert(result.successful && result.matches == ["x", "x", "x"]);
    enum invalid = grammar("Broken: A <- (");
    static assert(invalid.length > 0);
}

version (unittest) mixin(grammar(`
RuntimeTest:
    Expr <- Expr '+' Number / Number
    Number <~ [0-9]+
`));

@nogc nothrow unittest {
    ParseContext ctx;
    auto result = RuntimeTest(ctx, "1+2+3");
    assert(result.successful && result.end == 5);
    assert(result.matches == ["1", "+", "2", "+", "3"]);
    assert(result.children[0].name == "RuntimeTest.Expr");
    auto bad = RuntimeTest(ctx, "x");
    assert(!bad.successful);
    ctx.depthLimit = 0;
    auto limited = RuntimeTest(ctx, "1");
    assert(limited.status == Status.resourceLimit);
}

@nogc nothrow unittest {
    foreach (budget; 0 .. 80) {
        ParseContext context;
        context.memoryLimit = budget * 128;
        auto memory = RuntimeTest(context, "1+2+3+4");
        assert(memory.status == Status.ok || memory.status == Status.resourceLimit);
        context = ParseContext.init;
        context.stepLimit = budget;
        auto work = RuntimeTest(context, "1+2+3+4");
        assert(work.status == Status.ok || work.status == Status.resourceLimit);
    }
}

/// Cold runtime generation reports errors explicitly. Output uses selective druntime GC.
struct GenerationResult {
    Status status = Status.invalidInput;
    string source;
    Diagnostic diagnostic;
}

GenerationResult generate(Memoization memo = Memoization.yes)(string definition, string moduleName = "") nothrow {
    Frontend frontend;
    frontend.input = definition;
    frontend.memoize = memo == Memoization.yes;
    frontend.read();
    if (frontend.error.message.length)
        return GenerationResult(Status.invalidInput, null, frontend.error);
    auto source = frontend.emit();
    if (moduleName.length)
        source = "module " ~ moduleName ~ ";\npublic import npegged.peg;\n" ~ source;
    return GenerationResult(Status.ok, source);
}

unittest {
    auto result = generate("Test: A <- 'a'", "test_generated");
    assert(result.status == Status.ok && result.source.length);
    auto invalid = generate("Test: A <- (");
    assert(invalid.status == Status.invalidInput);
}

Status asModule(Memoization memo = Memoization.yes)(string moduleName, string fileName,
        string definition, string header = "") nothrow {
    import npegged.io : File;

    auto result = generate!(memo)(definition);
    if (result.status != Status.ok)
        return result.status;
    auto file = File.open(fileName ~ ".d", true);
    if (file.write("// Generated from Pegged-derived npegged grammar. Boost 1.0.\n") != Status.ok)
        return Status.ioError;
    if (file.write("module " ~ moduleName ~ ";\npublic import npegged.peg;\n") != Status.ok)
        return Status.ioError;
    if (header.length && file.write(header ~ "\n") != Status.ok)
        return Status.ioError;
    return file.write(result.source);
}

unittest {
    assert(asModule("test", "/nonexistent/npegged", "Test: A <- 'a'") == Status.ioError);
    assert(asModule("test", "build/invalid", "Test:") == Status.invalidInput);
    assert(asModule("test", "build/roundtrip", "Test: A <- 'a'", "// custom header") == Status.ok);
}

/// Generate from a successful grammar parse while its owning result remains alive.
string grammar(Memoization memo = Memoization.yes)(scope const ref ParseTree definition) nothrow {
    if (!definition.successful)
        return "static assert(false, `Cannot generate from a failed grammar parse`);";
    return grammar!(memo)(definition.input);
}

nothrow unittest {
    import npegged.parser : Pegged;

    ParseContext context;
    auto parsed = Pegged(context, "TreeInput: A <- 'a'");
    auto source = grammar(parsed.tree);
    assert(source.length);
    ParseTree invalid;
    auto failure = grammar(invalid);
    assert(failure.length);
}

/// Borrow a scoped file and generate a parser module, preserving I/O error status.
Status asModule(Memoization memo = Memoization.yes)(string moduleName, string destination,
        ref npegged.io.File input, string header = "") nothrow {
    import npegged.storage : Buffer;

    Buffer!char text;
    auto status = input.read(text);
    if (status != Status.ok)
        return status;
    return asModule!(memo)(moduleName, destination, cast(string)text.data, header);
}

nothrow unittest {
    import npegged.io : File;

    File invalid;
    assert(asModule("test", "build/from-file", invalid) == Status.ioError);
    {
        auto output = File.open("build/input.peg", true);
        assert(output.write("FromFile: A <- 'a'") == Status.ok);
    }
    auto input = File.open("build/input.peg");
    assert(asModule("from_file", "build/from-file", input) == Status.ok);
}

version (unittest) mixin(grammar(`RawBytes: Start <- [\xFF] :eoi`));
@nogc nothrow unittest {
    ParseContext context;
    auto raw = RawBytes(context, "\xff");
    assert(raw.successful && raw.end == 1);
    auto unicode = RawBytes(context, "ÿ");
    assert(!unicode.successful);
}
