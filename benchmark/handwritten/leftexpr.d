module benchmark.handwritten.leftexpr;

/// Handwritten twin of the left-recursive `BenchLeftExpr` grammar: whole-input acceptance of
/// `Expr <- Expr ('+'/'-') Space Term / Term`, `Term <- Term ('*'/'/') Space Primary / Primary`.
/// A suffix that fails after its operator is not consumed (seed growth stops), and the root then needs the end of input.
struct LeftExprParser {
    private string input;
    private size_t at;

    private bool isSpace(char c) @nogc nothrow pure @safe {
        return c == ' ' || c == '\t' || c == '\n';
    }

    private void space() @nogc nothrow {
        while (at < input.length && isSpace(input[at]))
            ++at;
    }

    private bool primary() @nogc nothrow {
        if (at < input.length && input[at] == '(') {
            const start = at;
            ++at;
            space();
            if (expression() && at < input.length && input[at] == ')') {
                ++at;
                space();
                return true;
            }
            at = start;
            return false;
        }
        if (at < input.length && input[at] >= '0' && input[at] <= '9') {
            while (at < input.length && input[at] >= '0' && input[at] <= '9')
                ++at;
            space();
            return true;
        }
        return false;
    }

    private bool term() @nogc nothrow {
        if (!primary())
            return false;
        while (at < input.length && (input[at] == '*' || input[at] == '/')) {
            const start = at;
            ++at;
            space();
            if (!primary()) {
                at = start;
                break;
            }
        }
        return true;
    }

    private bool expression() @nogc nothrow {
        if (!term())
            return false;
        while (at < input.length && (input[at] == '+' || input[at] == '-')) {
            const start = at;
            ++at;
            space();
            if (!term()) {
                at = start;
                break;
            }
        }
        return true;
    }

    static bool parse(string text) @nogc nothrow {
        LeftExprParser parser;
        parser.input = text;
        parser.space();
        return parser.expression() && parser.at == text.length;
    }
}

@nogc nothrow unittest {
    assert(LeftExprParser.parse("1") && LeftExprParser.parse(" 1 + 2 * (3 - 4) ") && LeftExprParser
            .parse("((7))"));
    assert(LeftExprParser.parse("1+2+3-4*5/6"));
    assert(!LeftExprParser.parse("") && !LeftExprParser.parse("1+")
            && !LeftExprParser.parse("1 * ") && !LeftExprParser.parse("(1")
            && !LeftExprParser.parse("1)") && !LeftExprParser.parse("+1"));
}
