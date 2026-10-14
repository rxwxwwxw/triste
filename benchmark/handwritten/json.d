module benchmark.handwritten.json;

enum TokenType : ubyte {
    eof,
    leftBrace,
    rightBrace,
    leftBracket,
    rightBracket,
    colon,
    comma,
    stringLit,
    number,
    kwTrue,
    kwFalse,
    kwNull,
    invalid
}

struct Token {
    TokenType type;
    string text;
}

private bool isDigit(char c) @nogc nothrow pure @safe {
    return c >= '0' && c <= '9';
}

private bool isHex(char c) @nogc nothrow pure @safe {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

private bool isSpace(char c) @nogc nothrow pure @safe {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

struct JsonLexer {
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

        if (c == '"') {
            pos++;
            while (pos < src.length) {
                if (src[pos] == '"') {
                    pos++;
                    return Token(TokenType.stringLit, src[start .. pos]);
                }
                if (src[pos] == '\\') {
                    pos++;
                    if (pos >= src.length)
                        return Token(TokenType.invalid, src[start .. pos]);
                    const char esc = src[pos];
                    if (esc == '"' || esc == '\\' || esc == '/' || esc == 'b' || esc == 'f' || esc == 'n'
                            || esc == 'r' || esc == 't') {
                        pos++;
                    } else if (esc == 'u') {
                        pos++;
                        for (size_t k = 0; k < 4; ++k) {
                            if (pos >= src.length || !isHex(src[pos]))
                                return Token(TokenType.invalid, src[start .. pos]);
                            pos++;
                        }
                    } else {
                        pos++;
                    }
                } else {
                    pos++;
                }
            }
            return Token(TokenType.invalid, src[start .. pos]);
        }

        if (c == '-' || isDigit(c)) {
            if (c == '-')
                pos++;
            if (pos >= src.length)
                return Token(TokenType.invalid, src[start .. pos]);
            if (src[pos] == '0') {
                pos++;
            } else if (isDigit(src[pos])) {
                while (pos < src.length && isDigit(src[pos])) {
                    pos++;
                }
            } else {
                return Token(TokenType.invalid, src[start .. pos]);
            }

            if (pos < src.length && src[pos] == '.') {
                pos++;
                if (pos >= src.length || !isDigit(src[pos]))
                    return Token(TokenType.invalid, src[start .. pos]);
                while (pos < src.length && isDigit(src[pos])) {
                    pos++;
                }
            }

            if (pos < src.length && (src[pos] == 'e' || src[pos] == 'E')) {
                pos++;
                if (pos < src.length && (src[pos] == '+' || src[pos] == '-'))
                    pos++;
                if (pos >= src.length || !isDigit(src[pos]))
                    return Token(TokenType.invalid, src[start .. pos]);
                while (pos < src.length && isDigit(src[pos])) {
                    pos++;
                }
            }

            return Token(TokenType.number, src[start .. pos]);
        }

        if (pos + 4 <= src.length && src[pos .. pos + 4] == "true") {
            pos += 4;
            return Token(TokenType.kwTrue, src[start .. pos]);
        }
        if (pos + 5 <= src.length && src[pos .. pos + 5] == "false") {
            pos += 5;
            return Token(TokenType.kwFalse, src[start .. pos]);
        }
        if (pos + 4 <= src.length && src[pos .. pos + 4] == "null") {
            pos += 4;
            return Token(TokenType.kwNull, src[start .. pos]);
        }

        pos++;
        switch (c) {
        case '{':
            return Token(TokenType.leftBrace, src[start .. pos]);
        case '}':
            return Token(TokenType.rightBrace, src[start .. pos]);
        case '[':
            return Token(TokenType.leftBracket, src[start .. pos]);
        case ']':
            return Token(TokenType.rightBracket, src[start .. pos]);
        case ':':
            return Token(TokenType.colon, src[start .. pos]);
        case ',':
            return Token(TokenType.comma, src[start .. pos]);
        default:
            return Token(TokenType.invalid, src[start .. pos]);
        }
    }
}

struct JsonParser {
    private JsonLexer lexer;
    private Token current;

    static bool parse(string input) @nogc nothrow pure @safe {
        JsonParser p;
        p.lexer = JsonLexer(input, 0);
        p.advance();
        if (!p.parseValue())
            return false;
        return p.current.type == TokenType.eof;
    }

    private void advance() @nogc nothrow pure @safe {
        current = lexer.nextToken();
    }

    private bool parseValue() @nogc nothrow pure @safe {
        switch (current.type) {
        case TokenType.leftBrace:
            return parseObject();
        case TokenType.leftBracket:
            return parseArray();
        case TokenType.stringLit:
        case TokenType.number:
        case TokenType.kwTrue:
        case TokenType.kwFalse:
        case TokenType.kwNull:
            advance();
            return true;
        default:
            return false;
        }
    }

    private bool parseObject() @nogc nothrow pure @safe {
        advance(); // consume '{'
        if (current.type == TokenType.rightBrace) {
            advance();
            return true;
        }

        while (true) {
            if (current.type != TokenType.stringLit)
                return false;
            advance(); // consume key

            if (current.type != TokenType.colon)
                return false;
            advance(); // consume ':'

            if (!parseValue())
                return false;

            if (current.type == TokenType.comma) {
                advance();
                // Trailing comma before '}' is not valid JSON
                if (current.type == TokenType.rightBrace)
                    return false;
            } else if (current.type == TokenType.rightBrace) {
                advance();
                return true;
            } else {
                return false;
            }
        }
    }

    private bool parseArray() @nogc nothrow pure @safe {
        advance(); // consume '['
        if (current.type == TokenType.rightBracket) {
            advance();
            return true;
        }

        while (true) {
            if (!parseValue())
                return false;

            if (current.type == TokenType.comma) {
                advance();
                if (current.type == TokenType.rightBracket)
                    return false;
            } else if (current.type == TokenType.rightBracket) {
                advance();
                return true;
            } else {
                return false;
            }
        }
    }
}

@nogc nothrow unittest {
    assert(JsonParser.parse("{}"));
    assert(JsonParser.parse("[]"));
    assert(JsonParser.parse(`{"key": "value"}`));
    assert(JsonParser.parse(`{"a": 1, "b": true, "c": false, "d": null}`));
    assert(JsonParser.parse(`[1, 2, "three", true, null, {"nested": [4, 5]}]`));
    assert(JsonParser.parse(`{"name": "test", "id": 12345, "active": true, "score": 98.6}`));

    enum complexJson = `{
  "project": "triste",
  "version": 1,
  "tags": ["druntime", "nogc", "parser", "peg"],
  "maintainers": [
    {"name": "Alex", "role": "lead", "active": true, "commits": 120},
    {"name": "Agent", "role": "pair", "active": false, "commits": 45}
  ],
  "meta": {"created": 2026, "verified": true, "score": 0.995}
}`;
    assert(JsonParser.parse(complexJson));

    assert(!JsonParser.parse(""));
    assert(!JsonParser.parse("{"));
    assert(!JsonParser.parse(`{"missing_colon" "val"}`));
    assert(!JsonParser.parse(`{"trailing_comma": 1,}`));
    assert(!JsonParser.parse(`[1, 2,]`));
}
