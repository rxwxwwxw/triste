module benchmark.handwritten.peg;

import npegged.storage : Arena, Status;
import npegged.records : CompactNode, RecordBuffer;

enum PegKind : uint {
    root = 100,
    definition,
    expression,
    sequence,
    prefix,
    primary
}

alias PegParser = PegParserImpl!false;

private struct PegParserImpl(bool Capture) {
    private string input;
    private size_t pos;
    static if (Capture) {
        RecordBuffer* output;
        bool spans;
    }

    static if (!Capture)
        static bool parse(string s) @nogc nothrow {
            PegParserImpl p;
            p.input = s;
            p.pos = 0;
            return p.parseGrammar();
        }

    private void skipSpacing()() @nogc nothrow {
        while (pos < input.length) {
            char c = input[pos];
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                pos++;
            } else if (c == '#') {
                while (pos < input.length && input[pos] != '\n') {
                    pos++;
                }
            } else {
                break;
            }
        }
    }

    private bool isIdentStart()(char c) const @nogc nothrow {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    }

    private bool isIdentChar()(char c) const @nogc nothrow {
        return isIdentStart(c) || (c >= '0' && c <= '9');
    }

    private bool parseIdent()(out string id) @nogc nothrow {
        skipSpacing();
        if (pos >= input.length || !isIdentStart(input[pos]))
            return false;
        size_t start = pos++;
        while (pos < input.length && isIdentChar(input[pos]))
            pos++;
        id = input[start .. pos];
        return true;
    }

    private bool parseGrammar()() @nogc nothrow {
        bool accepted;
        static if (Capture) {
            const checkpoint = output.length;
            const parent = output.parent;
            const index = output.openKind(spans && PegKind.root != PegKind.primary ? uint.max
                    : cast(uint)PegKind.root, pos);
        }
        scope (exit) {
            static if (Capture) {
                if (accepted)
                    output.finish(index, pos);
                else
                    output.rollback(checkpoint);
                output.parent = parent;
            }
        }

        skipSpacing();
        string name;
        if (!parseIdent(name))
            return accepted = (false);
        skipSpacing();
        if (pos < input.length && input[pos] == '(') {
            pos++;
            size_t depth = 1;
            while (pos < input.length && depth > 0) {
                char ch = input[pos];
                if (ch == '\'' || ch == '"') {
                    pos++;
                    while (pos < input.length && input[pos] != ch) {
                        if (input[pos] == '\\' && pos + 1 < input.length)
                            pos += 2;
                        else
                            pos++;
                    }
                    if (pos < input.length)
                        pos++;
                } else if (ch == '(') {
                    depth++;
                    pos++;
                } else if (ch == ')') {
                    depth--;
                    pos++;
                } else {
                    pos++;
                }
            }
            if (depth != 0)
                return accepted = (false);
            skipSpacing();
        }
        if (pos >= input.length || input[pos] != ':')
            return accepted = (false);
        pos++;

        skipSpacing();
        size_t defCount = 0;
        while (pos < input.length) {
            if (!parseDefinition())
                return accepted = (false);
            defCount++;
            skipSpacing();
        }
        return accepted = (defCount > 0 && pos == input.length);
    }

    private bool parseDefinition()() @nogc nothrow {
        bool accepted;
        static if (Capture) {
            const checkpoint = output.length;
            const parent = output.parent;
            const index = output.openKind(spans && PegKind.definition != PegKind.primary ? uint.max
                    : cast(uint)PegKind.definition, pos);
        }
        scope (exit) {
            static if (Capture) {
                if (accepted)
                    output.finish(index, pos);
                else
                    output.rollback(checkpoint);
                output.parent = parent;
            }
        }

        skipSpacing();
        string id;
        if (!parseIdent(id))
            return accepted = (false);
        skipSpacing();
        if (pos < input.length && input[pos] == '(') {
            pos++;
            size_t depth = 1;
            while (pos < input.length && depth > 0) {
                char ch = input[pos];
                if (ch == '\'' || ch == '"') {
                    pos++;
                    while (pos < input.length && input[pos] != ch) {
                        if (input[pos] == '\\' && pos + 1 < input.length)
                            pos += 2;
                        else
                            pos++;
                    }
                    if (pos < input.length)
                        pos++;
                } else if (ch == '(') {
                    depth++;
                    pos++;
                } else if (ch == ')') {
                    depth--;
                    pos++;
                } else {
                    pos++;
                }
            }
            if (depth != 0)
                return accepted = (false);
            skipSpacing();
        }

        if (pos >= input.length || input[pos] != '<')
            return accepted = (false);
        pos++;
        if (pos < input.length) {
            char c = input[pos];
            if (c == '-') {
                while (pos < input.length && input[pos] == '-')
                    pos++;
            } else if (c == '~' || c == ':' || c == '^' || c == ';' || c == '%') {
                pos++;
            } else if (c == '{') {
                pos++;
                size_t depth = 1;
                while (pos < input.length && depth > 0) {
                    char ch = input[pos];
                    if (ch == '\'' || ch == '"') {
                        pos++;
                        while (pos < input.length && input[pos] != ch) {
                            if (input[pos] == '\\' && pos + 1 < input.length)
                                pos += 2;
                            else
                                pos++;
                        }
                        if (pos < input.length)
                            pos++;
                    } else if (ch == '{') {
                        depth++;
                        pos++;
                    } else if (ch == '}') {
                        depth--;
                        pos++;
                    } else {
                        pos++;
                    }
                }
                if (depth != 0)
                    return accepted = (false);
            }
        }
        skipSpacing();

        return accepted = (parseExpression());
    }

    private bool parseExpression()() @nogc nothrow {
        bool accepted;
        static if (Capture) {
            const checkpoint = output.length;
            const parent = output.parent;
            const index = output.openKind(spans && PegKind.expression != PegKind.primary ? uint.max
                    : cast(uint)PegKind.expression, pos);
        }
        scope (exit) {
            static if (Capture) {
                if (accepted)
                    output.finish(index, pos);
                else
                    output.rollback(checkpoint);
                output.parent = parent;
            }
        }

        skipSpacing();
        if (pos < input.length && (input[pos] == '/' || input[pos] == '|')) {
            pos++;
            skipSpacing();
        }
        if (!parseSequence())
            return accepted = (false);
        while (true) {
            skipSpacing();
            if (pos < input.length && (input[pos] == '/' || input[pos] == '|')) {
                pos++;
                skipSpacing();
                if (!parseSequence())
                    return accepted = (false);
            } else {
                break;
            }
        }
        return accepted = (true);
    }

    private bool isPrefixChar()(char c) const @nogc nothrow {
        return c == '&' || c == '!' || c == '~' || c == ':' || c == '^' || c == ';' || c == '%';
    }

    private bool parseSequence()() @nogc nothrow {
        bool accepted;
        static if (Capture) {
            const checkpoint = output.length;
            const parent = output.parent;
            const index = output.openKind(spans && PegKind.sequence != PegKind.primary ? uint.max
                    : cast(uint)PegKind.sequence, pos);
        }
        scope (exit) {
            static if (Capture) {
                if (accepted)
                    output.finish(index, pos);
                else
                    output.rollback(checkpoint);
                output.parent = parent;
            }
        }

        skipSpacing();
        size_t pieceCount = 0;
        while (pos < input.length) {
            skipSpacing();
            if (pos >= input.length)
                break;
            char c = input[pos];
            if (c == '/' || c == '|' || c == ')')
                break;
            if (isDefinitionAhead())
                break;
            if (!parsePrefix())
                return accepted = (false);
            pieceCount++;
        }
        return accepted = (pieceCount > 0);
    }

    private bool isDefinitionAhead()() @nogc nothrow {
        size_t saved = pos;
        scope (exit)
            pos = saved;
        skipSpacing();
        string id;
        if (!parseIdent(id))
            return false;
        skipSpacing();
        if (pos < input.length && input[pos] == '(') {
            pos++;
            size_t depth = 1;
            while (pos < input.length && depth > 0) {
                if (input[pos] == '(')
                    depth++;
                else if (input[pos] == ')')
                    depth--;
                pos++;
            }
            if (depth != 0)
                return false;
            skipSpacing();
        }
        return pos < input.length && input[pos] == '<';
    }

    private bool parsePrefix()() @nogc nothrow {
        bool accepted;
        static if (Capture) {
            const checkpoint = output.length;
            const parent = output.parent;
            const index = output.openKind(spans && PegKind.prefix != PegKind.primary ? uint.max
                    : cast(uint)PegKind.prefix, pos);
        }
        scope (exit) {
            static if (Capture) {
                if (accepted)
                    output.finish(index, pos);
                else
                    output.rollback(checkpoint);
                output.parent = parent;
            }
        }

        skipSpacing();
        while (pos < input.length && isPrefixChar(input[pos])) {
            pos++;
            skipSpacing();
        }
        if (!parsePrimary())
            return accepted = (false);
        while (pos < input.length) {
            char c = input[pos];
            if (c == '*' || c == '+' || c == '?') {
                pos++;
            } else if (c == '{') {
                pos++;
                size_t depth = 1;
                while (pos < input.length && depth > 0) {
                    char ch = input[pos];
                    if (ch == '\'' || ch == '"') {
                        pos++;
                        while (pos < input.length && input[pos] != ch) {
                            if (input[pos] == '\\' && pos + 1 < input.length)
                                pos += 2;
                            else
                                pos++;
                        }
                        if (pos < input.length)
                            pos++;
                    } else if (ch == '{') {
                        depth++;
                        pos++;
                    } else if (ch == '}') {
                        depth--;
                        pos++;
                    } else {
                        pos++;
                    }
                }
                if (depth != 0)
                    return accepted = (false);
            } else {
                break;
            }
        }
        return accepted = (true);
    }

    private bool parsePrimary()() @nogc nothrow {
        bool accepted;
        static if (Capture) {
            const checkpoint = output.length;
            const parent = output.parent;
            const index = output.openKind(spans && PegKind.primary != PegKind.primary ? uint.max
                    : cast(uint)PegKind.primary, pos);
        }
        scope (exit) {
            static if (Capture) {
                if (accepted)
                    output.finish(index, pos);
                else
                    output.rollback(checkpoint);
                output.parent = parent;
            }
        }

        skipSpacing();
        if (pos >= input.length)
            return accepted = (false);
        char c = input[pos];

        if (c == '(') {
            pos++;
            skipSpacing();
            if (!parseExpression())
                return accepted = (false);
            skipSpacing();
            if (pos >= input.length || input[pos] != ')')
                return accepted = (false);
            pos++;
            return accepted = (true);
        }

        if (c == '.') {
            pos++;
            return accepted = (true);
        }

        if (c == '\'' || c == '"') {
            char quote = c;
            pos++;
            while (pos < input.length && input[pos] != quote) {
                if (input[pos] == '\\' && pos + 1 < input.length)
                    pos += 2;
                else
                    pos++;
            }
            if (pos >= input.length || input[pos] != quote)
                return accepted = (false);
            pos++;
            if (pos < input.length && input[pos] == 'i')
                pos++;
            return accepted = (true);
        }

        if (c == '[') {
            pos++;
            if (pos < input.length && input[pos] == '^')
                pos++;
            while (pos < input.length && input[pos] != ']') {
                if (input[pos] == '\\' && pos + 1 < input.length)
                    pos += 2;
                else
                    pos++;
            }
            if (pos >= input.length || input[pos] != ']')
                return accepted = (false);
            pos++;
            return accepted = (true);
        }

        string id;
        if (parseIdent(id)) {
            if (pos < input.length && input[pos] == '(') {
                pos++;
                size_t depth = 1;
                while (pos < input.length && depth > 0) {
                    char ch = input[pos];
                    if (ch == '\'' || ch == '"') {
                        pos++;
                        while (pos < input.length && input[pos] != ch) {
                            if (input[pos] == '\\' && pos + 1 < input.length)
                                pos += 2;
                            else
                                pos++;
                        }
                        if (pos < input.length)
                            pos++;
                    } else if (ch == '(') {
                        depth++;
                        pos++;
                    } else if (ch == ')') {
                        depth--;
                        pos++;
                    } else {
                        pos++;
                    }
                }
                if (depth != 0)
                    return accepted = (false);
            }
            while (pos + 1 < input.length && input[pos] == '.' && isIdentStart(input[pos + 1])) {
                pos++;
                string subId;
                if (!parseIdent(subId))
                    return accepted = (false);
            }
            return accepted = (true);
        }

        return accepted = (false);
    }
}

@nogc nothrow unittest {
    enum samplePegSmall = "Calc:\n  Expr <- Term ('+' Term)*\n  Term <- [0-9]+\n";
    assert(PegParser.parse(samplePegSmall));

    enum samplePegMedium = "JSON:\n" ~ "  JSONObject < :'{' (Pair (:',' Pair)*)? :'}'\n"
        ~ "  Pair       < String :':' Value\n" ~ "  Array      < :'[' (Value (:',' Value)*)? :']'\n"
        ~ "  Value      < String / Number / JSONObject / Array / True / False / Null\n"
        ~ "  True       <- 'true'\n" ~ "  False      <- 'false'\n" ~ "  Null       <- 'null'\n";
    assert(PegParser.parse(samplePegMedium));

    enum gArith = `
# Arithmetic grammar with variable terminal
Arithmetic:
    Term     < Factor (Add / Sub)*
    Add      < "+" Factor
    Sub      < "-" Factor
    Factor   < Primary (Mul / Div)*
    Mul      < "*" Primary
    Div      < "/" Primary
    Primary  < Parens / Neg / Number / Variable
    Parens   < :"(" Term :")"
    Neg      < "-" Primary
    Number   < ~([0-9]+)
    Variable <- identifier
`;
    assert(PegParser.parse(gArith));

    enum gJson = `
JSON:
    JSONObject <  :'{' (Pair (:',' Pair)*)? :'}'
    Pair       <  String :':' Value
    Array      <  :'[' (Value (:',' Value)* )? :']'

    Value  <  String
            / Number
            / JSONObject
            / Array
            / True
            / False
            / Null
    True   <- "true"
    False  <- "false"
    Null   <- "null"

    String <~ :doublequote Char* :doublequote
    Char   <~ backslash doublequote
            / backslash backslash
            / backslash [bfnrt]
            / backslash 'u' Hex Hex Hex Hex
            / (!doublequote .)

    Number <~ '0'
            / [1-9] Digit* ('.' Digit*)?
    Digit  <- [0-9]
    Hex    <- [0-9A-Fa-f]
`;
    assert(PegParser.parse(gJson));

    // Negative tests
    assert(!PegParser.parse(""));
    assert(!PegParser.parse("   \n\t"));
    assert(!PegParser.parse("Calc Expr <- Term"));
    assert(!PegParser.parse("Calc:"));
    assert(!PegParser.parse("Calc:\n Expr Term"));
    assert(!PegParser.parse("Calc:\n Expr <- "));
    assert(!PegParser.parse("Calc:\n Expr <- (Term\n"));
    assert(!PegParser.parse("Calc:\n Expr <- 'Term\n"));
    assert(!PegParser.parse("Calc:\n Expr <- [0-9\n"));
    assert(!PegParser.parse("Calc:\n Expr <- Term { action\n"));
    assert(!PegParser.parse("Calc:\n Expr <- Term\n %"));
    assert(!PegParser.parse("Calc:\n Expr <- Term\n <"));
}

struct PegTreeResult {
    Arena arena;
    CompactNode[] nodes;
    bool accepted;
    Status status;
    @disable this(this);
    @disable this(ref PegTreeResult);
}

PegTreeResult parsePegTree(string input, bool spans = false, size_t limit = 256 * 1024 * 1024) @nogc nothrow {
    PegTreeResult result;
    result.arena.limit = limit;
    RecordBuffer output;
    output.arena = &result.arena;
    PegParserImpl!true parser;
    parser.input = input;
    parser.output = &output;
    parser.spans = spans;
    result.accepted = parser.parseGrammar();
    result.status = output.status != Status.ok ? output.status : result.accepted ? Status.ok : Status
        .mismatch;
    result.accepted = result.status == Status.ok;
    if (!result.accepted)
        output.rollback(0);
    result.nodes = output.nodes;
    return result;
}

@nogc nothrow unittest {
    auto tree = parsePegTree("G: A <- ('a' / B)+");
    assert(tree.accepted && tree.nodes.length > 6);
    assert(tree.nodes[0].kind == PegKind.root && tree.nodes[0].parent == size_t.max);
    assert(tree.nodes[1].kind == PegKind.definition && tree.nodes[1].parent == 0);
    assert(!parsePegTree("G: A <- (").nodes.length);
    assert(parsePegTree("G: A <- 'a'", false, 0).status == Status.resourceLimit);
}
