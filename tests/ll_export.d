module tests.ll_export;
import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

// ---- Independent EBNF reader and CFG (set-of-end-positions) matcher for the exported text.
private enum Kind {
    seq,
    alt,
    opt,
    star,
    plus,
    ref_,
    lit,
    cls,
    eps,
    eof
}

private struct Node {
    Kind kind;
    size_t[] kids;
    string text; // literal bytes or rule name
    bool[256] set;
}

private struct Ebnf {
    Node[] nodes;
    string[] names;
    size_t[] roots;
    string source;
    size_t at;
    bool failed;

    private char peekChar() {
        while (at < source.length && (source[at] == ' ' || source[at] == '\n'))
            ++at;
        return at < source.length ? source[at] : '\0';
    }

    private size_t add(Node node) {
        nodes ~= node;
        return nodes.length - 1;
    }

    private ubyte hexByte() {
        // at points after "\x"
        ubyte value;
        foreach (k; 0 .. 2) {
            const c = source[at++];
            value = cast(ubyte)(value * 16 + (c >= 'a' ? c - 'a' + 10 : c - '0'));
        }
        return value;
    }

    private size_t parseAtom() {
        const c = peekChar();
        Node node;
        if (c == '(') {
            ++at;
            const inner = parseAlt();
            if (peekChar() != ')')
                failed = true;
            ++at;
            return inner;
        }
        if (c == '"') {
            node.kind = Kind.lit;
            ++at;
            while (at < source.length && source[at] != '"') {
                if (source[at] == '\\') {
                    ++at;
                    if (source[at] == 'x') {
                        ++at;
                        node.text ~= cast(char)hexByte();
                    } else
                        node.text ~= source[at++];
                } else
                    node.text ~= source[at++];
            }
            ++at;
            return add(node);
        }
        if (c == '[') {
            node.kind = Kind.cls;
            ++at;
            while (source[at] != ']') {
                assert(source[at] == '\\' && source[at + 1] == 'x');
                at += 2;
                const low = hexByte();
                ubyte high = low;
                if (source[at] == '-') {
                    at += 3;
                    high = hexByte();
                }
                foreach (b; low .. high + 1)
                    node.set[b] = true;
            }
            ++at;
            return add(node);
        }
        size_t end = at;
        while (end < source.length && (source[end] == '_' || (source[end] >= 'A'
                && source[end] <= 'Z') || (source[end] >= 'a' && source[end] <= 'z')
                || (source[end] >= '0' && source[end] <= '9')))
            ++end;
        if (end == at) {
            failed = true;
            return 0;
        }
        const word = source[at .. end];
        at = end;
        node.kind = word == "eps" ? Kind.eps : word == "EOF" ? Kind.eof : Kind.ref_;
        node.text = word;
        return add(node);
    }

    private size_t parsePostfix() {
        size_t atom = parseAtom();
        while (true) {
            const c = peekChar();
            Kind kind;
            if (c == '?')
                kind = Kind.opt;
            else if (c == '*')
                kind = Kind.star;
            else if (c == '+')
                kind = Kind.plus;
            else
                return atom;
            ++at;
            Node wrap;
            wrap.kind = kind;
            wrap.kids = [atom];
            atom = add(wrap);
        }
    }

    private size_t parseSeq() {
        Node node;
        node.kind = Kind.seq;
        while (true) {
            const c = peekChar();
            if (c == '|' || c == ')' || c == ';' || c == '\0')
                break;
            node.kids ~= parsePostfix();
        }
        return add(node);
    }

    private size_t parseAlt() {
        Node node;
        node.kind = Kind.alt;
        node.kids ~= parseSeq();
        while (peekChar() == '|') {
            ++at;
            node.kids ~= parseSeq();
        }
        return add(node);
    }

    static Ebnf read(string text) {
        Ebnf result;
        result.source = text;
        while (true) {
            const c = result.peekChar();
            if (c == '\0')
                break;
            if (c == '(' && result.at + 1 < text.length && text[result.at + 1] == '*') { // comment line
                while (result.at < text.length && text[result.at] != '\n')
                    ++result.at;
                continue;
            }
            size_t end = result.at;
            while (end < text.length && text[end] != ' ')
                ++end;
            result.names ~= text[result.at .. end];
            result.at = end;
            result.peekChar();
            assert(text[result.at .. result.at + 3] == "::=");
            result.at += 3;
            result.roots ~= result.parseAlt();
            assert(result.peekChar() == ';');
            ++result.at;
        }
        assert(!result.failed);
        return result;
    }

    /// Positions at which `index` can finish, starting at `pos` (CFG semantics: all alternatives, all lengths).
    bool[] ends(size_t index, string input, size_t pos, size_t depth = 0) {
        assert(depth < 200);
        auto result = new bool[input.length + 1];
        const node = nodes[index];
        final switch (node.kind) {
        case Kind.eps:
            result[pos] = true;
            break;
        case Kind.eof:
            result[pos] = pos == input.length;
            break;
        case Kind.lit:
            if (pos + node.text.length <= input.length && input[pos .. pos + node.text.length] == node
                    .text)
                result[pos + node.text.length] = true;
            break;
        case Kind.cls:
            if (pos < input.length && node.set[cast(ubyte)input[pos]])
                result[pos + 1] = true;
            break;
        case Kind.ref_:
            foreach (r, name; names)
                if (name == node.text)
                    return ends(roots[r], input, pos, depth + 1);
            assert(false, "unknown rule in export");
        case Kind.seq:
            result[pos] = true;
            foreach (kid; node.kids) {
                auto next = new bool[input.length + 1];
                foreach (p; 0 .. input.length + 1)
                    if (result[p])
                        foreach (q, hit; ends(kid, input, p, depth + 1))
                            next[q] = next[q] || hit;
                result = next;
            }
            break;
        case Kind.alt:
            foreach (kid; node.kids)
                foreach (q, hit; ends(kid, input, pos, depth + 1))
                    result[q] = result[q] || hit;
            break;
        case Kind.opt:
            result[pos] = true;
            foreach (q, hit; ends(node.kids[0], input, pos, depth + 1))
                result[q] = result[q] || hit;
            break;
        case Kind.star:
        case Kind.plus:
            auto frontier = [pos];
            if (node.kind == Kind.star)
                result[pos] = true;
            bool[] visited = new bool[input.length + 1];
            while (frontier.length) {
                const p = frontier[$ - 1];
                frontier.length -= 1;
                foreach (q, hit; ends(node.kids[0], input, p, depth + 1))
                    if (hit) {
                        result[q] = true;
                        if (!visited[q]) {
                            visited[q] = true;
                            frontier ~= q;
                        }
                    }
            }
            break;
        }
        return result;
    }

    bool accepts(string rule, string input) {
        foreach (r, name; names)
            if (name == rule)
                return ends(roots[r], input, 0)[input.length];
        assert(false, "rule not exported");
    }
}

// ---- Finite-corpus differential check: exported CFG vs the real PEG parser on every string up to a length.
private struct Pair(string definition, ParserBackend backend) {
    mixin(grammar!(Memoization.selective, void, backend)(definition));
}

private string nameOf(string definition) {
    size_t end;
    while (definition[end] != ':')
        ++end;
    return definition[0 .. end];
}

private void compare(string definition, string rule, ParserBackend backend, string alphabet, size_t maxLength)(
        ref size_t checkedStrings) {
    auto exported = ebnfExport(definition);
    assert(exported.status == Status.ok);
    auto ebnf = Ebnf.read(exported.report);
    alias P = Pair!(definition, backend);
    string[] all = [""];
    size_t from;
    foreach (length; 0 .. maxLength) {
        const to = all.length;
        foreach (i; from .. to)
            foreach (c; alphabet)
                all ~= all[i] ~ c;
        from = to;
    }
    foreach (input; all) {
        ParseContext context;
        mixin("auto result = check!(P." ~ nameOf(definition) ~ "." ~ rule ~ ")(context, input);");
        const pegAccepts = result.successful && result.end == input.length;
        assert(pegAccepts == ebnf.accepts(rule, input), "exported CFG disagrees with the PEG");
        ++checkedStrings;
    }
}

private bool has(string text, string needle) @nogc nothrow pure {
    if (needle.length > text.length)
        return false;
    foreach (i; 0 .. text.length - needle.length + 1)
        if (text[i .. i + needle.length] == needle)
            return true;
    return false;
}

int main() {
    alarm(120);
    size_t checked;
    static foreach (backend; [ParserBackend.combinators, ParserBackend.direct]) {
        compare!("E: Num <- [0-9]+ Expr <- Term (('+' / '-') Term)* Term <- Num / '(' Expr ')' Root <- Expr eoi",
                "Root", backend, "1+-()", 7)(checked);
        compare!("S: Root <- 'a'* 'b'", "Root", backend, "abc", 7)(checked);
        compare!("S: Root <- 'a'+ 'b'?", "Root", backend, "abc", 7)(checked);
        compare!("N: Root <- ('a' / 'c'?) 'b'", "Root", backend, "abc", 6)(checked);
        compare!("K: Root <- Item (',' Item)* eoi Item <- 'x' 'y'? / 'z'", "Root", backend, "xyz,", 7)(
                checked);
    }
    assert(checked > 20000);
    // The contract refuses regions whose naive CFG reading differs from the PEG: show the trap and the refusal.
    enum trap = "T: Root <- 'a'* 'a' eoi";
    auto refused = ebnfExport(trap, EligibilityFormat.json);
    assert(has(refused.report, "\"status\":\"not-convertible\"") && !has(refused.report, "\"ebnf\":"));
    auto naive = Ebnf.read("Root ::= \"a\"* \"a\" EOF ;\n");
    alias T = Pair!(trap, ParserBackend.combinators);
    ParseContext context;
    assert(naive.accepts("Root", "aa") && !check!(T.T.Root)(context, "aa").successful);
    // Other classes get their own entries, with reasons and no EBNF.
    auto mixed = ebnfExport("M: Good <- 'a' Shadow <- 'a' / 'ab' Pred <- !'q' 'r' Act <- 'a'{act}");
    assert(has(mixed.report, "Good ::= \"a\" ;") && has(mixed.report, "(* not converted: Shadow is PEGOnly"));
    assert(has(mixed.report, "(* not converted: Pred is PEGOnly") && has(mixed.report,
            "(* not converted: Act is unknown"));
    auto json = ebnfExport("M: Good <- 'a' Bad <- 'a' / 'ab'", EligibilityFormat.json);
    assert(has(json.report, "\"rule\":\"Good\",\"ruleIndex\":0,\"status\":\"converted\"")
            && has(json.report, "\"proof\":{"));
    assert(has(json.report, "\"rule\":\"Bad\",\"ruleIndex\":1,\"status\":\"not-convertible\""));
    assert(ebnfExport("M: Good <- 'a'").report == ebnfExport("M: Good <- 'a'").report);
    assert(ebnfExport("Broken:").status == Status.invalidInput);
    assert(ebnfExport("M: Good <- 'a'", cast(EligibilityFormat)99).status == Status.invalidInput);
    printf("ll export passed (%zu strings)\n", checked);
    return 0;
}
