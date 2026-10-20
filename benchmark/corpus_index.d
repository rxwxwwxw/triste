module benchmark.corpus_index;

/// Q2: one row of performance/corpora/index.tsv (name, family, label, valid, bytes, sha256, path).
struct CorpusRow {
    string name, family, label, path;
    bool valid;
    size_t bytes;
}

/// Splits one tab-separated line into the seven index columns; false for a malformed row.
bool parseCorpusRow(string line, ref CorpusRow row) @nogc nothrow pure {
    string[7] cells;
    size_t count, begin;
    foreach (i; 0 .. line.length + 1) {
        if (i == line.length || line[i] == '\t') {
            if (count == 7)
                return false;
            cells[count++] = line[begin .. i];
            begin = i + 1;
        }
    }
    if (count != 7 || !cells[0].length || !cells[6].length || cells[3].length != 1
            || cells[3][0] != '0' && cells[3][0] != '1')
        return false;
    size_t bytes;
    foreach (c; cells[4]) {
        if (c < '0' || c > '9')
            return false;
        bytes = bytes * 10 + (c - '0');
    }
    if (!cells[4].length)
        return false;
    row = CorpusRow(cells[0], cells[1], cells[2], cells[6], cells[3][0] == '1', bytes);
    return true;
}

@nogc nothrow pure unittest {
    CorpusRow row;
    assert(parseCorpusRow("n\tjson\treal\t1\t12\tdeadbeef\tp/q.txt", row));
    assert(row.name == "n" && row.family == "json" && row.label == "real" && row.valid && row.bytes == 12
            && row.path == "p/q.txt");
    assert(parseCorpusRow("n\tcsv\tsynthetic\t0\t0\td\tp", row) && !row.valid && row.bytes == 0);
    assert(!parseCorpusRow("", row) && !parseCorpusRow("a\tb", row));
    assert(!parseCorpusRow("n\tjson\treal\t2\t12\td\tp", row));
    assert(!parseCorpusRow("n\tjson\treal\t1\tx\td\tp", row));
    assert(!parseCorpusRow("n\tjson\treal\t1\t\td\tp", row));
    assert(!parseCorpusRow("n\tjson\treal\t1\t1\td\tp\textra", row));
    assert(!parseCorpusRow("\tjson\treal\t1\t1\td\tp", row));
}

/// Whole file as a string, or null when it cannot be opened or read completely.
string readWholeFile(string path) {
    import core.stdc.stdio : FILE, fopen, fclose, fread, fseek, ftell, SEEK_END, SEEK_SET;

    auto terminated = new char[path.length + 1];
    terminated[0 .. path.length] = path[];
    terminated[path.length] = 0;
    FILE* file = fopen(terminated.ptr, "rb");
    if (file is null)
        return null;
    scope (exit)
        fclose(file);
    if (fseek(file, 0, SEEK_END) != 0)
        return null;
    const size = ftell(file);
    if (size < 0 || fseek(file, 0, SEEK_SET) != 0)
        return null;
    auto data = new char[cast(size_t)size];
    if (data.length && fread(data.ptr, 1, data.length, file) != data.length)
        return null;
    return cast(string)data;
}

unittest {
    assert(readWholeFile("performance/corpora/does-not-exist.tsv") is null);
    const index = readWholeFile("performance/corpora/index.tsv");
    assert(index.length > 100 && index[0 .. 5] == "name\t");
}

/// Strict UTF-8 (no overlongs, surrogates or code points above U+10FFFF).
bool isValidUtf8(scope const(char)[] text) @nogc nothrow pure {
    size_t i;
    while (i < text.length) {
        const first = cast(ubyte)text[i];
        size_t extra;
        uint minimum, value;
        if (first < 0x80) {
            ++i;
            continue;
        } else if (first >= 0xC2 && first <= 0xDF) {
            extra = 1;
            minimum = 0x80;
            value = first & 0x1F;
        } else if (first >= 0xE0 && first <= 0xEF) {
            extra = 2;
            minimum = 0x800;
            value = first & 0x0F;
        } else if (first >= 0xF0 && first <= 0xF4) {
            extra = 3;
            minimum = 0x10000;
            value = first & 0x07;
        } else
            return false;
        if (i + extra >= text.length)
            return false;
        foreach (k; 1 .. extra + 1) {
            const next = cast(ubyte)text[i + k];
            if ((next & 0xC0) != 0x80)
                return false;
            value = (value << 6) | (next & 0x3F);
        }
        if (value < minimum || value > 0x10FFFF || value >= 0xD800 && value <= 0xDFFF)
            return false;
        i += extra + 1;
    }
    return true;
}

@nogc nothrow pure unittest {
    assert(isValidUtf8("") && isValidUtf8("abc") && isValidUtf8("é日本語😀"));
    assert(!isValidUtf8("\xFF") && !isValidUtf8("a\xC3") && !isValidUtf8("\xC3("));
    assert(!isValidUtf8("\xC0\x80") && !isValidUtf8("\xE0\x80\x80"));
    assert(!isValidUtf8("\xED\xA0\x80") && !isValidUtf8("\xF4\x90\x80\x80"));
    assert(!isValidUtf8("\xF8\x88\x80\x80\x80") && !isValidUtf8("\x80"));
    assert(isValidUtf8("\xF4\x8F\xBF\xBF") && isValidUtf8("\xEF\xBF\xBD"));
}
