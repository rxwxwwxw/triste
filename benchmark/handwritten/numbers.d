module benchmark.handwritten.numbers;

private bool isDigit(char c) @nogc nothrow pure @safe {
    return c >= '0' && c <= '9';
}

private bool isHexDigit(char c) @nogc nothrow pure @safe {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

private bool isBinaryDigit(char c) @nogc nothrow pure @safe {
    return c == '0' || c == '1';
}

struct NumbersParser {
    static bool parseScientific(string s) @nogc nothrow pure @safe {
        if (s.length == 0)
            return false;

        size_t pos = 0;

        // Sign?
        if (s[pos] == '-' || s[pos] == '+') {
            pos++;
            if (pos >= s.length)
                return false;
        }

        // Unsigned ([0-9]+)
        if (!isDigit(s[pos]))
            return false;
        while (pos < s.length && isDigit(s[pos])) {
            pos++;
        }

        // ('.' Unsigned)?
        if (pos < s.length && s[pos] == '.') {
            pos++;
            if (pos >= s.length || !isDigit(s[pos]))
                return false;
            while (pos < s.length && isDigit(s[pos])) {
                pos++;
            }
        }

        // ( ('e' / 'E') Integer )?
        if (pos < s.length && (s[pos] == 'e' || s[pos] == 'E')) {
            pos++;
            if (pos >= s.length)
                return false;
            // Integer: Sign? Unsigned
            if (s[pos] == '-' || s[pos] == '+') {
                pos++;
                if (pos >= s.length)
                    return false;
            }
            if (!isDigit(s[pos]))
                return false;
            while (pos < s.length && isDigit(s[pos])) {
                pos++;
            }
        }

        return pos == s.length;
    }

    static bool parseHexa(string s) @nogc nothrow pure @safe {
        if (s.length == 0)
            return false;
        foreach (char c; s) {
            if (!isHexDigit(c))
                return false;
        }
        return true;
    }

    static bool parseBinary(string s) @nogc nothrow pure @safe {
        if (s.length < 3 || s[0 .. 2] != "0b")
            return false;
        if (!isBinaryDigit(s[2]))
            return false;
        for (size_t i = 3; i < s.length; ++i) {
            if (!isBinaryDigit(s[i]) && s[i] != '_')
                return false;
        }
        return true;
    }
}

@nogc nothrow unittest {
    static immutable string[] validScientific = [
        "0", "0.0", "0.01", "-0", "+0", "-0.0", "+0.0", "0", "1", "2", "3", "4", "5", "6", "7",
        "8", "9", "0123456789", "123", "123.0", "123.01", "-123", "-123.0", "-123.01", "-123e+12",
        "-123e-12", "+123e+12", "+123e-12", "-123E+12", "-123E-12", "+123E+12", "+123E-12",
        "123.456e+00", "123.456E+00", "123.456e-00", "123.456E-00", "-123.456e+00",
        "-123.456E+00", "-123.456e-00",
        "-123.456E-00", "+123.456e+00", "+123.456E+00", "+123.456e-00", "+123.456E-00"
    ];
    foreach (num; validScientific) {
        assert(NumbersParser.parseScientific(num), num);
    }

    static immutable string[] invalidScientific = [
        ".", ".0", "0.", "123..456", "", "abc", "+", "-", "+.", "-.", "--1", "++1", "+-1", "-+1",
        "1e", "1e+", "1e-", "1ee"
    ];
    foreach (num; invalidScientific) {
        assert(!NumbersParser.parseScientific(num), num);
    }

    assert(NumbersParser.parseHexa("0123456789ABCDEF"));
    assert(NumbersParser.parseHexa("deadbeef"));
    assert(!NumbersParser.parseHexa(""));
    assert(!NumbersParser.parseHexa("0x123"));

    assert(NumbersParser.parseBinary("0b0"));
    assert(NumbersParser.parseBinary("0b1010_0101"));
    assert(!NumbersParser.parseBinary("0b"));
    assert(!NumbersParser.parseBinary("1010"));
}
