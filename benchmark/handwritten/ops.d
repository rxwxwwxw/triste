module benchmark.handwritten.ops;

/// Handwritten twin of the `BenchOps` grammar: whitespace-separated one- and two-byte operators.
/// Ordered choice: the listed two-byte operators win over their one-byte prefixes.
struct OpsParser {
    private static bool isSpace(char c) @nogc nothrow pure @safe {
        return c == ' ' || c == '\t' || c == '\n';
    }

    private static bool twoByte(char a, char b) @nogc nothrow pure @safe {
        if (b == '=')
            return a == '<' || a == '>' || a == '=' || a == '!' || a == '+' || a == '-' || a == '*' || a == '/';
        return a == '<' && b == '<' || a == '>' && b == '>' || a == '&' && b == '&' || a == '|' && b == '|'
            || a == '+' && b == '+' || a == '-' && b == '-';
    }

    private static bool oneByte(char c) @nogc nothrow pure @safe {
        return c == '<' || c == '>' || c == '=' || c == '!' || c == '&' || c == '|' || c == '+'
            || c == '-' || c == '*' || c == '/';
    }

    static bool parse(string input) @nogc nothrow pure @safe {
        size_t at;
        while (at < input.length && isSpace(input[at]))
            ++at;
        while (at < input.length) {
            if (at + 1 < input.length && twoByte(input[at], input[at + 1]))
                at += 2;
            else if (oneByte(input[at]))
                ++at;
            else
                return false;
            while (at < input.length && isSpace(input[at]))
                ++at;
        }
        return true;
    }
}

@nogc nothrow pure @safe unittest {
    assert(OpsParser.parse("") && OpsParser.parse("  \t\n") && OpsParser.parse("<<= == != ++ - /"));
    assert(OpsParser.parse("<<<") && OpsParser.parse("=== !") && OpsParser.parse("&&|||"));
    assert(!OpsParser.parse("a") && !OpsParser.parse("< a") && !OpsParser.parse("<=x") && !OpsParser
            .parse("~"));
    assert(OpsParser.parse("&") && OpsParser.parse("|") && OpsParser.parse("&="));
}
