/** Cold CTFE Thompson/subset compiler and allocation-free byte scanner.
    Callers must establish equivalence between PEG and regular-language semantics. */
module npegged.dfa;

import npegged.peg : CharSetMask, State, Status;

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
}

/// Hoist a state's self-loop byte class out of its inner scanner loop.
/// This preserves DFA semantics while removing a dependent table read per byte.
pragma(inline, true) size_t scanDFA(alias Table)(scope string input, size_t pos,
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
        ubyte state;
        size_t end = automaton.accepting[0] ? pos : size_t.max;
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

version (NPeggedScannerMetrics) @nogc nothrow unittest {
    import npegged.peg : Arena, ParseContext, ScannerReason, ScannerReport, ScannerStats, State,
        Status, and, digit, eoi, literal, oneOrMore;
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

    ScannerStats[8] storage;
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
