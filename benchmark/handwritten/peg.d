module benchmark.handwritten.peg;

struct PegParser {
    private string input;
    private size_t pos;

    static bool parse(string s) @nogc nothrow pure @safe {
        PegParser p;
        p.input = s;
        p.pos = 0;
        return p.parseGrammar();
    }

    private void skipSpacing() @nogc nothrow pure @safe {
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

    private bool isIdentStart(char c) const @nogc nothrow pure @safe {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    }

    private bool isIdentChar(char c) const @nogc nothrow pure @safe {
        return isIdentStart(c) || (c >= '0' && c <= '9');
    }

    private bool parseIdent(out string id) @nogc nothrow pure @safe {
        skipSpacing();
        if (pos >= input.length || !isIdentStart(input[pos]))
            return false;
        size_t start = pos++;
        while (pos < input.length && isIdentChar(input[pos]))
            pos++;
        id = input[start .. pos];
        return true;
    }

    private bool parseGrammar() @nogc nothrow pure @safe {
        skipSpacing();
        string name;
        if (!parseIdent(name))
            return false;
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
                return false;
            skipSpacing();
        }
        if (pos >= input.length || input[pos] != ':')
            return false;
        pos++;

        skipSpacing();
        size_t defCount = 0;
        while (pos < input.length) {
            if (!parseDefinition())
                return false;
            defCount++;
            skipSpacing();
        }
        return defCount > 0 && pos == input.length;
    }

    private bool parseDefinition() @nogc nothrow pure @safe {
        skipSpacing();
        string id;
        if (!parseIdent(id))
            return false;
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
                return false;
            skipSpacing();
        }

        if (pos >= input.length || input[pos] != '<')
            return false;
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
                    return false;
            }
        }
        skipSpacing();

        return parseExpression();
    }

    private bool parseExpression() @nogc nothrow pure @safe {
        skipSpacing();
        if (pos < input.length && (input[pos] == '/' || input[pos] == '|'))
            pos++;
        if (!parseSequence())
            return false;
        while (true) {
            skipSpacing();
            if (pos < input.length && (input[pos] == '/' || input[pos] == '|')) {
                pos++;
                skipSpacing();
                if (!parseSequence())
                    return false;
            } else {
                break;
            }
        }
        return true;
    }

    private bool isPrefixChar(char c) const @nogc nothrow pure @safe {
        return c == '&' || c == '!' || c == '~' || c == ':' || c == '^' || c == ';' || c == '%';
    }

    private bool parseSequence() @nogc nothrow pure @safe {
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
                return false;
            pieceCount++;
        }
        return pieceCount > 0;
    }

    private bool isDefinitionAhead() @nogc nothrow pure @safe {
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

    private bool parsePrefix() @nogc nothrow pure @safe {
        skipSpacing();
        while (pos < input.length && isPrefixChar(input[pos])) {
            pos++;
            skipSpacing();
        }
        if (!parsePrimary())
            return false;
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
                    return false;
            } else {
                break;
            }
        }
        return true;
    }

    private bool parsePrimary() @nogc nothrow pure @safe {
        skipSpacing();
        if (pos >= input.length)
            return false;
        char c = input[pos];

        if (c == '(') {
            pos++;
            skipSpacing();
            if (!parseExpression())
                return false;
            skipSpacing();
            if (pos >= input.length || input[pos] != ')')
                return false;
            pos++;
            return true;
        }

        if (c == '.') {
            pos++;
            return true;
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
                return false;
            pos++;
            if (pos < input.length && input[pos] == 'i')
                pos++;
            return true;
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
                return false;
            pos++;
            return true;
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
                    return false;
            }
            while (pos + 1 < input.length && input[pos] == '.' && isIdentStart(input[pos + 1])) {
                pos++;
                string subId;
                if (!parseIdent(subId))
                    return false;
            }
            return true;
        }

        return false;
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
