module benchmark.handwritten.arithmetic;

enum TokenType : ubyte {
    eof,
    number,
    identifier,
    plus,
    minus,
    star,
    slash,
    openParen,
    closeParen,
    invalid
}

struct Token {
    TokenType type;
    string text;
}

private bool isDigit(char c) @nogc nothrow pure @safe {
    return c >= '0' && c <= '9';
}

private bool isAlpha(char c) @nogc nothrow pure @safe {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

private bool isAlphaNum(char c) @nogc nothrow pure @safe {
    return isAlpha(c) || isDigit(c);
}

private bool isSpace(char c) @nogc nothrow pure @safe {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

struct ArithmeticLexer {
    string src;
    size_t pos;

    Token nextToken() @nogc nothrow pure @safe {
        while (pos < src.length && isSpace(src[pos])) {
            pos++;
        }
        if (pos >= src.length) {
            return Token(TokenType.eof, src[pos .. pos]);
        }

        const char c = src[pos];
        const size_t start = pos;

        if (isDigit(c)) {
            while (pos < src.length && isDigit(src[pos])) {
                pos++;
            }
            if (pos < src.length && src[pos] == '.' && pos + 1 < src.length && isDigit(src[pos + 1])) {
                pos++;
                while (pos < src.length && isDigit(src[pos])) {
                    pos++;
                }
            }
            return Token(TokenType.number, src[start .. pos]);
        }

        if (isAlpha(c)) {
            while (pos < src.length && isAlphaNum(src[pos])) {
                pos++;
            }
            return Token(TokenType.identifier, src[start .. pos]);
        }

        pos++;
        switch (c) {
        case '+':
            return Token(TokenType.plus, src[start .. pos]);
        case '-':
            return Token(TokenType.minus, src[start .. pos]);
        case '*':
            return Token(TokenType.star, src[start .. pos]);
        case '/':
            return Token(TokenType.slash, src[start .. pos]);
        case '(':
            return Token(TokenType.openParen, src[start .. pos]);
        case ')':
            return Token(TokenType.closeParen, src[start .. pos]);
        default:
            return Token(TokenType.invalid, src[start .. pos]);
        }
    }
}

struct ArithmeticParser {
    private ArithmeticLexer lexer;
    private Token current;

    static bool parse(string input) @nogc nothrow pure @safe {
        ArithmeticParser p;
        p.lexer = ArithmeticLexer(input, 0);
        p.advance();
        if (!p.parseTerm())
            return false;
        return p.current.type == TokenType.eof;
    }

    private void advance() @nogc nothrow pure @safe {
        current = lexer.nextToken();
    }

    private bool parseTerm() @nogc nothrow pure @safe {
        if (!parseFactor())
            return false;
        while (current.type == TokenType.plus || current.type == TokenType.minus) {
            advance();
            if (!parseFactor())
                return false;
        }
        return true;
    }

    private bool parseFactor() @nogc nothrow pure @safe {
        if (!parsePrimary())
            return false;
        while (current.type == TokenType.star || current.type == TokenType.slash) {
            advance();
            if (!parsePrimary())
                return false;
        }
        return true;
    }

    private bool parsePrimary() @nogc nothrow pure @safe {
        if (current.type == TokenType.openParen) {
            advance();
            if (!parseTerm())
                return false;
            if (current.type != TokenType.closeParen)
                return false;
            advance();
            return true;
        }
        if (current.type == TokenType.minus || current.type == TokenType.plus) {
            advance();
            return parsePrimary();
        }
        if (current.type == TokenType.number || current.type == TokenType.identifier) {
            advance();
            return true;
        }
        return false;
    }
}

@nogc nothrow unittest {
    assert(ArithmeticParser.parse("1"));
    assert(ArithmeticParser.parse("1 + 2"));
    assert(ArithmeticParser.parse("1 + 2 * (3 - 4)"));
    assert(ArithmeticParser.parse("1 + 2 * (3 + 10 / 4) - (5 * 6 + 7) * (8 - 9 / (2 + 3))"));
    assert(ArithmeticParser.parse(
            "(((1 + 2) * 3 - 4) / 5 + (6 * (7 - 8))) * (((9 + 10) * 11 - 12) / 13 + (14 * (15 - 16)))"));
    assert(ArithmeticParser.parse("var1 + -var2 * +3"));

    assert(!ArithmeticParser.parse(""));
    assert(!ArithmeticParser.parse("1 +"));
    assert(!ArithmeticParser.parse("(1 + 2"));
    assert(!ArithmeticParser.parse("1 + * 2"));
    assert(!ArithmeticParser.parse("1 + 2)"));
}
