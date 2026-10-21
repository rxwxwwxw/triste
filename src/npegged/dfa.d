/** Cold CTFE Thompson/subset compiler and allocation-free byte scanner.
    Callers must establish equivalence between PEG and regular-language semantics. */
module npegged.dfa;

import npegged.peg : CharSetMask, State, Status, ParseContext, CheckResult;

version (NPeggedScannerMetrics) import npegged.peg : ScannerEvent, ScannerReason;

nothrow:

enum RegularKind {
    bytes,
    sequence,
    choice,
    optional,
    repetition,
    endOfInput
}

/// Children precede their parents; references and actions are deliberately absent.
struct RegularExpression {
    RegularKind kind;
    CharSetMask bytes;
    size_t[] children;
}

/// Compact constructors keep generated automaton graphs readable and stable under dfmt.
RegularExpression regularByte(ulong b0, ulong b1, ulong b2, ulong b3) @nogc pure nothrow @safe {
    return RegularExpression(RegularKind.bytes, CharSetMask([b0, b1, b2, b3]));
}

@nogc nothrow unittest {
    const node = regularByte(1, 2, 3, 4);
    assert(node.kind == RegularKind.bytes && node.bytes.bits == [1UL, 2UL, 3UL, 4UL]);
}

RegularExpression regularNode(RegularKind kind, size_t[] children) @nogc pure nothrow @safe {
    return RegularExpression(kind, CharSetMask.init, children);
}

@nogc nothrow unittest {
    size_t[2] children = [0, 1];
    const node = regularNode(RegularKind.sequence, children[]);
    assert(node.children == children[] && node.kind == RegularKind.sequence);
}

struct Automaton {
    ubyte[256][] transitions;
    bool[] accepting;
    bool valid;
    bool requireEnd;
    /// Extra accepting states enabled only after the last input byte.
    bool[] eofAccepting;
}

private struct NfaState {
    size_t[] epsilon;
    size_t[] eofEpsilon;
    CharSetMask bytes;
    size_t target = size_t.max;
}

/// Bounded construction and determinization fall back without exhausting CTFE storage.
Automaton compileDFA(const(RegularExpression)[] expressions, size_t root, bool requireEnd = false,
        size_t stateLimit = ubyte.max, size_t nfaLimit = 4096) pure {
    Automaton result;
    if (root >= expressions.length || !stateLimit || stateLimit > ubyte.max || nfaLimit < 2)
        return result;
    const maxStates = expressions.length * 4 + 4 < nfaLimit + 2 ? expressions.length * 4 + 4 : nfaLimit + 2;
    auto stateBuf = new NfaState[maxStates];
    size_t stateCount;
    struct Fragment {
        size_t begin, end;
    }

    bool malformed;
    bool hasEnd;
    Fragment build(size_t index, size_t depth = 0) {
        if (stateCount > nfaLimit - 2 || stateCount + 2 > stateBuf.length || depth >= 128) {
            malformed = true;
            return Fragment.init;
        }
        alias states = stateBuf;
        auto node = expressions[index];
        if (node.kind == RegularKind.sequence && node.children.length == 1) {
            if (node.children[0] >= index) {
                malformed = true;
                return Fragment.init;
            }
            return build(node.children[0], depth + 1);
        }
        const begin = stateCount++;
        const end = stateCount++;
        if (node.kind == RegularKind.bytes) {
            states[begin].bytes = node.bytes;
            states[begin].target = end;
        } else if (node.kind == RegularKind.endOfInput) {
            hasEnd = true;
            malformed = node.children.length != 0;
            states[begin].eofEpsilon ~= end;
        } else {
            size_t previous = begin;
            foreach (child; node.children) {
                if (child >= index) {
                    malformed = true;
                    return Fragment(begin, end);
                }
                const savedCount = stateCount;
                const part = build(child, depth + 1);
                if (malformed)
                    return Fragment(begin, end);
                if (node.kind == RegularKind.sequence) {
                    states[previous].epsilon ~= part.begin;
                    previous = part.end;
                } else if (node.kind == RegularKind.choice && part.begin == savedCount
                        && part.end == savedCount + 1 && stateCount == savedCount + 2
                        && states[part.begin].target == part.end
                        && !states[part.begin].epsilon.length
                        && !states[part.begin].eofEpsilon.length) {
                    states[begin].bytes = states[begin].bytes | states[part.begin].bytes;
                    states[begin].target = end;
                    states[part.begin] = NfaState.init;
                    stateCount = savedCount;
                } else {
                    states[begin].epsilon ~= part.begin;
                    states[part.end].epsilon ~= end;
                    if (node.kind == RegularKind.repetition)
                        states[part.end].epsilon ~= part.begin;
                }
            }
            if (node.kind == RegularKind.sequence)
                states[previous].epsilon ~= end;
            else if (node.kind == RegularKind.optional || node.kind == RegularKind.repetition) {
                if (node.children.length != 1)
                    malformed = true;
                states[begin].epsilon ~= end;
            }
        }
        return Fragment(begin, end);
    }

    const fragment = build(root);
    if (malformed)
        return result;
    auto states = stateBuf[0 .. stateCount];
    auto pending = new size_t[states.length];
    bool[] closure(bool[] set, bool atEnd = false) {
        size_t tail;
        foreach (i, present; set)
            if (present)
                pending[tail++] = i;
        while (tail) {
            const current = pending[--tail];
            foreach (next; states[current].epsilon)
                if (!set[next]) {
                    set[next] = true;
                    pending[tail++] = next;
                }
            if (atEnd)
                foreach (next; states[current].eofEpsilon)
                    if (!set[next]) {
                        set[next] = true;
                        pending[tail++] = next;
                    }
        }
        return set;
    }

    auto initial = new bool[states.length];
    initial[fragment.begin] = true;
    bool[][] subsets = [closure(initial)];
    auto active = new size_t[states.length];
    for (size_t current; current < subsets.length; ++current) {
        ubyte[256] row = ubyte.max;
        size_t activeLen;
        CharSetMask remaining;
        foreach (i, present; subsets[current])
            if (present && states[i].target != size_t.max) {
                active[activeLen++] = i;
                remaining = remaining | states[i].bytes;
            }
        for (size_t byteValue; byteValue < 256 && !remaining.empty; ++byteValue) {
            if (!remaining.contains(cast(ubyte)byteValue))
                continue;
            CharSetMask same = remaining;
            auto next = new bool[states.length];
            foreach (k; 0 .. activeLen) {
                const i = active[k];
                if (states[i].bytes.contains(cast(ubyte)byteValue)) {
                    next[states[i].target] = true;
                    same = same & states[i].bytes;
                } else {
                    same = same & ~states[i].bytes;
                }
            }
            next = closure(next);
            size_t target;
            while (target < subsets.length && subsets[target] != next)
                ++target;
            if (target == subsets.length) {
                if (target == stateLimit)
                    return Automaton.init;
                subsets ~= next;
            }
            foreach (b; byteValue .. 256)
                if (same.contains(cast(ubyte)b))
                    row[b] = cast(ubyte)target;
            remaining = remaining & ~same;
        }
        result.transitions ~= row;
        result.accepting ~= subsets[current][fragment.end];
        if (hasEnd)
            result.eofAccepting ~= closure(subsets[current].dup, true)[fragment.end];
    }
    if (result.eofAccepting == result.accepting)
        result.eofAccepting = null;
    result.valid = true;
    result.requireEnd = requireEnd;
    return minimizeDFA(result);
}

unittest {
    CharSetMask digits, dot;
    digits.addRange('0', '9');
    dot.addChar('.');
    // [0-9]+ ('.' [0-9]+)?
    RegularExpression[] nodes = [
        RegularExpression(RegularKind.bytes, digits),
        RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
        RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1]),
        RegularExpression(RegularKind.bytes, dot),
        RegularExpression(RegularKind.sequence, CharSetMask.init, [3, 2]),
        RegularExpression(RegularKind.optional, CharSetMask.init, [4]),
        RegularExpression(RegularKind.sequence, CharSetMask.init, [2, 5])
    ];
    const table = compileDFA(nodes, 6);
    assert(table.valid);
    assert(scanDFA(table.transitions, table.accepting, "123.45!", 0) == 6);
    assert(scanDFA(table.transitions, table.accepting, "123.", 0) == 3);
    assert(scanDFA(table.transitions, table.accepting, "x", 0) == size_t.max);
    nodes ~= RegularExpression(RegularKind.choice, CharSetMask.init, [0, 3]);
    const choice = compileDFA(nodes, 7);
    assert(scanDFA(choice.transitions, choice.accepting, ".", 0) == 1);
    assert(!compileDFA(nodes, 100).valid);
    nodes ~= RegularExpression(RegularKind.sequence, CharSetMask.init, [8]);
    assert(!compileDFA(nodes, 8).valid);
    nodes ~= RegularExpression(RegularKind.optional);
    assert(!compileDFA(nodes, 9).valid);
    assert(!compileDFA(nodes, 0, false, 1).valid);
    assert(!compileDFA(nodes, 0, false, 0).valid);
    assert(!compileDFA(nodes, 0, false, 256).valid);
    assert(!compileDFA(nodes, 0, false, 255, 1).valid);
    assert(!compileDFA(nodes, 1, false, 255, 2).valid);
    RegularExpression[] deeplyNested = [regularByte(1, 0, 0, 0)];
    foreach (size_t i; 1 .. 512)
        deeplyNested ~= regularNode(RegularKind.optional, [i - 1]);
    assert(!compileDFA(deeplyNested, deeplyNested.length - 1).valid);
    assert(!compileDFA([regularNode(RegularKind.endOfInput, [0])], 0).valid);
    auto anchored = compileDFA([
        RegularExpression(RegularKind.bytes, digits), regularNode(RegularKind.endOfInput, []),
        regularNode(RegularKind.sequence, [0, 1])
    ], 2);
    const afterDigit = anchored.transitions[0]['0'];
    assert(anchored.valid && !anchored.accepting[afterDigit] && anchored.eofAccepting[afterDigit]);
}

/// Refine equivalence classes until every byte transition agrees within a class.
Automaton minimizeDFA(Automaton input) pure {
    if (!input.valid)
        return input;
    // Keep explicit failed-prefix states: reaching one advances the diagnostic
    // offset, whereas a missing transition stops before consuming that byte.
    // Refinement preserves both acceptance and this observable scan behavior.
    auto classes = new size_t[input.transitions.length];
    const endAccepting = input.eofAccepting.length ? input.eofAccepting : input.accepting;
    foreach (i; 0 .. classes.length)
        classes[i] = (input.accepting[i] ? 1 : 0) + (endAccepting[i] ? 2 : 0);
    size_t[] representatives;
    while (true) {
        auto refined = new size_t[classes.length];
        representatives = null;
        foreach (i; 0 .. classes.length) {
            size_t group;
            foreach (candidate; representatives) {
                bool equivalent = input.accepting[i] == input.accepting[candidate]
                    && endAccepting[i] == endAccepting[candidate];
                foreach (c; 0 .. 256) {
                    const a = input.transitions[i][c], b = input.transitions[candidate][c];
                    if ((a == ubyte.max) != (b == ubyte.max) || (a != ubyte.max && b != ubyte.max
                            && classes[a] != classes[b])) {
                        equivalent = false;
                        break;
                    }
                }
                if (equivalent)
                    break;
                ++group;
            }
            if (group == representatives.length)
                representatives ~= i;
            refined[i] = group;
        }
        if (refined == classes)
            break;
        classes = refined;
    }
    Automaton result;
    result.transitions = new ubyte[256][representatives.length];
    result.accepting = new bool[representatives.length];
    if (input.eofAccepting.length)
        result.eofAccepting = new bool[representatives.length];
    foreach (idx, representative; representatives) {
        auto row = input.transitions[representative];
        foreach (ref target; row)
            if (target != ubyte.max)
                target = cast(ubyte)classes[target];
        result.transitions[idx] = row;
        result.accepting[idx] = input.accepting[representative];
        if (input.eofAccepting.length)
            result.eofAccepting[idx] = endAccepting[representative];
    }
    result.valid = true;
    result.requireEnd = input.requireEnd;
    return result;
}

unittest {
    Automaton input;
    ubyte[256] row = ubyte.max;
    input.transitions = [row, row, row];
    input.transitions[0]['a'] = 1;
    input.transitions[0]['b'] = 2;
    input.accepting = [false, true, true];
    input.valid = true;
    const minimized = minimizeDFA(input);
    assert(minimized.transitions.length == 2);
    assert(minimized.transitions[0]['a'] == minimized.transitions[0]['b']);
    assert(!minimizeDFA(Automaton.init).valid);

}

/// Return the last accepting offset, or size_t.max when no prefix matched.
size_t scanDFA(scope const(ubyte[256])[] transitions, scope const(bool)[] accepting, scope string input,
        size_t pos) @nogc pure nothrow @safe {
    size_t examined;
    return scanDFA(transitions, accepting, input, pos, examined);
}

@nogc nothrow unittest {
    ubyte[256][1] transitions;
    transitions[0][] = ubyte.max;
    bool[1] accepting = [true];
    assert(scanDFA(transitions[], accepting[], "suffix", 0) == 0);
}

/// The furthest examined prefix preserves recognition diagnostics after rollback.
size_t scanDFA(scope const(ubyte[256])[] transitions, scope const(bool)[] accepting, scope string input,
        size_t pos, out size_t examined) @nogc pure nothrow @safe {
    examined = pos;
    if (!transitions.length || transitions.length != accepting.length || pos > input.length)
        return size_t.max;
    ubyte state;
    size_t end = accepting[0] ? pos : size_t.max;
    while (pos < input.length) {
        const next = transitions[state][cast(ubyte)input[pos]];
        if (next == ubyte.max)
            break;
        assert(next < transitions.length);
        state = next;
        ++pos;
        examined = pos;
        if (accepting[state])
            end = pos;
    }
    return end;
}

@nogc nothrow unittest {
    enum makeTable = () {
        CharSetMask mask;
        mask.addRange('a', 'z');
        return compileDFA([RegularExpression(RegularKind.bytes, mask)], 0);
    };
    enum table = makeTable();
    static assert(table.valid);
    assert(scanDFA(table.transitions, table.accepting, "az", 0) == 1);
    assert(scanDFA(table.transitions, table.accepting, "az", 1) == 2);
    assert(scanDFA(table.transitions, table.accepting, "", 1) == size_t.max);
    assert(scanDFA(null, null, "", 0) == size_t.max);
}

private struct DfaStorage(alias Table) {
    static if (__traits(hasMember, Table, "automaton"))
        enum compiled = Table.automaton;
    else
        enum compiled = Table;
    static immutable loops = () {
        CharSetMask[compiled.transitions.length] masks;
        foreach (state, row; compiled.transitions)
            foreach (c; 0 .. 256)
                if (row[c] == state)
                    masks[state].addChar(cast(ubyte)c);
        return masks;
    }();
    static immutable automaton = compiled;
    version (NPeggedDFAEdgeCoverage) unittest {
        import tests.dfa_edges : exercise;

        static if (compiled.valid)
            assert(exercise!Table() > 0);
        else
            assert(exercise!Table() == 0);
    }
}

/// Largest DFA lowered to straight-line state code; bigger tables use the generic loop.
private enum codeScannerStateLimit = 48;

private string unsignedText(size_t value) pure nothrow @safe {
    char[20] digits;
    size_t count;
    do {
        digits[count++] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value);
    string result;
    while (count)
        result ~= digits[--count];
    return result;
}

@safe pure nothrow unittest {
    assert(unsignedText(0) == "0" && unsignedText(7) == "7" && unsignedText(1204) == "1204");
}

private string hexText(ulong value) pure nothrow @safe {
    string result;
    foreach_reverse (nibble; 0 .. 16)
        result ~= "0123456789abcdef"[(value >> (nibble * 4)) & 15];
    return result;
}

@safe pure nothrow unittest {
    assert(hexText(0) == "0000000000000000" && hexText(0x1f2a) == "0000000000001f2a");
}

/// `case` labels (ranges for consecutive bytes) of every byte `state` sends to `target`.
private string emitRuns(const Automaton automaton, size_t state, ubyte target) pure nothrow @safe {
    string labels;
    size_t c;
    while (c < 256) {
        if (automaton.transitions[state][c] != target) {
            ++c;
            continue;
        }
        size_t last = c;
        while (last + 1 < 256 && automaton.transitions[state][last + 1] == target)
            ++last;
        labels ~= "case " ~ unsignedText(c) ~ ":" ~ (last > c ? " .. case " ~ unsignedText(last) ~ ":" : "") ~ "\n";
        c = last + 1;
    }
    return labels;
}

@safe pure nothrow unittest {
    Automaton table;
    table.transitions.length = 1;
    foreach (ref target; table.transitions[0])
        target = ubyte.max;
    assert(emitRuns(table, 0, 0).length == 0);
    table.transitions[0][0] = 0;
    table.transitions[0][1] = 0;
    table.transitions[0][255] = 0;
    assert(emitRuns(table, 0, 0) == "case 0: .. case 1:\ncase 255:\n");
}

/// CTFE source for a scanner that keeps the DFA state in the program counter.
/// Each state label performs exactly the arrival bookkeeping of the table loop:
/// accepting/EOF-accepting ends, the examined frontier, then one byte dispatch.
/// Expects `input`, `pos`, `end`, `examined` and `lastEofEnd` in scope.
private string codeScannerSource(const Automaton automaton) pure nothrow @safe {
    string code = "const size_t scanLength = input.length;\n";
    const hasEof = automaton.eofAccepting.length != 0;
    foreach (state; 0 .. automaton.transitions.length) {
        const name = unsignedText(state);
        code ~= "dfaState" ~ name ~ ":\n";
        // Self-loop bytes run in a tight loop; arrival bookkeeping then happens once,
        // exactly as the table loop's hoisted self-loop does.
        ulong[4] loopBits;
        foreach (c; 0 .. 256)
            if (automaton.transitions[state][c] == state)
                loopBits[c >> 6] |= 1UL << (c & 63);
        size_t runStart = 256, runEnd, loopRuns;
        foreach (c; 0 .. 256)
            if (automaton.transitions[state][c] == state) {
                if (runStart == 256)
                    runStart = c;
                runEnd = c;
                if (c == 0 || automaton.transitions[state][c - 1] != state)
                    ++loopRuns;
            }
        if (loopRuns == 1) {
            // One contiguous byte range: a single unsigned compare.
            code ~= "while (pos < scanLength && cast(ubyte)(cast(ubyte)input[pos] - " ~ unsignedText(
                    runStart) ~ ") <= " ~ unsignedText(runEnd - runStart) ~ ") ++pos;\n";
        } else if (loopRuns) {
            string literal;
            foreach (word; loopBits)
                literal ~= (literal.length ? ", 0x" : "0x") ~ hexText(word) ~ "UL";
            code ~= "{ enum ulong[4] loopBits = [" ~ literal ~ "]; while (pos < scanLength) { const ubyte c = " ~ "cast(ubyte)input[pos]; if (!((loopBits[c >> 6] >> (c & 63)) & 1)) break; ++pos; } }\n";
        }
        if (automaton.accepting[state])
            code ~= "end = pos;\n";
        const eof = hasEof && automaton.eofAccepting[state];
        if (eof)
            code ~= "lastEofEnd = pos;\n";
        code ~= "examined = pos;\n";
        code ~= "if (pos == scanLength) {" ~ (eof ? " end = pos;" : "") ~ " goto dfaFinish; }\n";
        code ~= "switch (cast(ubyte)input[pos]) {\n";
        foreach (target; 0 .. automaton.transitions.length) {
            if (target == state)
                continue;
            const runs = emitRuns(automaton, state, cast(ubyte)target);
            if (runs.length)
                code ~= runs ~ "++pos; goto dfaState" ~ unsignedText(target) ~ ";\n";
        }
        code ~= "default: goto dfaFinish;\n}\n";
    }
    code ~= "dfaFinish:;\n";
    return code;
}

@safe pure nothrow unittest {
    Automaton table;
    table.transitions.length = 1;
    table.accepting = [true];
    table.eofAccepting = [true];
    foreach (ref target; table.transitions[0])
        target = ubyte.max;
    auto withoutLoops = codeScannerSource(table);
    assert(withoutLoops.length && withoutLoops != codeScannerSource(Automaton.init));
    table.transitions[0][0] = 0;
    table.transitions[0][1] = 0;
    auto rangeLoop = codeScannerSource(table);
    assert(rangeLoop != withoutLoops);
    table.transitions[0][255] = 0;
    auto maskLoop = codeScannerSource(table);
    assert(maskLoop != rangeLoop);
    table.accepting[0] = false;
    table.eofAccepting = null;
    assert(codeScannerSource(table) != maskLoop);
    table.transitions.length = 2;
    foreach (ref target; table.transitions[1])
        target = ubyte.max;
    table.transitions[0]['b'] = 1;
    table.accepting ~= true;
    assert(codeScannerSource(table).length > maskLoop.length);
}

/// Hoist a state's self-loop byte class out of its inner scanner loop.
/// This preserves DFA semantics while removing a dependent table read per byte.
pragma(inline, true) size_t scanDFA(alias Table)(scope string input, size_t pos,
        out size_t examined, out size_t lastEofEnd) @nogc pure nothrow @safe {
    alias compiled = DfaStorage!Table.compiled;
    return scanDFAWith!(Table, compiled.transitions.length <= codeScannerStateLimit)(input, pos, examined,
            lastEofEnd);
}

/// `Code` selects the straight-line state scanner over the table loop; both are equivalent.
pragma(inline, true) size_t scanDFAWith(alias Table, bool Code)(scope string input, size_t pos,
        out size_t examined, out size_t lastEofEnd) @nogc pure nothrow @safe {
    alias storage = DfaStorage!Table;
    alias compiled = storage.compiled;
    alias loops = storage.loops;
    alias automaton = storage.automaton;
    examined = pos;
    lastEofEnd = size_t.max;
    static if (!compiled.valid)
        return size_t.max;
    else {
        if (pos > input.length)
            return size_t.max;
        size_t end = size_t.max;
        static if (Code) {
            mixin(codeScannerSource(compiled));
            lastEofEnd = automaton.eofAccepting.length ? lastEofEnd : end;
            return automaton.requireEnd && end != input.length ? size_t.max : end;
        } else {
            ubyte state;
            end = automaton.accepting[0] ? pos : size_t.max;
            if (automaton.eofAccepting.length && automaton.eofAccepting[0])
                lastEofEnd = pos;
            while (pos < input.length) {
                const mask = loops[state];
                while (pos < input.length && mask.contains(cast(ubyte)input[pos]))
                    ++pos;
                examined = pos;
                if (automaton.accepting[state])
                    end = pos;
                if (automaton.eofAccepting.length && automaton.eofAccepting[state])
                    lastEofEnd = pos;
                if (pos == input.length)
                    break;
                const next = automaton.transitions[state][cast(ubyte)input[pos]];
                if (next == ubyte.max)
                    break;
                state = next;
                ++pos;
                examined = pos;
                if (automaton.accepting[state])
                    end = pos;
                if (automaton.eofAccepting.length && automaton.eofAccepting[state])
                    lastEofEnd = pos;
            }
            if (pos == input.length && automaton.eofAccepting.length && automaton.eofAccepting[state]) {
                end = pos;
                lastEofEnd = pos;
            }
            lastEofEnd = automaton.eofAccepting.length ? lastEofEnd : end;
            return automaton.requireEnd && end != input.length ? size_t.max : end;
        }
    }
}

@nogc nothrow unittest {
    // The state-code scanner must match the table loop on every observable output.
    static void same(alias table)(string input) {
        foreach (start; 0 .. input.length + 1) {
            size_t examinedCode, examinedTable, eofCode, eofTable;
            const code = scanDFAWith!(table, true)(input, start, examinedCode, eofCode);
            const loop = scanDFAWith!(table, false)(input, start, examinedTable, eofTable);
            assert(code == loop && examinedCode == examinedTable && eofCode == eofTable);
        }
    }

    enum digits = () {
        CharSetMask d;
        d.addRange('0', '9');
        return compileDFA([
            RegularExpression(RegularKind.bytes, d),
            RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
            RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
        ], 2);
    }();
    enum anchoredDigits = () {
        CharSetMask d;
        d.addRange('0', '9');
        return compileDFA([
            RegularExpression(RegularKind.bytes, d),
            RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
            RegularExpression(RegularKind.endOfInput, CharSetMask.init),
            RegularExpression(RegularKind.sequence, CharSetMask.init, [1, 2])
        ], 3);
    }();
    enum quoted = () {
        CharSetMask q,
        s,
        other;
        q.addChar('"');
        s.addChar('\\');
        other.addRange(0, 255);
        CharSetMask plain;
        foreach (c; 0 .. 256)
            if (c != '"' && c != '\\')
                plain.addChar(cast(ubyte)c);
        return compileDFA([
            RegularExpression(RegularKind.bytes, q), // 0
            RegularExpression(RegularKind.bytes, s), // 1
            RegularExpression(RegularKind.bytes, other), // 2
            RegularExpression(RegularKind.sequence,
                    CharSetMask.init,
                    [1, 2]), // 3 escape
            RegularExpression(RegularKind.bytes, plain), // 4
            RegularExpression(RegularKind.choice,
                    CharSetMask.init,
                    [3, 4]), // 5
            RegularExpression(RegularKind.repetition, CharSetMask.init, [5]), // 6
            RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 6, 0]) // 7
        ], 7);
    }();
    static foreach (table; [digits, anchoredDigits, quoted]) {
        {
            enum t = table;
            static immutable string[] inputs = [
                "", "1", "123", "123x", "x", "\"\"", "\"a\"", "\"a\\\"b\"", "\"a\\", "\"abc",
                "\"a\\\"", "\"\\\\\"x", "\"\\n\\t\"", "12\"3"
            ];
            foreach (input; inputs)
                same!t(input);
        }
    }
    // A table past the state limit still takes the loop path in the public entry point.
    static assert(codeScannerStateLimit < ubyte.max);
}

size_t scanDFA(alias Table)(scope string input, size_t pos, out size_t examined) @nogc pure nothrow @safe {
    size_t lastEofEnd;
    return scanDFA!Table(input, pos, examined, lastEofEnd);
}

@nogc nothrow unittest {
    enum mask = CharSetMask.fromChars('a');
    enum table = compileDFA([regularByte(mask.bits[0], mask.bits[1], mask.bits[2], mask.bits[3])], 0);
    size_t examined;
    assert(scanDFA!table("ax", 0, examined) == 1 && examined == 1);
}

@nogc nothrow unittest {
    enum end = compileDFA([regularNode(RegularKind.endOfInput, [])], 0);
    assert(scanDFA!end("", 0) == 0 && scanDFA!end("x", 0) == size_t.max);
    assert(scanDFA!end("x", 1) == 1);
    enum mask = CharSetMask.fromChars('a');
    enum anchored = compileDFA([
            regularByte(mask.bits[0], mask.bits[1], mask.bits[2], mask.bits[3]),
            regularNode(RegularKind.endOfInput, []), regularNode(RegularKind.sequence, [0, 1])
    ], 2);
    assert(scanDFA!anchored("a", 0) == 1 && scanDFA!anchored("ax", 0) == size_t.max);
    enum impossible = compileDFA([
            regularNode(RegularKind.endOfInput, []),
            regularByte(mask.bits[0], mask.bits[1], mask.bits[2], mask.bits[3]),
            regularNode(RegularKind.sequence, [0, 1])
    ], 2);
    assert(scanDFA!impossible("a", 0) == size_t.max);
}

/// Alias form keeps the table and compressed byte classes in compile-time storage.
size_t scanDFA(alias Table)(scope string input, size_t pos) @nogc pure nothrow @safe {
    size_t examined;
    return scanDFA!Table(input, pos, examined);
}

@nogc nothrow unittest {
    enum table = () {
        CharSetMask a,
        b;
        a.addChar('a');
        b.addChar('b');
        return compileDFA([
            RegularExpression(RegularKind.bytes, a),
            RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
            RegularExpression(RegularKind.bytes, b),
            RegularExpression(RegularKind.sequence, CharSetMask.init, [1, 2])
        ], 3);
    }();
    foreach (input; ["", "a", "aaab", "aaab!", "b", "!", "abbb"])
        assert(scanDFA!table(input, 0) == scanDFA(table.transitions, table.accepting, input, 0));
    assert(scanDFA!table("", 1) == size_t.max);
    enum invalid = Automaton.init;
    assert(scanDFA!invalid("a", 0) == size_t.max);
}

/// Array-alias interface for ordinary byte DFAs; the table form also carries EOF facts.
size_t scanDFA(alias Transitions, alias Accepting)(scope string input, size_t pos) @nogc pure nothrow @safe {
    struct BoundTable {
        static immutable automaton = Automaton(Transitions, Accepting, true);
    }

    return scanDFA!BoundTable(input, pos);
}

@nogc nothrow unittest {
    enum mask = CharSetMask.fromChars('a');
    enum table = compileDFA([regularByte(mask.bits[0], mask.bits[1], mask.bits[2], mask.bits[3])], 0);
    assert(scanDFA!(table.transitions, table.accepting)("ax", 0) == 1);
    assert(scanDFA!(table.transitions, table.accepting)("x", 0) == size_t.max);
}

version (NPeggedScannerMetrics) template scannerName(alias Table) {
    static if (__traits(hasMember, Table, "diagnosticName"))
        enum scannerName = Table.diagnosticName;
    else
        enum scannerName = "<anonymous DFA>";
}

version (NPeggedScannerMetrics) @nogc nothrow unittest {
    struct Named {
        enum diagnosticName = "Example.Token/_dfa_Token";
    }

    static assert(scannerName!Named == "Example.Token/_dfa_Token");
    static assert(scannerName!Automaton == "<anonymous DFA>");
}

/// Generic tree capture retains the original combinator.
/// A failed scan is replayed to produce the original failure structure.
struct dfaToken(alias Original, alias Table, size_t ReferenceDepth = 0, bool HasInnerRecords = false) {
    version (NPeggedScannerMetrics) private enum diagnosticName = scannerName!Table;
    static if (__traits(hasMember, Original, "scan")) {
        version (NPeggedScannerMetrics) {
            static State!(CT, Check).Node scan(bool Capture, bool CT, int Check = 0)(ref State!(CT,
                    Check) s, size_t pos) nothrow {
                ScannerEvent event;
                event.rule = diagnosticName;
                event.reason = ScannerReason.primitiveScan;
                event.eligible = (Check == 1 || Check == 2 && !HasInnerRecords) && Table.valid;
                event.original = true;
                auto sink = s.context.scannerReport;
                auto result = Original.scan!Capture(s, pos);
                const frontier = result.end > result.failEnd ? result.end : result.failEnd;
                event.originalBytes = frontier > pos ? frontier - pos : 0;
                if (!__ctfe && sink !is null)
                    sink.record(event);
                return result;
            }
        } else
            alias scan = Original.scan;
    }
    static if (__traits(hasMember, Original, "byteScanner") && __traits(hasMember, Original,
            "byteMatches") && __traits(hasMember, Original, "byteSteps") && Original.byteScanner) {
        enum byteScanner = true;
        alias byteMatches = Original.byteMatches;
        alias byteSteps = Original.byteSteps;
    }
    /// Cursor entry (S4, S5). `steps`/`live` and `depth` are the caller's register-resident counters (`s.depth` may be stale). A scan the table settles
    /// consumes exactly the work units `opCall` charges and never touches `s.steps` or `s.status`; every other
    /// outcome syncs the shared state and replays through `opCall`, so end, failEnd, status and steps are
    /// identical to `s.steps = steps; opCall(s, pos); steps = s.steps; live = s.status == Status.ok`.
    pragma(inline, true) static bool cursor(bool CT, int Check = 0)(ref State!(CT, Check) s,
            size_t pos, ref size_t steps, ref bool live, const size_t depth, out size_t end, out size_t failEnd) nothrow {
        return cursorImpl!false(s, pos, steps, live, depth, end, failEnd);
    }

    /// `cursor` for `accept` mode: identical units and outcomes, but a settled failure is not recorded as a diagnostic.
    pragma(inline, true) static bool cursorAccept(bool CT, int Check = 0)(ref State!(CT, Check) s,
            size_t pos, ref size_t steps, ref bool live, const size_t depth, out size_t end, out size_t failEnd) nothrow {
        return cursorImpl!true(s, pos, steps, live, depth, end, failEnd);
    }

    pragma(inline, true) private static bool cursorImpl(bool Accept, bool CT, int Check)(
            ref State!(CT,
            Check) s, size_t pos, ref size_t steps, ref bool live, const size_t depth, out size_t end,
            out size_t failEnd) nothrow {
        version (NPeggedScannerMetrics) {
        } else static if ((Check == 1 || (Check == 2 && !HasInnerRecords)) && Table.valid) {
            const limit = s.context.stepLimit;
            if (live && steps < limit && pos <= s.input.length && (!ReferenceDepth
                    || s.context.trace is null && depth <= s.context.depthLimit
                    && ReferenceDepth <= s.context.depthLimit - depth)) {
                const remaining = limit - steps - 1;
                const available = s.input.length - pos;
                const stop = pos + (remaining < available ? remaining : available);
                size_t examined;
                size_t lastEofEnd;
                const scanned = scanDFA!Table(s.input[0 .. stop], pos, examined, lastEofEnd);
                const settled = examined < stop || stop == s.input.length;
                if (scanned != size_t.max && settled) {
                    steps += examined - pos + 1;
                    static if (!Accept)
                        if (examined > scanned)
                            s.recordFailure(s.node(pos, examined, false));
                    end = failEnd = scanned;
                    return true;
                }
                static if (Table.requireEnd) {
                    if (settled && lastEofEnd != size_t.max) {
                        steps += examined - pos + 1;
                        end = lastEofEnd;
                        failEnd = examined > lastEofEnd ? examined : lastEofEnd;
                        static if (!Accept) {
                            auto failed = s.node(pos, end, false);
                            failed.failEnd = failEnd;
                            s.recordFailure(failed);
                        }
                        return false;
                    }
                } else {
                    if (settled) {
                        steps += examined - pos + 1;
                        end = failEnd = examined;
                        static if (!Accept) {
                            auto failed = s.node(pos, examined, false);
                            failed.failEnd = examined;
                            s.recordFailure(failed);
                        }
                        return false;
                    }
                }
            }
        }
        s.steps = steps;
        s.depth = depth;
        const replay = opCall(s, pos);
        steps = s.steps;
        live = s.status == Status.ok;
        end = replay.end;
        failEnd = replay.failEnd;
        return replay.successful;
    }

    /// The cursor entry for bodies whose counters live in the shared state (`withSharedSteps`).
    pragma(inline, true) static bool cursorShared(bool CT, int Check = 0)(ref State!(CT, Check) s,
            size_t pos, const size_t depth, out size_t end, out size_t failEnd) nothrow {
        s.depth = depth;
        const result = opCall(s, pos);
        end = result.end;
        failEnd = result.failEnd;
        return result.successful;
    }

    pragma(inline, true) static State!(CT, Check).Node opCall(bool CT, int Check = 0)(ref State!(CT,
            Check) s, size_t pos) nothrow {
        version (NPeggedScannerMetrics) {
            ScannerEvent event;
            event.rule = diagnosticName;
            auto sink = s.context.scannerReport;
            scope (exit)
                if (!__ctfe && sink !is null)
                    sink.record(event);
            static if (Check == 0)
                event.reason = ScannerReason.tree;
            else static if (Check == 2 && HasInnerRecords)
                event.reason = ScannerReason.innerRecords;
            else static if (!Table.valid)
                event.reason = ScannerReason.invalidTable;
        }
        static if ((Check == 1 || (Check == 2 && !HasInnerRecords)) && Table.valid) {
            version (NPeggedScannerMetrics)
                event.eligible = true;
            if (s.status == Status.ok && pos <= s.input.length && s.steps < s.context.stepLimit
                    && (!ReferenceDepth || s.context.trace is null) && (!ReferenceDepth
                        || s.depth <= s.context.depthLimit
                        && ReferenceDepth <= s.context.depthLimit - s.depth)) {
                // Every examined byte consumes one work unit. Cap speculation
                // before scanning so a small budget cannot trigger an unbounded loop.
                const remaining = s.context.stepLimit - s.steps - 1;
                const available = s.input.length - pos;
                const limit = pos + (remaining < available ? remaining : available);
                size_t examined;
                size_t lastEofEnd;
                const end = scanDFA!Table(s.input[0 .. limit], pos, examined, lastEofEnd);
                version (NPeggedScannerMetrics) {
                    event.attempted = true;
                    event.scanAccepted = end != size_t.max;
                    event.examinedBytes = examined - pos;
                    event.reason = examined < limit || limit == s.input.length
                        ? ScannerReason.failureDiagnostic : ScannerReason.budgetEdge;
                }
                if (end != size_t.max && (examined < limit || limit == s.input.length)) {
                    version (NPeggedScannerMetrics) {
                        event.fastSuccess = true;
                        event.reason = ScannerReason.none;
                    }
                    s.steps += examined - pos + 1;
                    if (examined > end)
                        s.recordFailure(s.node(pos, examined, false));
                    return s.node(pos, end);
                } else static if (Check == 1 || (Check == 2 && !HasInnerRecords)) {
                    static if (Table.requireEnd) {
                        if (lastEofEnd != size_t.max && (examined < limit || limit == s.input.length)) {
                            version (NPeggedScannerMetrics) {
                                event.fastFailure = true;
                                event.reason = ScannerReason.none;
                            }
                            s.steps += examined - pos + 1;
                            auto result = s.node(pos, lastEofEnd, false);
                            result.failEnd = examined > lastEofEnd ? examined : lastEofEnd;
                            s.recordFailure(result);
                            return result;
                        }
                    } else {
                        if (examined < limit || limit == s.input.length) {
                            version (NPeggedScannerMetrics) {
                                event.fastFailure = true;
                                event.reason = ScannerReason.none;
                            }
                            s.steps += examined - pos + 1;
                            auto result = s.node(pos, examined, false);
                            result.failEnd = examined;
                            s.recordFailure(result);
                            return result;
                        }
                    }
                }
            } else version (NPeggedScannerMetrics) {
                if (s.status != Status.ok)
                    event.reason = ScannerReason.state;
                else if (pos > s.input.length)
                    event.reason = ScannerReason.position;
                else if (s.steps >= s.context.stepLimit)
                    event.reason = ScannerReason.steps;
                else if (ReferenceDepth && s.context.trace !is null)
                    event.reason = ScannerReason.trace;
                else
                    event.reason = ScannerReason.depth;
            }
        }
        version (NPeggedScannerMetrics) {
            event.original = true;
            auto result = Original(s, pos);
            const frontier = result.end > result.failEnd ? result.end : result.failEnd;
            event.originalBytes = frontier > pos ? frontier - pos : 0;
            event.replayedBytes = event.examinedBytes < event.originalBytes ? event.examinedBytes : event
                .originalBytes;
            return result;
        } else
            return Original(s, pos);
    }
}

/// S4: the cursor entry is `opCall` with the counters held by the caller, for every step limit.
@nogc nothrow unittest {
    import npegged.peg : oneOrMore, digit;

    enum Digits = () {
        CharSetMask mask;
        mask.addRange('0', '9');
        return compileDFA([
            RegularExpression(RegularKind.bytes, mask),
            RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
            RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
        ], 2);
    }();
    struct DigitsTable {
        enum automaton = Digits;
        enum valid = Digits.valid;
        enum requireEnd = Digits.requireEnd;
        enum diagnosticName = "Unit.Digits/_dfa_Digits";
    }

    alias token = dfaToken!(oneOrMore!digit, DigitsTable);
    alias deep = dfaToken!(oneOrMore!digit, DigitsTable, 2, false);
    static immutable string[5] inputs = ["", "x", "7", "1234", "12x"];
    static void sweep(Token)() @nogc nothrow {
        foreach (limit; 0 .. 9)
            foreach (depthLimit; 0 .. 4)
                foreach (input; inputs)
                    foreach (start; 0 .. input.length + 1)
                        foreach (depth; 0 .. 5) {
                            ParseContext context;
                            context.stepLimit = limit;
                            context.depthLimit = depthLimit;
                            State!(false, 1) reference;
                            State!(false, 1) cursor;
                            reference.context = context;
                            cursor.context = context;
                            reference.input = cursor.input = input;
                            reference.depth = depth;
                            // The cursor's depth lives in the caller; its shared copy may be stale.
                            cursor.depth = 99;
                            size_t steps = 0;
                            bool live = true;
                            size_t end, failEnd;
                            const expected = Token(reference, start);
                            const ok = Token.cursor(cursor, start, steps, live, depth, end, failEnd);
                            assert(ok == expected.successful && end == expected.end && failEnd == expected
                                    .failEnd);
                            assert(steps == reference.steps && live == (reference.status == Status.ok));
                            assert(cursor.status == reference.status);
                        }
    }

    sweep!token();
    sweep!deep();
}

@nogc nothrow unittest {
    import npegged.peg : ParseContext, check, parse, oneOrMore, digit;

    enum table = () {
        CharSetMask mask;
        mask.addRange('0', '9');
        return compileDFA([
            RegularExpression(RegularKind.bytes, mask),
            RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
            RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
        ], 2);
    }();
    alias token = dfaToken!(oneOrMore!digit, table);
    ParseContext context;
    auto limited = check!token(context, "123");
    assert(limited.successful && limited.end == 3);
    context.stepLimit = size_t.max;
    auto fast = check!token(context, "123x");
    assert(fast.successful && fast.end == 3 && fast.failEnd == 3);
    auto bad = check!token(context, "x");
    assert(!bad.successful && bad.failEnd == 0);
    auto tree = parse!token(context, "12");
    assert(tree.matches == ["1", "2"]);
}

@nogc nothrow unittest {
    import npegged.peg : ParseContext, check, zeroOrMore, option, and, literal, charClass;

    enum mask = CharSetMask.fromChars('a');
    enum table = compileDFA([
            regularByte(mask.bits[0], mask.bits[1], mask.bits[2], mask.bits[3]),
            regularByte(0, 0, 0, 0), regularNode(RegularKind.sequence, [0, 1]),
            regularNode(RegularKind.optional, [2]), regularNode(RegularKind.repetition, [3])
    ], 4);
    alias original = zeroOrMore!(option!(and!(literal!"a", charClass!(0, 0, 0, 0))));
    ParseContext context;
    auto baseline = check!original(context, "a!");
    auto compiled = check!(dfaToken!(original, table))(context, "a!");
    assert(baseline.successful && compiled.successful);
    assert(baseline.end == compiled.end && baseline.failEnd == compiled.failEnd);
}

@nogc nothrow unittest {
    import npegged.peg : Arena, ParseContext, State, Status, and, digit, eoi, literal, oneOrMore, or;
    import npegged.records : RecordBuffer;

    struct DigitsTable {
        enum automaton = () {
            CharSetMask mask;
            mask.addRange('0', '9');
            return compileDFA([
                RegularExpression(RegularKind.bytes, mask),
                RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
                RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
            ], 2);
        }();
        enum valid = automaton.valid;
        enum requireEnd = automaton.requireEnd;
        enum diagnosticName = "Unit.Digits/_dfa_Digits";
    }

    struct AnchoredTable {
        enum automaton = () {
            CharSetMask mask;
            mask.addRange('0', '9');
            return compileDFA([
                RegularExpression(RegularKind.bytes, mask),
                RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
                RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
            ], 2, true);
        }();
        enum valid = automaton.valid;
        enum requireEnd = automaton.requireEnd;
        enum diagnosticName = "Unit.Anchored/_dfa_Anchored";
    }

    struct PairTable {
        enum automaton = () {
            CharSetMask digits;
            digits.addRange('0', '9');
            const bang = CharSetMask.fromChars('!');
            return compileDFA([
                RegularExpression(RegularKind.bytes, digits),
                RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
                RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1]),
                RegularExpression(RegularKind.bytes, bang),
                RegularExpression(RegularKind.sequence, CharSetMask.init, [2, 3])
            ], 4);
        }();
        enum valid = automaton.valid;
        enum requireEnd = automaton.requireEnd;
        enum diagnosticName = "Unit.Pair/_dfa_Pair";
    }

    struct EscapeTable {
        enum automaton = () {
            CharSetMask slash = CharSetMask.fromChars('\\');
            CharSetMask esc = CharSetMask.fromChars('n', 't', '\\', '"');
            return compileDFA([
                RegularExpression(RegularKind.bytes, slash), RegularExpression(RegularKind.bytes,
                        esc), RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
            ], 2);
        }();
        enum valid = automaton.valid;
        enum requireEnd = automaton.requireEnd;
        enum diagnosticName = "Unit.Escape/_dfa_Escape";
    }

    alias FastDigits = dfaToken!(oneOrMore!digit, DigitsTable, 2, false);
    alias InnerDigits = dfaToken!(oneOrMore!digit, DigitsTable, 2, true);
    alias AnchoredDigits = dfaToken!(and!(oneOrMore!digit, eoi), AnchoredTable, 0, false);
    alias PairDigits = dfaToken!(and!(oneOrMore!digit, literal!"!"), PairTable, 0, false);

    alias EscapeRule = and!(literal!"\\", or!(literal!"n", literal!"t", literal!"\\", literal!"\""));
    alias FastEscape = dfaToken!(EscapeRule, EscapeTable, 2, false);
    alias InnerEscape = dfaToken!(EscapeRule, EscapeTable, 2, true);

    alias AltA = and!(FastDigits, literal!"!");
    alias AltB = and!(FastDigits, literal!"?");
    alias ChoiceDigits = or!(AltA, AltB);

    Arena arena;
    RecordBuffer records;
    records.arena = &arena;
    State!(false, 2) s;
    s.arena = &arena;
    s.attachRecords(records);

    // 1. Terminal fast-failure on EOF: failEnd == 0, 0 records
    s.input = "";
    auto rEof = FastDigits(s, 0);
    assert(!rEof.successful && rEof.failEnd == 0);
    assert(records.length == 0);

    // 2. Terminal fast-failure on mismatch: failEnd == 0, 0 records
    s.input = "abc";
    auto rMismatch = FastDigits(s, 0);
    assert(!rMismatch.successful && rMismatch.failEnd == 0);
    assert(records.length == 0);

    // 3. Failed escape sequence: mismatching escape char, failEnd == 1, 0 records
    s.input = "\\x";
    auto rFailEsc = FastEscape(s, 0);
    assert(!rFailEsc.successful && rFailEsc.failEnd == 1);
    assert(records.length == 0);

    // 4. Truncated escape sequence at EOF: failEnd == 1, 0 records
    s.input = "\\";
    auto rTruncEsc = FastEscape(s, 0);
    assert(!rTruncEsc.successful && rTruncEsc.failEnd == 1);
    assert(records.length == 0);

    // 5. Successful escape sequence: end == 2
    s.input = "\\n";
    auto rSuccEsc = FastEscape(s, 0);
    assert(rSuccEsc.successful && rSuccEsc.end == 2);

    // 6. Truncated pair at EOF: failEnd == 3, 0 records
    s.input = "123";
    auto rTruncPair = PairDigits(s, 0);
    assert(!rTruncPair.successful && rTruncPair.failEnd == 3);
    assert(records.length == 0);

    // 7. Anchored token failing at EOF requirement: failEnd == 3, 0 records
    s.input = "123x";
    auto rAnchored = AnchoredDigits(s, 0);
    assert(!rAnchored.successful && rAnchored.failEnd == 3);
    assert(records.length == 0);

    // 8. Backtracking with choice: first alt fast-fails without corrupting state, second alt succeeds
    s.input = "123?";
    auto rChoice = ChoiceDigits(s, 0);
    assert(rChoice.successful && rChoice.end == 4);

    // 9. Token WITH inner records (InnerDigits): falls back to combinator execution on failure
    s.input = "abc";
    auto rInnerFail = InnerDigits(s, 0);
    assert(!rInnerFail.successful && rInnerFail.failEnd == 0);
    assert(records.length == 0);

    s.input = "123";
    auto rInnerSucc = InnerDigits(s, 0);
    assert(rInnerSucc.successful && rInnerSucc.end == 3);

    // 10. Step budget edge: limits halt scan safely
    s.input = "12345";
    s.context.stepLimit = 2;
    auto rBudget = FastDigits(s, 0);
    assert(!rBudget.successful);
    s.context.stepLimit = size_t.max;
}

version (NPeggedScannerMetrics) @nogc nothrow unittest {
    import npegged.peg : Arena, ParseContext, ScannerReason, ScannerReport, ScannerStats, State,
        Status, and, digit, eoi, literal, oneOrMore, or;
    import npegged.records : RecordBuffer;

    static void noopTrace(string, size_t, bool, void*) @nogc nothrow {
    }

    struct DigitsTable {
        enum automaton = () {
            CharSetMask mask;
            mask.addRange('0', '9');
            return compileDFA([
                RegularExpression(RegularKind.bytes, mask),
                RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
                RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
            ], 2);
        }();
        enum valid = automaton.valid;
        enum requireEnd = automaton.requireEnd;
        enum diagnosticName = "Unit.Digits/_dfa_Digits";
    }

    struct AnchoredTable {
        enum automaton = () {
            CharSetMask mask;
            mask.addRange('0', '9');
            return compileDFA([
                RegularExpression(RegularKind.bytes, mask),
                RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
                RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
            ], 2, true);
        }();
        enum valid = automaton.valid;
        enum requireEnd = automaton.requireEnd;
        enum diagnosticName = "Unit.Anchored/_dfa_Anchored";
    }

    struct PairTable {
        enum automaton = () {
            CharSetMask digits;
            digits.addRange('0', '9');
            const bang = CharSetMask.fromChars('!');
            return compileDFA([
                RegularExpression(RegularKind.bytes, digits),
                RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
                RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1]),
                RegularExpression(RegularKind.bytes, bang),
                RegularExpression(RegularKind.sequence, CharSetMask.init, [2, 3])
            ], 4);
        }();
        enum valid = automaton.valid;
        enum requireEnd = automaton.requireEnd;
        enum diagnosticName = "Unit.Pair/_dfa_Pair";
    }

    struct EscapeTable {
        enum automaton = () {
            CharSetMask slash = CharSetMask.fromChars('\\');
            CharSetMask esc = CharSetMask.fromChars('n', 't', '\\', '"');
            return compileDFA([
                RegularExpression(RegularKind.bytes, slash), RegularExpression(RegularKind.bytes,
                        esc), RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
            ], 2);
        }();
        enum valid = automaton.valid;
        enum requireEnd = automaton.requireEnd;
        enum diagnosticName = "Unit.Escape/_dfa_Escape";
    }

    struct InvalidTable {
        enum automaton = Automaton.init;
        enum valid = false;
        enum requireEnd = false;
        enum diagnosticName = "Unit.Invalid/_dfa_Invalid";
    }

    alias FastToken = dfaToken!(oneOrMore!digit, DigitsTable, 2, false);
    alias InnerToken = dfaToken!(oneOrMore!digit, DigitsTable, 2, true);
    alias BadTableToken = dfaToken!(oneOrMore!digit, InvalidTable, 0, false);
    alias AnchoredToken = dfaToken!(and!(oneOrMore!digit, eoi), AnchoredTable, 0, false);
    alias PairToken = dfaToken!(and!(oneOrMore!digit, literal!"!"), PairTable, 0, false);

    alias EscapeRule = and!(literal!"\\", or!(literal!"n", literal!"t", literal!"\\", literal!"\""));
    alias FastEscape = dfaToken!(EscapeRule, EscapeTable, 2, false);
    alias InnerEscape = dfaToken!(EscapeRule, EscapeTable, 2, true);

    alias AltA = and!(FastToken, literal!"!");
    alias AltB = and!(FastToken, literal!"?");
    alias ChoiceToken = or!(AltA, AltB);

    ScannerStats[16] storage;
    ScannerReport report;
    report.rows = storage[];

    Arena arena;
    State!(false, 1) s1;
    s1.arena = &arena;
    s1.input = "123x";
    assert(FastToken.scan!false(s1, 0).successful);
    assert(FastToken(s1, 0).successful);

    s1.context.scannerReport = &report;
    assert(FastToken.scan!false(s1, 0).end == 3);
    assert(!FastToken.scan!false(s1, 3).successful);
    assert(report.total.reasons[ScannerReason.primitiveScan] == 2);
    assert(report.total.originalBytes == 3);

    State!(false, 0) s0;
    s0.arena = &arena;
    s0.input = "12";
    s0.context.scannerReport = &report;
    assert(FastToken(s0, 0).successful);
    assert(report.total.reasons[ScannerReason.tree] == 1);

    RecordBuffer records;
    records.arena = &arena;
    State!(false, 2) s2;
    s2.arena = &arena;
    s2.input = "12x";
    s2.context.scannerReport = &report;
    s2.attachRecords(records);
    assert(InnerToken(s2, 0).successful);
    assert(!PairToken(s2, 0).successful);
    assert(report.total.fastFailure == 1);
    assert(report.total.replays == 0);
    assert(!AnchoredToken(s2, 0).successful);
    assert(report.total.fastFailure == 2);
    assert(report.total.replays == 0);

    // EOF on fast terminal: fastFailure, 0 replays
    s2.input = "";
    auto rEof = FastToken(s2, 0);
    assert(!rEof.successful && rEof.failEnd == 0);
    assert(records.length == 0);
    assert(report.total.fastFailure == 3);
    assert(report.total.replays == 0);

    // Failed escape sequence: fastFailure, 0 replays, exact failEnd == 1
    s2.input = "\\x";
    auto rFailEsc = FastEscape(s2, 0);
    assert(!rFailEsc.successful && rFailEsc.failEnd == 1);
    assert(records.length == 0);
    assert(report.total.fastFailure == 4);
    assert(report.total.replays == 0);

    // Truncated escape sequence at EOF: fastFailure, 0 replays, exact failEnd == 1
    s2.input = "\\";
    auto rTruncEsc = FastEscape(s2, 0);
    assert(!rTruncEsc.successful && rTruncEsc.failEnd == 1);
    assert(records.length == 0);
    assert(report.total.fastFailure == 5);
    assert(report.total.replays == 0);

    // Successful escape sequence: fastSuccess
    s2.input = "\\n";
    auto rSuccEsc = FastEscape(s2, 0);
    assert(rSuccEsc.successful && rSuccEsc.end == 2);
    assert(report.total.fastSuccess == 1);

    // Backtracking with choice: first alt succeeds scanning prefix, then fails on literal, second alt succeeds without replay
    s2.input = "123?";
    auto rChoice = ChoiceToken(s2, 0);
    assert(rChoice.successful && rChoice.end == 4);
    assert(report.total.fastFailure == 5);
    assert(report.total.replays == 0);

    // Token WITH inner records (InnerToken): failed scan MUST fall back to combinator execution
    s2.input = "abc";
    const prevFastFailure = report.total.fastFailure;
    const prevReplays = report.total.replays;
    const prevInnerRecords = report.total.reasons[ScannerReason.innerRecords];
    auto rInnerFail = InnerToken(s2, 0);
    assert(!rInnerFail.successful && rInnerFail.failEnd == 0);
    assert(records.length == 0);
    assert(report.total.fastFailure == prevFastFailure);
    assert(report.total.replays == prevReplays);
    assert(report.total.reasons[ScannerReason.innerRecords] == prevInnerRecords + 1);

    assert(BadTableToken(s1, 0).successful);
    assert(report.total.reasons[ScannerReason.invalidTable] == 1);

    // Guard reason precedence: state > position > steps > trace > depth.
    s1 = State!(false, 1).init;
    s1.arena = &arena;
    s1.input = "12";
    s1.context.scannerReport = &report;
    s1.status = Status.resourceLimit;
    s1.steps = s1.context.stepLimit;
    s1.context.trace = &noopTrace;
    s1.depth = s1.context.depthLimit + 1;
    cast(void)FastToken(s1, 99);
    assert(report.total.reasons[ScannerReason.state] == 1);

    s1.status = Status.ok;
    cast(void)FastToken(s1, 99);
    assert(report.total.reasons[ScannerReason.position] == 1);

    s1.status = Status.ok;
    s1.steps = s1.context.stepLimit;
    cast(void)FastToken(s1, 0);
    assert(report.total.reasons[ScannerReason.steps] == 1);

    s1.steps = 0;
    s1.status = Status.ok;
    cast(void)FastToken(s1, 0);
    assert(report.total.reasons[ScannerReason.trace] == 1);

    s1.context.trace = null;
    s1.steps = 0;
    s1.status = Status.ok;
    cast(void)FastToken(s1, 0);
    assert(report.total.reasons[ScannerReason.depth] == 1);

    s1.depth = s1.context.depthLimit;
    s1.steps = 0;
    s1.status = Status.ok;
    cast(void)FastToken(s1, 0);
    assert(report.total.reasons[ScannerReason.depth] == 2);

    // Terminal fastSuccess, fastFailure (anchored/unanchored), failureDiagnostic, and budgetEdge.
    s1 = State!(false, 1).init;
    s1.arena = &arena;
    s1.context.scannerReport = &report;
    s1.input = "123";
    assert(FastToken(s1, 0).end == 3);
    s1.input = "123x";
    assert(FastToken(s1, 0).end == 3);
    s1.input = "x";
    assert(!FastToken(s1, 0).successful);
    s1.input = "12x";
    assert(!AnchoredToken(s1, 0).successful);
    s1.input = "x";
    assert(!AnchoredToken(s1, 0).successful);

    s1.input = "1234";
    s1.status = Status.ok;
    s1.steps = 0;
    s1.context.stepLimit = 3; // remaining = 2 < available = 4 -> budgetEdge
    cast(void)FastToken(s1, 0);
    s1.input = "12!";
    s1.status = Status.ok;
    s1.steps = 0;
    s1.context.stepLimit = 2; // remaining = 1 < available = 3 -> budgetEdge on rejected scan
    cast(void)PairToken(s1, 0);
    s1.input = "12";
    s1.status = Status.ok;
    s1.steps = 0;
    s1.context.stepLimit = 2;
    cast(void)AnchoredToken(s1, 0);
    assert(report.total.fastSuccess >= 2 && report.total.fastFailure >= 2);
    assert(report.total.reasons[ScannerReason.budgetEdge] >= 3);
    assert(!report.truncated);
    ulong sumCalls;
    foreach (row; report.rows[0 .. report.length])
        sumCalls += row.calls;
    assert(sumCalls == report.total.calls);
}

/// Whole-DFA entry with the exact rule/scanner budget. False requests exact replay.
/// The caller proves a non-memoized, reference-free rule and supplies a fresh result.
pragma(inline, true) bool tryDFAEntry(alias Original, alias Table)(ref ParseContext context,
        scope string input, ref CheckResult result) @nogc nothrow {
    version (NPeggedMetrics)
        return false;
    else version (NPeggedRuleMetrics)
        return false;
    else version (NPeggedScannerMetrics)
        return false;
    else version (NPeggedDependencyTrace)
        return false;
    else static if (!Table.valid)
        return false;
    else {
        // Entry savings target bounded tiny inputs. Keep throughput scanners on
        // the established path: the broad clone regressed long-input codegen.
        if (input.length > 8 || context.trace !is null || context.depthLimit == 0 || context
                .stepLimit < 2)
            return false;
        // One rule tick, then the scanner's examined-bytes-plus-one charge.
        const remaining = context.stepLimit - 2;
        const limit = remaining < input.length ? remaining : input.length;
        size_t examined, lastEofEnd;
        const end = scanDFA!Table(input[0 .. limit], 0, examined, lastEofEnd);
        result.arena.limit = context.memoryLimit;
        if (examined < limit || limit == input.length) {
            if (end != size_t.max) {
                result.status = Status.ok;
                result.successful = true;
                result.end = end;
                result.failEnd = examined > end ? examined : end;
                return true;
            }
            static if (!Table.requireEnd) {
                result.status = Status.mismatch;
                result.end = result.failEnd = examined;
                return true;
            } else if (lastEofEnd != size_t.max) {
                result.status = Status.mismatch;
                result.end = lastEofEnd;
                result.failEnd = examined > lastEofEnd ? examined : lastEofEnd;
                return true;
            }
        }
        // Match dfaToken's exact replay without scanning a second time.
        State!(false, 1) state;
        state.arena = &result.arena;
        state.input = input;
        state.context = context;
        state.steps = 1;
        state.depth = 1;
        auto node = state.finish(Original(state, 0));
        result.status = state.status != Status.ok ? state.status : node.successful ? Status.ok : Status
            .mismatch;
        result.successful = result.status == Status.ok;
        result.end = node.end;
        result.failEnd = node.failEnd;
        return true;
    }
}

@nogc nothrow unittest {
    import npegged.peg : oneOrMore, literal, and, eoi, check;

    enum plain = () {
        CharSetMask mask;
        mask.addChar('a');
        return compileDFA([
            RegularExpression(RegularKind.bytes, mask),
            RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
            RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
        ], 2);
    }();
    enum anchored = () {
        CharSetMask mask;
        mask.addChar('a');
        return compileDFA([
            RegularExpression(RegularKind.bytes, mask),
            RegularExpression(RegularKind.repetition, CharSetMask.init, [0]),
            RegularExpression(RegularKind.sequence, CharSetMask.init, [0, 1])
        ], 2, true);
    }();
    static void verify(alias Original, alias Table)(string input) @nogc nothrow {
        static State!(false, 1).Node reference(ref State!(false, 1) state, size_t pos) @nogc nothrow {
            return state.rule!(dfaToken!(Original, Table), "Entry", false)(pos);
        }

        foreach (limit; 0 .. 16) {
            ParseContext context;
            context.stepLimit = limit;
            context.memoryLimit = 0;
            auto expected = check!reference(context, input);
            CheckResult actual;
            if (tryDFAEntry!(Original, Table)(context, input, actual)) {
                assert(actual.status == expected.status && actual.successful == expected.successful);
                assert(actual.end == expected.end && actual.failEnd == expected.failEnd);
                assert(actual.arena.allocationCalls == expected.arena.allocationCalls);
            } else {
                assert(actual.status == Status.invalidInput && !actual.successful);
                assert(actual.arena.allocationCalls == 0);
            }
        }
    }

    foreach (input; ["", "a", "aaa", "aaaaaaaa", "aaaaaaaaa", "!", "a!", "a\0", "\xFF"]) {
        verify!(oneOrMore!(literal!"a"), plain)(input);
        verify!(and!(oneOrMore!(literal!"a"), eoi), anchored)(input);
    }
    ParseContext context;
    CheckResult result;
    enum invalid = Automaton.init;
    assert(!tryDFAEntry!(literal!"a", invalid)(context, "a", result));
    context.depthLimit = 0;
    assert(!tryDFAEntry!(oneOrMore!(literal!"a"), plain)(context, "a", result));
    context.depthLimit = 1;
    context.trace = (string, size_t, bool, void*) @nogc nothrow{};
    assert(!tryDFAEntry!(oneOrMore!(literal!"a"), plain)(context, "a", result));
}
