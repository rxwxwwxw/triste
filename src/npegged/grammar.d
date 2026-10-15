/** Grammar frontend derived from Pegged's extended PEG syntax (Boost 1.0).
    Runtime code generation is a cold path using selective druntime GC. */
module npegged.grammar;
public import npegged.peg;
import npegged.io;
import npegged.analysis : GrammarAnalysis, Expression, ExpressionKind, Nullable, FirstFacts;

nothrow:

struct Diagnostic {
    size_t offset;
    string message;
}

enum Memoization {
    no,
    yes,
    selective
}

private string number(ulong value) pure nothrow {
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

private bool startsWith(scope string s, scope string prefix) @nogc nothrow pure @safe {
    return s.length >= prefix.length && s[0 .. prefix.length] == prefix;
}

private string ulongHex(ulong value) pure nothrow {
    if (value == 0)
        return "0x0UL";
    char[22] buf;
    buf[0 .. 2] = "0x";
    enum hex = "0123456789abcdef";
    char[16] digits;
    size_t len;
    ulong v = value;
    while (v) {
        digits[len++] = hex[v & 0xF];
        v >>= 4;
    }
    size_t outLen = 2;
    while (len) {
        buf[outLen++] = digits[--len];
    }
    return (buf[0 .. outLen] ~ "UL").idup;
}

unittest {
    assert(ulongHex(0) == "0x0UL");
    assert(ulongHex(15) == "0xfUL");
    assert(ulongHex(256) == "0x100UL");
    assert(startsWith("hello world", "hello"));
    assert(!startsWith("hello", "world"));
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
    bool selective;
    uint[] recordKinds;
    string[] parameterNames;
    private GrammarAnalysis analyzed;
    private bool hasAnalysis;
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
            parameterNames ~= id;
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
            bool allAscii = true;
            CharSetMask mask;
            size_t elementCount = 0;
            dchar singleFirst = 0, singleLast = 0;
            bool singleByteEscape = false;
            string[] nonAsciiRanges;
            while (pos < input.length && input[pos] != ']' && !error.message.length) {
                bool byteEscape = input[pos] == '\\' && pos + 1 < input.length
                    && (input[pos + 1] == 'x' || input[pos + 1] >= '0' && input[pos + 1] <= '7');
                auto first = character();
                if (pos < input.length && input[pos] == '-' && pos + 1 < input.length && input[pos + 1] != ']') {
                    ++pos;
                    auto last = character();
                    if (last < 256) {
                        mask.addRange(first, last);
                    } else {
                        allAscii = false;
                        nonAsciiRanges ~= "charRange!(" ~ number(first) ~ ", " ~ number(last) ~ ")";
                    }
                    singleFirst = first;
                    singleLast = last;
                    singleByteEscape = false;
                    ++elementCount;
                } else if (byteEscape) {
                    if (first < 256) {
                        mask.addChar(first);
                    } else {
                        allAscii = false;
                        nonAsciiRanges ~= "literal!(" ~ quoted([cast(char)first].idup) ~ ")";
                    }
                    singleFirst = first;
                    singleLast = first;
                    singleByteEscape = true;
                    ++elementCount;
                } else {
                    if (first < 256) {
                        mask.addChar(first);
                    } else {
                        allAscii = false;
                        nonAsciiRanges ~= "charRange!(" ~ number(first) ~ ", " ~ number(first) ~ ")";
                    }
                    singleFirst = first;
                    singleLast = first;
                    singleByteEscape = false;
                    ++elementCount;
                }
            }
            require(']');
            if (!elementCount)
                result = "fail";
            else if (elementCount == 1 && singleByteEscape) {
                result = "literal!(" ~ quoted([cast(char)singleFirst].idup) ~ ")";
            } else if (elementCount == 1 && allAscii) {
                result = "charRange!(" ~ number(singleFirst) ~ ", " ~ number(singleLast) ~ ")";
            } else if (allAscii) {
                result = "charClass!(" ~ ulongHex(mask.bits[0]) ~ ", " ~ ulongHex(
                        mask.bits[1]) ~ ", " ~ ulongHex(mask.bits[2]) ~ ", " ~ ulongHex(mask.bits[3]) ~ ")";
            } else {
                string[] allChoices;
                if (!mask.empty)
                    allChoices ~= "charClass!(" ~ ulongHex(mask.bits[0]) ~ ", " ~ ulongHex(
                            mask.bits[1]) ~ ", " ~ ulongHex(mask.bits[2]) ~ ", " ~ ulongHex(mask.bits[3]) ~ ")";
                allChoices ~= nonAsciiRanges;
                result = "or!(";
                foreach (i, c; allChoices)
                    result ~= (i ? ", " : "") ~ c;
                result ~= ")";
            }
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
        hasAnalysis = false;
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

    struct FirstSetResult {
        bool known;
        bool canBeEmpty;
        CharSetMask mask;
    }

    FirstSetResult primitiveFirstSet(string expr) const nothrow {
        FirstSetResult res;
        while (expr.length > 0 && expr[0] == ' ')
            expr = expr[1 .. $];
        while (expr.length > 0 && expr[$ - 1] == ' ')
            expr = expr[0 .. $ - 1];

        if (startsWith(expr, "literal!(") || startsWith(expr, "literal!\"")) {
            size_t qStart = 0;
            while (qStart < expr.length && expr[qStart] != '"')
                qStart++;
            if (qStart < expr.length) {
                size_t qEnd = qStart + 1;
                while (qEnd < expr.length && expr[qEnd] != '"') {
                    if (expr[qEnd] == '\\' && qEnd + 1 < expr.length)
                        qEnd += 2;
                    else
                        qEnd++;
                }
                string content = expr[qStart + 1 .. qEnd];
                if (content.length == 0) {
                    res.known = true;
                    res.canBeEmpty = true;
                    return res;
                }
                char c = content[0];
                if (c == '\\' && content.length > 1) {
                    char esc = content[1];
                    switch (esc) {
                    case 'n':
                        c = '\n';
                        break;
                    case 'r':
                        c = '\r';
                        break;
                    case 't':
                        c = '\t';
                        break;
                    case '0':
                        c = '\0';
                        break;
                    case '\\':
                        c = '\\';
                        break;
                    case '"':
                        c = '"';
                        break;
                    default:
                        c = esc;
                        break;
                    }
                }
                res.known = true;
                res.canBeEmpty = false;
                res.mask.addChar(c);
                return res;
            }
        }

        if (startsWith(expr, "charRange!(")) {
            string inner = expr[11 .. $];
            if (inner.length > 0 && inner[$ - 1] == ')')
                inner = inner[0 .. $ - 1];
            size_t comma = 0;
            while (comma < inner.length && inner[comma] != ',')
                comma++;
            if (comma < inner.length) {
                string sLow = inner[0 .. comma];
                string sHigh = inner[comma + 1 .. $];
                while (sLow.length > 0 && sLow[0] == ' ')
                    sLow = sLow[1 .. $];
                while (sHigh.length > 0 && sHigh[0] == ' ')
                    sHigh = sHigh[1 .. $];
                uint low = 0, high = 0;
                foreach (ch; sLow) {
                    if (ch >= '0' && ch <= '9')
                        low = low * 10 + (ch - '0');
                }
                foreach (ch; sHigh) {
                    if (ch >= '0' && ch <= '9')
                        high = high * 10 + (ch - '0');
                }
                if (high < 128 && low <= high) {
                    res.known = true;
                    res.canBeEmpty = false;
                    res.mask.addRange(low, high);
                    return res;
                }
            }
        }

        if (startsWith(expr, "charClass!(")) {
            string inner = expr[11 .. $];
            if (inner.length > 0 && inner[$ - 1] == ')')
                inner = inner[0 .. $ - 1];
            ulong[4] b;
            size_t idx = 0;
            size_t start = 0;
            for (size_t i = 0; i <= inner.length && idx < 4; ++i) {
                if (i == inner.length || inner[i] == ',') {
                    string part = inner[start .. i];
                    while (part.length > 0 && (part[0] == ' ' || part[0] == '\t'))
                        part = part[1 .. $];
                    while (part.length > 0 && (part[$ - 1] == 'U' || part[$ - 1] == 'L' || part[$ - 1] == ' '))
                        part = part[0 .. $ - 1];
                    ulong val = 0;
                    if (startsWith(part, "0x") || startsWith(part, "0X")) {
                        foreach (ch; part[2 .. $]) {
                            uint n = ch >= '0' && ch <= '9' ? ch - '0' : ch >= 'a' && ch <= 'f'
                                ? ch - 'a' + 10 : ch >= 'A' && ch <= 'F' ? ch - 'A' + 10 : 0;
                            val = (val << 4) | n;
                        }
                    } else {
                        foreach (ch; part) {
                            if (ch >= '0' && ch <= '9')
                                val = val * 10 + (ch - '0');
                        }
                    }
                    b[idx++] = val;
                    start = i + 1;
                }
            }
            if (idx == 4) {
                res.known = true;
                res.canBeEmpty = false;
                res.mask = CharSetMask(b);
                return res;
            }
        }

        if (expr == "digit") {
            res.known = true;
            res.mask.addRange('0', '9');
            return res;
        }
        if (expr == "alpha") {
            res.known = true;
            res.mask.addRange('a', 'z');
            return res;
        }
        if (expr == "Alpha") {
            res.known = true;
            res.mask.addRange('A', 'Z');
            return res;
        }
        if (expr == "hexDigit") {
            res.known = true;
            res.mask.addRange('0', '9');
            res.mask.addRange('a', 'f');
            res.mask.addRange('A', 'F');
            return res;
        }
        if (expr == "space") {
            res.known = true;
            res.mask.addChar(' ');
            res.mask.addChar('\t');
            res.mask.addChar('\v');
            return res;
        }
        if (expr == "blank") {
            res.known = true;
            res.mask.addChar(' ');
            res.mask.addChar('\t');
            res.mask.addChar('\v');
            res.mask.addChar('\r');
            res.mask.addChar('\n');
            return res;
        }
        if (expr == "ident" || expr == "identifier") {
            res.known = true;
            res.mask.addRange('a', 'z');
            res.mask.addRange('A', 'Z');
            res.mask.addChar('_');
            return res;
        }

        return res;
    }

    private size_t expressionNode(ref GrammarAnalysis graph, string text) const nothrow {
        while (text.length && (text[0] == ' ' || text[0] == '\t'))
            text = text[1 .. $];
        while (text.length && (text[$ - 1] == ' ' || text[$ - 1] == '\t'))
            text = text[0 .. $ - 1];
        Expression node;
        node.source = text;
        bool parameter;
        foreach (name; parameterNames)
            if (text == name)
                parameter = true;
        if (parameter)
            node.kind = ExpressionKind.unknown;
        else if (graph.ruleIndex(text) != size_t.max) {
            node.kind = ExpressionKind.reference;
            node.reference = text;
        } else if (text == "eps" || text == "eoi" || text == "endOfInput" || text == "fail") {
            node.kind = ExpressionKind.terminal;
            node.known = true;
            node.nullable = text == "fail" ? Nullable.no : Nullable.yes;
        } else if (text == "any") {
            node.kind = ExpressionKind.terminal;
            node.known = true;
            node.nullable = Nullable.no;
            node.first = CharSetMask([ulong.max, ulong.max, ulong.max, ulong.max]);
        } else {
            size_t marker;
            while (marker < text.length && text[marker] != '!')
                ++marker;
            string combinator = text[0 .. marker];
            bool compound = marker + 2 < text.length && text[marker .. marker + 2] == "!(" && text[$ - 1] == ')';
            string[] args;
            if (compound)
                args = splitTemplateArgs(text[marker + 2 .. $ - 1]);
            node.arguments = args;
            bool children;
            if (compound && (combinator == "and" || combinator == "wrapAround")) {
                node.kind = ExpressionKind.sequence;
                children = true;
            } else if (compound && (combinator == "or" || combinator == "longest_match"
                    || combinator == "predictiveChoice")) {
                node.kind = ExpressionKind.choice;
                children = true;
            } else if (compound && args.length && (combinator == "option" || combinator == "zeroOrMore")) {
                node.kind = combinator == "option" ? ExpressionKind.optional : ExpressionKind
                    .repetition;
                args.length = 1;
                children = true;
            } else if (compound && args.length && (combinator == "posLookahead" || combinator == "negLookahead")) {
                node.kind = ExpressionKind.predicate;
                args.length = 1;
                children = true;
            } else if (compound && args.length && (combinator == "discard" || combinator == "fuse"
                    || combinator == "keep"
                    || combinator == "drop" || combinator == "propagate" || combinator == "oneOrMore"
                    || combinator == "named" || combinator == "defined" || combinator == "branch")) {
                node.kind = ExpressionKind.wrapper;
                args.length = 1;
                children = true;
            }
            if (children) {
                node.combinator = combinator;
                foreach (arg; args)
                    node.children ~= expressionNode(graph, arg);
            } else {
                auto primitive = primitiveFirstSet(text);
                if (primitive.known) {
                    node.kind = ExpressionKind.terminal;
                    node.first = primitive.mask;
                    node.known = true;
                    node.nullable = primitive.canBeEmpty ? Nullable.yes : Nullable.no;
                } else if (startsWith(text, "charRange!(") || startsWith(text, "charClass!(")
                        || startsWith(text, "caseInsensitiveLiteral!(")) {
                    // Unknown Unicode FIRST bytes must not imply unknown rule calls.
                    node.kind = ExpressionKind.terminal;
                    node.nullable = Nullable.no;
                } else if (text == "spacing" || text == "Spacing") {
                    node.kind = ExpressionKind.terminal;
                    node.nullable = Nullable.yes;
                    node.known = true;
                    node.first = primitiveFirstSet("blank").mask;
                } else if (text == "doublequote" || text == "backslash" || text == "quote"
                        || text == "slash" || text == "backquote" || text == "tab") {
                    node.kind = ExpressionKind.terminal;
                    node.nullable = Nullable.no;
                    node.known = true;
                    node.first.addChar(text == "doublequote" ? '"' : text == "backslash"
                            ? '\\' : text == "quote" ? '\'' : text == "slash" ? '/' : text == "tab" ? '\t' : '`');
                } else if (text == "endOfLine" || text == "eol") {
                    node.kind = ExpressionKind.terminal;
                    node.nullable = Nullable.no;
                    node.known = true;
                    node.first.addChar('\r');
                    node.first.addChar('\n');
                } else if (marker == text.length) {
                    node.kind = ExpressionKind.reference;
                    node.reference = text;
                }
            }
        }
        graph.expressions ~= node;
        return graph.expressions.length - 1;
    }

    private void prepareAnalysis() nothrow {
        analyzed = GrammarAnalysis.init;
        foreach (rule; rules)
            analyzed.names ~= rule.name;
        foreach (rule; rules)
            analyzed.roots ~= expressionNode(analyzed, rule.body);
        analyzed.solve();
        hasAnalysis = true;
    }

    FirstSetResult computeFirstSet(string expression) nothrow {
        if (!hasAnalysis)
            prepareAnalysis();
        auto query = analyzed;
        auto root = expressionNode(query, expression);
        const value = query.appendFacts(root);
        return FirstSetResult(value.known && value.nullable != Nullable.unknown,
                value.nullable != Nullable.no, value.first);
    }

    static string[] splitTemplateArgs(string args) pure nothrow {
        string[] result;
        size_t depth, start;
        bool inQuote;
        for (size_t i; i < args.length; ++i) {
            const c = args[i];
            if (inQuote && c == '\\' && i + 1 < args.length) {
                ++i;
                continue;
            }
            if (c == '"')
                inQuote = !inQuote;
            else if (!inQuote) {
                if (c == '(')
                    ++depth;
                else if (c == ')' && depth)
                    --depth;
                else if (c == ',' && !depth) {
                    result ~= args[start .. i];
                    start = i + 1;
                }
            }
        }
        if (start < args.length)
            result ~= args[start .. $];
        return result;
    }

    private string dispatchChoice(string[] choices, FirstFacts[] values) nothrow {
        if (choices.length < 2)
            return null;
        foreach (value; values)
            if (!value.known || value.nullable != Nullable.no || value.first.empty)
                return null;
        foreach (i; 0 .. values.length)
            foreach (j; i + 1 .. values.length)
                if (values[i].first.intersects(values[j].first))
                    return null;
        string result = "predictiveChoice!(";
        foreach (i, choice; choices) {
            const mask = values[i].first;
            result ~= (i ? ", " : "") ~ "branch!(" ~ choice ~ ", " ~ ulongHex(
                    mask.bits[0]) ~ ", " ~ ulongHex(mask.bits[1]) ~ ", " ~ ulongHex(
                    mask.bits[2]) ~ ", " ~ ulongHex(mask.bits[3]) ~ ")";
        }
        return result ~ ")";
    }

    string optimizeChoice(string[] choices) nothrow {
        if (!hasAnalysis)
            prepareAnalysis();
        auto query = analyzed;
        FirstFacts[] values;
        foreach (choice; choices) {
            auto root = expressionNode(query, choice);
            values ~= query.appendFacts(root);
        }
        return dispatchChoice(choices, values);
    }

    private string emitExpression(const ref GrammarAnalysis graph, size_t index) nothrow {
        const ref node = graph.expressions[index];
        if (!node.children.length)
            return node.source;
        string[] args;
        foreach (i, argument; node.arguments)
            args ~= i < node.children.length ? emitExpression(graph, node.children[i]) : argument;
        if (node.combinator == "or") {
            FirstFacts[] values;
            foreach (child; node.children)
                values ~= graph.facts[child];
            auto predicted = dispatchChoice(args, values);
            if (predicted.length)
                return predicted;
        }
        string result = node.combinator ~ "!(";
        foreach (i, arg; args)
            result ~= (i ? ", " : "") ~ arg;
        return result ~ ")";
    }

    string optimizeRule(string expression) nothrow {
        if (!hasAnalysis)
            prepareAnalysis();
        auto query = analyzed;
        auto root = expressionNode(query, expression);
        query.appendFacts(root);
        return emitExpression(query, root);
    }

    void configureRecords(alias Selector)() nothrow {
        static if (!is(Selector == void)) {
            static assert(__traits(compiles, { uint function(string) @nogc nothrow pure fn = &Selector; }),
                    "Compact selectors must be pure @nogc nothrow uint functions");
            foreach (rule; rules)
                recordKinds ~= Selector(name ~ "." ~ rule.name);
        }
    }

    string emit() nothrow {
        prepareAnalysis();
        foreach (i, ref rule; rules)
            rule.body = emitExpression(analyzed, analyzed.roots[i]);
        bool actionGrammar;
        foreach (rule; rules)
            foreach (i; 0 .. rule.body.length)
                if (startsWith(rule.body[i .. $], "action!("))
                    actionGrammar = true;
        string result = "struct " ~ name ~ params ~ " {\n";
        if (recordKinds.length) {
            result ~= "enum string[] compactRuleNames = [";
            foreach (i, rule; rules)
                result ~= (i ? ", " : "") ~ quoted(name ~ "." ~ rule.name);
            result ~= "];\nenum uint[] compactRuleKinds = [";
            foreach (i, kind; recordKinds)
                result ~= (i ? ", " : "") ~ number(kind);
            result ~= "];\n";
        }
        bool[] recordLeaves;
        if (recordKinds.length)
            recordLeaves = analyzed.selectedLeaves(recordKinds);
        bool spacingDefined;
        foreach (rule; rules)
            if (rule.name == "Spacing")
                spacingDefined = true;
        if (!spacingDefined)
            result ~= "alias Spacing = npegged.peg.spacing;\n";
        foreach (ruleIndex, rule; rules) {
            bool cache = memoize && (!selective || analyzed.conservative || analyzed.leftRecursive[ruleIndex]);
            if (params.length || rule.params.length)
                cache = memoize;
            string recordTag;
            if (recordKinds.length)
                recordTag = ", " ~ (recordKinds[ruleIndex] == uint.max
                        ? "-2" : number(cast(ulong)recordKinds[ruleIndex] | (recordLeaves[ruleIndex]
                            ? 1UL << 32 : 0UL)) ~ "L");
            if (rule.params.length)
                result ~= "template " ~ rule.name ~ rule.params ~ " {\n";
            string r = rule.name;
            string entryName = rule.params.length ? "_entry" : r;
            result ~= "private static State!(CT, Check).Node _" ~ r ~ "(bool CT, int Check = 0)(ref State!(CT, Check) s, size_t p) nothrow { return defined!(" ~ rule
                .body ~ ", " ~ quoted(name ~ "." ~ r) ~ ")(s,p); }\n";
            // Concrete overloads break recursive attribute-inference cycles.
            foreach (mode; [
                "false, false", "true, false", "false, true", "true, true", "false, 2", "true, 2"
            ]) {
                auto attributes = !startsWith(mode, "true") ? " @nogc nothrow" : " nothrow";
                result ~= "static State!(" ~ mode ~ ").Node " ~ entryName ~ (startsWith(mode, "true")
                        ? "(CompileTime = void)" : "") ~ "(ref State!(" ~ mode ~ ") s, size_t p)" ~ attributes;
                if (actionGrammar && (mode != "false, false" && mode != "true, false"))
                    result ~= " { return s.treeFallback!(" ~ entryName ~ ")(p); }\n";
                else
                    result ~= " { return s.rule!(_" ~ r ~ "!(" ~ mode ~ "), " ~ quoted(
                            name ~ "." ~ r) ~ ", " ~ (cache ? "true" : "false") ~ recordTag ~ ")(p); }\n";
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
            foreach (mode; [
                "false, false", "true, false", "false, true", "true, true", "false, 2", "true, 2"
            ]) {
                result ~= "static State!(" ~ mode ~ ").Node opCall" ~ (startsWith(mode, "true")
                        ? "(CompileTime = void)" : "") ~ "(ref State!(" ~ mode ~ ") s, size_t p)" ~ (
                        !startsWith(mode, "true") ? " @nogc" : "") ~ " nothrow { auto t = " ~ first
                    ~ "(s,p); " ~ ((mode != "false, false" && mode != "true, false")
                            ? "" : "t.name = " ~ quoted(name) ~ "; ") ~ "return t; }\n";
            }
            result ~= "static ParseResult opCall(Context)(ref Context ctx, string input) @nogc nothrow if (is(Context == ParseContext)) { return parse!(opCall)(ctx,input); }\n";
            result ~= "static ParseTree opCall(Input)(Input input) nothrow if (is(Input == string)) { return parseCT!(opCall)(input); }\n";
        }
        result ~= "}\n";
        return result;
    }
}

nothrow unittest {
    Frontend parser;
    parser.input = "ChoiceTest: Term <- Add / Sub Add <- '+' Term Sub <- '-' Term Cycle <- Cycle";
    parser.read();
    assert(!parser.error.message.length);
    auto emitted = parser.emit();
    assert(startsWith(parser.rules[0].body, "predictiveChoice!("));

    // Test computeFirstSet
    auto firstAdd = parser.computeFirstSet("Add");
    assert(firstAdd.known && !firstAdd.canBeEmpty && firstAdd.mask.contains('+'));
    auto firstSub = parser.computeFirstSet("Sub");
    assert(firstSub.known && !firstSub.canBeEmpty && firstSub.mask.contains('-'));
    assert(!firstAdd.mask.intersects(firstSub.mask));

    // Test literals and escapes in computeFirstSet
    assert(parser.computeFirstSet(`literal!("\n")`).mask.contains('\n'));
    assert(parser.computeFirstSet(`literal!("\r")`).mask.contains('\r'));
    assert(parser.computeFirstSet(`literal!("\t")`).mask.contains('\t'));
    assert(parser.computeFirstSet(`literal!("\0")`).mask.contains('\0'));
    assert(parser.computeFirstSet(`literal!("\\")`).mask.contains('\\'));
    assert(parser.computeFirstSet(`literal!("\"")`).mask.contains('"'));
    assert(parser.computeFirstSet(`literal!("foo")`).mask.contains('f'));
    assert(parser.computeFirstSet(`literal!("")`).canBeEmpty);
    assert(!parser.computeFirstSet(`literal!(`).known);

    // Test charRange
    assert(parser.computeFirstSet("charRange!(97, 122)").mask.contains('a'));
    assert(!parser.computeFirstSet("charRange!(300, 400)").known);
    assert(!parser.computeFirstSet("charRange!(100, 50)").known);
    assert(!parser.computeFirstSet("charRange!(invalid)").known);

    // Test charClass
    assert(parser.computeFirstSet("charClass!(0x1UL, 0x2UL, 0x3UL, 0x4UL)").known);
    assert(parser.computeFirstSet("charClass!(10UL, 20UL, 30UL, 40UL)").known);
    assert(!parser.computeFirstSet("charClass!(invalid)").known);

    // Test combinator unwrapping
    assert(parser.computeFirstSet(`and!(literal!("a"), literal!("b"))`).mask.contains('a'));
    assert(parser.computeFirstSet(`discard!(literal!("a"))`).mask.contains('a'));
    assert(parser.computeFirstSet(`fuse!(literal!("b"))`).mask.contains('b'));
    assert(parser.computeFirstSet(`keep!(literal!("c"))`).mask.contains('c'));
    assert(parser.computeFirstSet(`drop!(literal!("d"))`).mask.contains('d'));
    assert(parser.computeFirstSet(`oneOrMore!(literal!("e"))`).mask.contains('e'));

    // Test predefined symbols
    assert(parser.computeFirstSet("digit").mask.contains('5'));
    assert(parser.computeFirstSet("alpha").mask.contains('k'));
    assert(parser.computeFirstSet("Alpha").mask.contains('K'));
    assert(parser.computeFirstSet("hexDigit").mask.contains('f'));
    assert(parser.computeFirstSet("space").mask.contains(' '));
    assert(parser.computeFirstSet("blank").mask.contains('\n'));
    assert(parser.computeFirstSet("ident").mask.contains('_'));
    assert(parser.computeFirstSet("identifier").mask.contains('_'));
    assert(!parser.computeFirstSet("nonExistentRule").known);
    assert(!parser.computeFirstSet("Cycle").known); // recursion guard

    // Test splitTemplateArgs
    auto args = Frontend.splitTemplateArgs(`A, and!(B, C), literal!(",")`);
    assert(args.length == 3);

    // Test optimizeChoice
    assert(parser.optimizeChoice(["A"]) is null); // less than 2
    assert(parser.optimizeChoice(["unknown1", "unknown2"]) is null);

    // Test overlapping choice falls back to or
    Frontend overlap;
    overlap.input = "OverlapTest: Term <- 'a' 'b' / 'a' 'c'";
    overlap.read();
    assert(!overlap.error.message.length);
    auto emittedOverlap = overlap.emit();
    assert(startsWith(overlap.rules[0].body, "or!("));

    // Test character classes in primary
    Frontend charClasses;
    charClasses.input = "CharClasses: Single <- [a] ByteEsc <- [\\xFF] NonAscii <- [\\u03B1-\\u03C9] Mixed <- [a-z\\u03B1-\\u03C9] Empty <- []";
    charClasses.read();
    assert(!charClasses.error.message.length);
    auto emittedClasses = charClasses.emit();
    assert(emittedClasses.length > 0);

    assert(ulongHex(0x1234UL) == "0x1234UL");
    assert(ulongHex(0UL) == "0x0UL");

    Frontend opt;
    opt.input = "Opt: A <- 'a' / 'b' Single <- 'x'";
    opt.read();
    opt.emit();
    assert(opt.optimizeRule("or!(literal!('a'), literal!('b'))").length);
    assert(opt.optimizeRule("or!(literal!('a'), literal!('b'))").length);
    assert(opt.optimizeRule("longest_match!(literal!('a'), literal!('b'))").length);
    assert(opt.optimizeRule("predictiveChoice!(literal!('a'), literal!('b'))").length);
    assert(opt.optimizeRule("option!(literal!('a'))").length);
    assert(opt.optimizeRule("zeroOrMore!(literal!('a'))").length);
    assert(opt.optimizeRule("posLookahead!(literal!('a'))").length);
    assert(opt.optimizeRule("negLookahead!(literal!('a'))").length);
    assert(opt.optimizeRule("named!(literal!('a'), \"name\")").length);
    assert(opt.optimizeRule("branch!(literal!('a'), 0UL, 0UL, 0UL, 0UL)").length);
    assert(opt.optimizeRule("eps").length);
    assert(opt.optimizeRule("eoi").length);
    assert(opt.optimizeRule("endOfInput").length);
    assert(opt.optimizeRule("fail").length);
    assert(opt.optimizeRule("any").length);
    assert(opt.optimizeRule("spacing").length);
    assert(opt.optimizeRule("doublequote").length);
    assert(opt.optimizeRule("backslash").length);
    assert(opt.optimizeRule("quote").length);
    assert(opt.optimizeRule("slash").length);
    assert(opt.optimizeRule("backquote").length);
    assert(opt.optimizeRule("tab").length);
    assert(opt.optimizeRule("endOfLine").length);
    assert(opt.optimizeRule("eol").length);
    assert(opt.primitiveFirstSet("  literal!(\"a\")  ").known);
    assert(opt.primitiveFirstSet("literal!(\"\")").canBeEmpty);
    assert(opt.primitiveFirstSet("charClass!(0x1UL, 0X2UL, 3UL, 4UL)").known);
    assert(opt.primitiveFirstSet("charRange!(  10 ,  20 )").known);
    assert(Frontend.splitTemplateArgs(`"\\", a`).length == 2);
    assert(Frontend.splitTemplateArgs("a, b").length == 2);

    Frontend aheadTest;
    aheadTest.input = "DefAhead: Rule(T = ')') <- 'a' Other <- Rule";
    aheadTest.read();
    assert(!aheadTest.error.message.length);
    assert(aheadTest.emit().length);
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
string grammar(Memoization memo = Memoization.yes, alias Selector = void)(string definition) nothrow {
    Frontend frontend;
    frontend.input = definition;
    frontend.memoize = memo != Memoization.no;
    frontend.selective = memo == Memoization.selective;
    frontend.read();
    if (frontend.error.message.length)
        return "static assert(false, " ~ quoted(
                frontend.error.message ~ " at byte " ~ number(frontend.error.offset)) ~ ");";
    frontend.configureRecords!Selector();
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

@nogc nothrow unittest {
    ParseContext context;
    foreach (input; ["1+2+3", "x", "1+"]) {
        auto tree = RuntimeTest(context, input);
        auto recognized = check!(RuntimeTest.opCall)(context, input);
        assert(recognized.status == tree.status);
        assert(recognized.successful == tree.successful && recognized.end == tree.end);
        assert(recognized.failEnd == tree.failEnd);
    }
    context.depthLimit = 0;
    assert(check!(RuntimeTest.opCall)(context, "1").status == Status.resourceLimit);
    context = ParseContext.init;
    context.memoryLimit = 0;
    assert(check!(RuntimeTest.opCall)(context, "1").status == Status.resourceLimit);
}

version (unittest) private ParseTree countAction(bool CT)(ref State!CT state, ParseTree tree) nothrow {
    ++*cast(size_t*)state.context.userData;
    return tree;
}

version (unittest) mixin(grammar(`ActionRecognition: Root <- (Root 'a' / 'a'){countAction}`));
version (unittest) mixin(grammar(`PredicateAction: Root <- (&('a'{countAction}) 'a' / 'b') eoi`));
version (unittest) mixin(grammar!(Memoization.selective)(`SelectiveAction: Root <- (Root 'a' / 'a'){countAction}`));

@nogc nothrow unittest {
    ParseContext context;
    size_t calls;
    context.userData = &calls;
    auto tree = ActionRecognition(context, "aaa");
    const treeCalls = calls;
    calls = 0;
    auto recognized = check!(ActionRecognition.opCall)(context, "aaa");
    assert(recognized.successful == tree.successful && recognized.end == tree.end);
    assert(calls == treeCalls && calls > 0);
    calls = 0;
    auto selected = check!(SelectiveAction.opCall)(context, "aaa");
    assert(selected.successful && selected.end == tree.end);
    assert(calls == treeCalls && selected.arena.allocationCalls > 0);
}

@nogc nothrow unittest {
    ParseContext context;
    size_t calls;
    context.userData = &calls;
    auto tree = PredicateAction(context, "b");
    assert(tree.successful && calls == 1);
    calls = 0;
    auto recognized = check!(PredicateAction.opCall)(context, "b");
    assert(recognized.successful && calls == 1);
}

version (unittest) mixin(grammar!(Memoization.selective)(`
SelectiveLeft:
    Root <- Expr eoi
    Expr <- Expr '+' Number / Number
    Number <~ [0-9]+
`));
version (unittest) mixin(grammar!(Memoization.selective)(`
SelectiveNested:
    Root <- '(' Root ')' / 'x'
`));
version (unittest) mixin(grammar!(Memoization.selective)(`
SelectiveHidden:
    Root <- Prefix? Root 'a' / 'a'
    Prefix <- 'b'
`));

@nogc nothrow unittest {
    ParseContext context;
    foreach (input; ["1+2+3", "x", "1+"]) {
        auto full = RuntimeTest(context, input);
        auto selected = SelectiveLeft.Expr(context, input);
        assert(selected.successful == full.successful && selected.end == full.end);
        auto recognized = check!(SelectiveLeft.Expr)(context, input);
        assert(recognized.successful == selected.successful && recognized.end == selected.end);
    }
    auto nested = check!(SelectiveNested.opCall)(context, "(((x)))");
    assert(nested.successful && nested.end == 7 && nested.arena.allocationCalls == 0);
    auto hidden = check!(SelectiveHidden.opCall)(context, "aaaa");
    assert(hidden.successful && hidden.end == 4 && hidden.arena.allocationCalls > 0);
}

unittest {
    Frontend graph;
    graph.input = "Test: A <- B? C B <- 'b' C <- 'c'";
    graph.read();
    auto first = graph.computeFirstSet("A");
    assert(first.known && !first.canBeEmpty && first.mask.contains('b') && first.mask.contains('c'));
    assert(!graph.computeFirstSet("charRange!(128, 255)").known);
    assert(graph.optimizeRule(`literal!("or!(x)")`) == `literal!("or!(x)")`);
    auto args = Frontend.splitTemplateArgs(`literal!("\\"), literal!("a")`);
    assert(args.length == 2);
    auto selected = grammar!(Memoization.selective)("Nested: A <- '(' A ')' / 'x'");
    assert(selected.length);
}

version (unittest) private uint compactTag(string name) @nogc nothrow pure {
    if (name.length >= 5 && name[$ - 5 .. $] == ".Root")
        return 0;
    if (name.length >= 5 && name[$ - 5 .. $] == ".Leaf")
        return 1;
    if (name.length >= 8 && name[$ - 8 .. $] == ".Ignored")
        return uint.max;
    return 2;
}

version (unittest) mixin(grammar!(Memoization.selective)(`
RecordNested:
    Root <- Ignored Branch eoi
    Ignored <: ' '?
    Branch <- '[' Leaf (',' Leaf)* ']'
    Leaf <~ [a-z]+
`));
version (unittest) mixin(grammar!(Memoization.yes, compactTag)(`
RecordBacktrack:
    Root <- (Branch / Leaf) eoi
    Branch <- Leaf ':' Leaf
    Leaf <~ [a-z]+
`));
version (unittest) mixin(grammar(`
RecordPredicate:
    Root <- &Branch Branch eoi
    Branch <- Leaf
    Leaf <~ [a-z]+
`));
version (unittest) mixin(grammar!(Memoization.selective)(`
RecordLeft:
    Root <- Expr eoi
    Expr <- Expr '+' Leaf / Leaf
    Leaf <~ [0-9]+
`));
version (unittest) mixin(grammar!(Memoization.yes, compactTag)(`
RecordLongest:
    Root <- (Short | Long) eoi
    Short <- Leaf
    Long <- Leaf Leaf
    Leaf <- [a-z]
`));
version (unittest) mixin(grammar(`
RecordAction:
    Root <- Branch eoi
    Branch <- Leaf {countAction}
    Leaf <~ [a-z]+
`));

@nogc nothrow unittest {
    ParseContext context;
    auto nested = parseRecords!(RecordNested.opCall, compactTag)(context, "[a,b]");
    assert(nested.successful && nested.nodes.length == 4);
    assert(nested.nodes[0] == CompactNode(0, 0, 5));
    assert(nested.nodes[1] == CompactNode(2, 0, 5, 0));
    assert(nested.nodes[2] == CompactNode(1, 1, 2, 1));
    assert(nested.nodes[3] == CompactNode(1, 3, 4, 1));
    auto backtrack = parseRecords!(RecordBacktrack.opCall, compactTag)(context, "a");
    assert(backtrack.successful && backtrack.nodes.length == 2);
    assert(backtrack.nodes[1] == CompactNode(1, 0, 1, 0));
    auto predicate = parseRecords!(RecordPredicate.opCall, compactTag)(context, "abc");
    assert(predicate.successful && predicate.nodes.length == 3);
    assert(predicate.nodes[1] == CompactNode(2, 0, 3, 0));
    assert(predicate.nodes[2] == CompactNode(1, 0, 3, 1));
    auto left = parseRecords!(RecordLeft.opCall, compactTag)(context, "1+2+3");
    assert(left.successful && left.nodes.length == 7);
    assert(left.nodes[4] == CompactNode(1, 0, 1, 3));
    assert(left.nodes[5] == CompactNode(1, 2, 3, 2));
    assert(left.nodes[6] == CompactNode(1, 4, 5, 1));
    auto longest = parseRecords!(RecordLongest.opCall, compactTag)(context, "ab");
    assert(longest.successful && longest.nodes.length == 4);
    assert(longest.nodes[1] == CompactNode(2, 0, 2, 0));
    assert(longest.nodes[2] == CompactNode(1, 0, 1, 1));
    assert(longest.nodes[3] == CompactNode(1, 1, 2, 1));
    size_t calls;
    context.userData = &calls;
    auto action = parseRecords!(RecordAction.opCall, compactTag)(context, "abc");
    assert(action.successful && calls == 1 && action.nodes.length == 3);
    assert(action.nodes[2] == CompactNode(1, 0, 3, 1));
    auto bad = parseRecords!(RecordNested.opCall, compactTag)(context, "[a,]");
    assert(!bad.successful && bad.status == Status.mismatch && bad.nodes.length == 0);
    auto limited = parseRecords!(RecordNested.opCall, compactTag)(context, "[a]", 0);
    assert(!limited.successful && limited.status == Status.resourceLimit && limited.nodes.length == 0);
    foreach (budget; 0 .. 100) {
        context = ParseContext.init;
        context.stepLimit = budget;
        auto trial = parseRecords!(RecordLeft.opCall, compactTag)(context, "1+2+3");
        assert(trial.status == Status.ok || trial.status == Status.resourceLimit);
        if (!trial.successful)
            assert(trial.nodes.length == 0);
    }
}

version (unittest) private uint wrongCompactTag(string name) @nogc nothrow pure {
    return uint.max;
}

version (unittest) enum staticRecordDefinition = `StaticRecords:
    Root <- Ignored &Leaf Leaf eoi
    Ignored <: ' '?
    Leaf <~ [a-z]+
`;
version (unittest) mixin(grammar!(Memoization.selective, compactTag)(staticRecordDefinition));

@nogc nothrow unittest {
    ParseContext context;
    auto result = parseRecords!(StaticRecords.opCall, compactTag, false)(context, " abc");
    assert(result.successful && result.nodes.length == 2 && result.input is null);
    assert(result.nodes[0] == CompactNode(0, 0, 4));
    assert(result.nodes[1] == CompactNode(1, 1, 4, 0));
    auto typeEntry = parseRecords!(StaticRecords, compactTag)(context, "abc");
    assert(typeEntry.successful && typeEntry.nodes.length == 2 && typeEntry.input == "abc");
    static assert(!__traits(compiles, parseRecords!(StaticRecords.opCall, wrongCompactTag)(context, "abc")));
    auto owned = parseRecords!(RecordNested.opCall, compactTag)(context, "[a,b]");
    auto borrowed = parseRecords!(RecordNested.opCall, compactTag, false)(context, "[a,b]");
    assert(owned.nodes == borrowed.nodes && borrowed.input is null);
    assert(borrowed.arena.allocationCalls == 0 && owned.arena.allocationCalls == 1);
    auto rejectedLeaf = parseRecords!(StaticRecords.Leaf, compactTag, false)(context, "!", 0);
    assert(rejectedLeaf.status == Status.mismatch && rejectedLeaf.outputArena.allocationCalls == 0);
    auto limitedLeaf = parseRecords!(StaticRecords.Leaf, compactTag, false)(context, "abc", 0);
    assert(limitedLeaf.status == Status.resourceLimit && limitedLeaf.nodes.length == 0);
    assert(limitedLeaf.end == 3);
    foreach (budget; 0 .. 60) {
        context.stepLimit = budget;
        auto checked = check!(StaticRecords.opCall)(context, " abc");
        auto captured = parseRecords!(StaticRecords.opCall, compactTag, false)(context, " abc");
        assert(captured.status == checked.status && captured.end == checked.end);
        assert(captured.failEnd == checked.failEnd);
        if (!captured.successful)
            assert(captured.nodes.length == 0);
    }
}

nothrow unittest {
    auto source = generate!(Memoization.selective, compactTag)(staticRecordDefinition);
    assert(source.status == Status.ok && source.source.length > 0);
}

version (unittest) private void countRecordTrace(string name, size_t pos, bool success, void* user) @nogc nothrow {
    ++*cast(size_t*)user;
}

version (unittest) mixin(grammar!(Memoization.selective, compactTag)(`
RecordLookLeft:
    Root <- Expr eoi
    Expr <- &Expr 'a' / 'a'
`));

@nogc nothrow unittest {
    ParseContext context;
    size_t calls;
    context.userData = &calls;
    context.trace = &countRecordTrace;
    auto checked = check!(RecordLookLeft.opCall)(context, "a");
    const expectedCalls = calls;
    assert(checked.successful && expectedCalls == 2);
    calls = 0;
    auto captured = parseRecords!(RecordLookLeft.opCall, compactTag)(context, "a");
    assert(captured.successful && captured.nodes.length == 2 && calls == expectedCalls);
    foreach (budget; 0 .. 24) {
        context.stepLimit = budget;
        calls = 0;
        auto reference = check!(RecordLookLeft.opCall)(context, "a");
        const referenceCalls = calls;
        calls = 0;
        auto candidate = parseRecords!(RecordLookLeft.opCall, compactTag)(context, "a");
        assert(candidate.status == reference.status && candidate.end == reference.end);
        assert(candidate.failEnd == reference.failEnd && calls == referenceCalls);
    }
}

version (unittest) mixin(grammar!(Memoization.selective, compactTag)(`
ShadowedBuiltin(digit = 'x'):
    Root <- digit / 'y'
`));
version (unittest) mixin(grammar!(Memoization.selective, compactTag)(`
ShadowedRule:
    Root <- Item('x')
    Item(digit = 'x') <- digit / 'y'
`));

@nogc nothrow unittest {
    ParseContext context;
    auto grammarParam = parseRecords!(ShadowedBuiltin!().opCall, compactTag)(context, "x");
    assert(grammarParam.successful && grammarParam.nodes.length == 1);
    auto ruleParam = parseRecords!(ShadowedRule.opCall, compactTag)(context, "x");
    assert(ruleParam.successful && ruleParam.nodes.length == 2);
    assert(check!(ShadowedBuiltin!().opCall)(context, "y").successful);
    assert(!check!(ShadowedBuiltin!().opCall)(context, "1").successful);
}

/// Cold runtime generation reports errors explicitly. Output uses selective druntime GC.
struct GenerationResult {
    Status status = Status.invalidInput;
    string source;
    Diagnostic diagnostic;
}

GenerationResult generate(Memoization memo = Memoization.yes, alias Selector = void)(
        string definition, string moduleName = "") nothrow {
    Frontend frontend;
    frontend.input = definition;
    frontend.memoize = memo != Memoization.no;
    frontend.selective = memo == Memoization.selective;
    frontend.read();
    if (frontend.error.message.length)
        return GenerationResult(Status.invalidInput, null, frontend.error);
    frontend.configureRecords!Selector();
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

Status asModule(Memoization memo = Memoization.yes, alias Selector = void)(string moduleName,
        string fileName, string definition, string header = "") nothrow {
    import npegged.io : File;

    auto result = generate!(memo, Selector)(definition);
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
string grammar(Memoization memo = Memoization.yes, alias Selector = void)(scope const ref ParseTree definition) nothrow {
    if (!definition.successful)
        return "static assert(false, `Cannot generate from a failed grammar parse`);";
    return grammar!(memo, Selector)(definition.input);
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
Status asModule(Memoization memo = Memoization.yes, alias Selector = void)(string moduleName,
        string destination, ref npegged.io.File input, string header = "") nothrow {
    import npegged.storage : Buffer;

    Buffer!char text;
    auto status = input.read(text);
    if (status != Status.ok)
        return status;
    return asModule!(memo, Selector)(moduleName, destination, cast(string)text.data, header);
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
