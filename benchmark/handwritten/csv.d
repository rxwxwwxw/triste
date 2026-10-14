module benchmark.handwritten.csv;

struct CsvParser {
    string src;
    size_t pos;

    static bool parse(string input) @nogc nothrow pure @safe {
        CsvParser p = CsvParser(input, 0);
        return p.parseCsvFile();
    }

    private void skipSpaces() @nogc nothrow pure @safe {
        while (pos < src.length && (src[pos] == ' ' || src[pos] == '\t')) {
            pos++;
        }
    }

    private bool isEndOfLine() const @nogc nothrow pure @safe {
        if (pos >= src.length)
            return false;
        return src[pos] == '\n' || src[pos] == '\r';
    }

    private bool consumeEndOfLine() @nogc nothrow pure @safe {
        if (pos >= src.length)
            return false;
        if (src[pos] == '\r') {
            pos++;
            if (pos < src.length && src[pos] == '\n')
                pos++;
            return true;
        }
        if (src[pos] == '\n') {
            pos++;
            return true;
        }
        return false;
    }

    private bool parseItem() @nogc nothrow pure @safe {
        if (pos < src.length && src[pos] == '"') {
            // QuotedField: doublequote EscapedField doublequote :S*
            pos++; // consume opening quote
            while (pos < src.length) {
                if (src[pos] == '"') {
                    if (pos + 1 < src.length && src[pos + 1] == '"') {
                        pos += 2; // escaped quote
                    } else {
                        pos++; // closing quote
                        skipSpaces();
                        return true;
                    }
                } else {
                    pos++;
                }
            }
            return false; // unterminated quote
        }

        // SimpleField: (!eoi !endOfLine !S !',' !doublequote .)+ :S*
        const size_t start = pos;
        while (pos < src.length && !isEndOfLine() && src[pos] != ' ' && src[pos] != '\t'
                && src[pos] != ',' && src[pos] != '"') {
            pos++;
        }
        if (pos > start) {
            skipSpaces();
            return true;
        }

        // EmptyField: eps :S*
        skipSpaces();
        return true;
    }

    private bool parseLineItems() @nogc nothrow pure @safe {
        skipSpaces();
        if (!parseItem())
            return false;
        while (pos < src.length && src[pos] == ',') {
            pos++; // consume ','
            skipSpaces();
            if (!parseItem())
                return false;
        }
        return true;
    }

    private bool parseCsvFile() @nogc nothrow pure @safe {
        if (src.length == 0)
            return true;

        while (pos < src.length) {
            if (!parseLineItems())
                return false;

            if (pos == src.length) {
                // LastLine eoi
                return true;
            }

            if (!consumeEndOfLine())
                return false;

            if (pos == src.length) {
                // Ended after trailing newline, last line was empty
                return true;
            }
        }
        return true;
    }
}

@nogc nothrow unittest {
    assert(CsvParser.parse(""));
    assert(CsvParser.parse("a,b,c"));
    assert(CsvParser.parse("1,2,3\n4,5,6"));
    assert(CsvParser.parse("id,name,role\n1,Alice,Engineer\n2,Bob,\"Manager, HQ\""));
    assert(CsvParser.parse(`"quoted, with comma","escaped ""quote""",simple,123`));

    enum multiLineCsv = "id,name,role,department,score\n"
        ~ "1,Alice_Smith,Engineer,Platform,94.5\n" ~ "2,Bob_Jones,Manager,\"Operations, HQ\",88.0\n"
        ~ "3,Charlie_Brown,Analyst,Data,91.2\n" ~ "4,Diana_Prince,Architect,\"Security & Trust\",99.0";
    assert(CsvParser.parse(multiLineCsv));

    // Unterminated quote should fail
    assert(!CsvParser.parse(`1,2,"unterminated quote`));
}
