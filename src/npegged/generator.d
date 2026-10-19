/** Cold, seeded candidate generator for PEG grammars (G1). No parser is involved: a walk of the expression
    graph *proposes* strings. A proposal is NOT known to be accepted (ordered choice, greedy repetition and
    predicates make that undecidable by walking); G2 filters candidates through the real parser.

    PRNG: splitmix64 seeded from `GeneratorOptions.seed`; one 64-bit state, fully deterministic and portable.
    Streams are reproducible: the same grammar, start rule, options and seed give the same candidates.

    Repetition lengths are skewed on purpose: `e*` is empty with probability 1/4, otherwise 1 + a geometric tail
    (each extra repeat with probability 1/2) capped at `maxRepeat`; one repetition in 32 may instead reach up to
    4 * maxRepeat. `e?` is taken with probability 1/2. Choices are uniform (weights arrive with G4).

    Termination: past `softDepth` a choice takes its alternative with the smallest minimal output length, so any
    productive grammar finishes; `maxDepth` is a hard stop, as is `maxOutput` bytes. Hitting a budget or an
    unsupported construct yields a status, never an unmarked candidate.
*/
module npegged.generator;
import npegged.analysis;
import npegged.bites : BitesAnalysis;
import npegged.peg : CharSetMask;

nothrow:

enum GenStatus : ubyte {
    ok,
    unsupported, /// the walk met a construct it cannot propose input for
    budgetExceeded /// depth or output budget hit
}

struct GeneratorOptions {
    ulong seed = 1;
    size_t maxDepth = 48;
    size_t softDepth = 12;
    size_t maxOutput = 4096;
    size_t maxRepeat = 8;
}

struct Candidate {
    GenStatus status;
    string text;
    string reason; /// why generation failed, when it did
}

private ulong splitmix(ref ulong state) @nogc pure {
    state += 0x9E3779B97F4A7C15UL;
    ulong z = state;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
    return z ^ (z >> 31);
}

@nogc pure nothrow unittest {
    ulong a = 1, b = 1, c = 2;
    assert(splitmix(a) == splitmix(b) && splitmix(a) == splitmix(b));
    ulong first = 1;
    assert(splitmix(first) == 0x910A2DEC89025CC1UL); // splitmix64 reference value for seed 1
    assert(splitmix(c) != splitmix(first));
}

private enum size_t infinite = size_t.max / 4;

struct CandidateGenerator {
nothrow:
    private GrammarAnalysis* graph;
    private GeneratorOptions options;
    private size_t startRule;
    private ulong state;
    private size_t[] minimal; // minimal output length per expression, `infinite` when none
    private bool failed;
    private string failure;
    private GenStatus failureStatus;
    private char[] output;

    this(ref GrammarAnalysis graph, size_t startRule, GeneratorOptions options = GeneratorOptions
            .init) {
        this.graph = &graph;
        this.options = options;
        this.startRule = startRule;
        this.state = options.seed;
        computeMinimal();
    }

    private ulong roll() {
        return splitmix(state);
    }

    private bool chance(ulong numerator, ulong denominator) {
        return roll() % denominator < numerator;
    }

    /// Smallest output length of every expression, by fixed point from "infinite".
    private void computeMinimal() {
        const count = graph.expressions.length;
        minimal = new size_t[count];
        minimal[] = infinite;
        bool changed = true;
        while (changed) {
            changed = false;
            foreach (index; 0 .. count) {
                auto node = graph.expressions[index];
                size_t value = infinite;
                final switch (node.kind) {
                case ExpressionKind.unknown:
                    break;
                case ExpressionKind.terminal:
                    value = terminalLength(node);
                    break;
                case ExpressionKind.reference:
                    const rule = graph.referenceRule(node);
                    if (rule != size_t.max)
                        value = minimal[graph.roots[rule]];
                    break;
                case ExpressionKind.sequence:
                    value = 0;
                    foreach (child; node.children)
                        value = add(value, minimal[child]);
                    break;
                case ExpressionKind.choice:
                    foreach (child; node.children)
                        value = minimal[child] < value ? minimal[child] : value;
                    break;
                case ExpressionKind.optional:
                case ExpressionKind.repetition:
                case ExpressionKind.predicate:
                    value = 0;
                    break;
                case ExpressionKind.wrapper:
                    value = node.children.length ? minimal[node.children[0]] : infinite;
                    break;
                }
                if (value < minimal[index]) {
                    minimal[index] = value;
                    changed = true;
                }
            }
        }
    }

    private static size_t add(size_t a, size_t b) @nogc {
        return a >= infinite || b >= infinite ? infinite : a + b;
    }

    /// Bytes a terminal produces, or `infinite` when this module cannot propose input for it.
    private size_t terminalLength(ref Expression node) {
        string text;
        if (literalBytes(node.source, text))
            return text.length;
        if (node.source == "eps" || node.source == "eoi" || node.source == "endOfInput")
            return 0;
        if (node.byteTerminal && node.byteWidth == 1 && node.known && !node.alphabet.empty)
            return 1;
        return infinite;
    }

    /// Decode `literal!("...")` including the simple escapes; anything else is not supported.
    static bool literalBytes(string source, out string bytes) {
        enum head = "literal!(";
        if (source.length < head.length + 3 || source[0 .. head.length] != head)
            return false;
        size_t at = head.length;
        const quote = source[at++];
        if (quote != '"' && quote != '\'')
            return false;
        while (at < source.length && source[at] != quote) {
            if (source[at] != '\\') {
                bytes ~= source[at++];
                continue;
            }
            if (at + 1 >= source.length)
                return false;
            const escape = source[at + 1];
            at += 2;
            switch (escape) {
            case 'n':
                bytes ~= '\n';
                break;
            case 't':
                bytes ~= '\t';
                break;
            case 'r':
                bytes ~= '\r';
                break;
            case '0':
                bytes ~= '\0';
                break;
            case '\\':
            case '"':
            case '\'':
                bytes ~= escape;
                break;
            case 'x':
                if (at + 1 >= source.length)
                    return false;
                int value;
                foreach (digit; source[at .. at + 2]) {
                    const v = digit >= '0' && digit <= '9' ? digit - '0' : digit >= 'a' && digit <= 'f'
                        ? digit - 'a' + 10 : digit >= 'A' && digit <= 'F' ? digit - 'A' + 10 : -1;
                    if (v < 0)
                        return false;
                    value = value * 16 + v;
                }
                at += 2;
                bytes ~= cast(char)value;
                break;
            default:
                return false;
            }
        }
        return at + 1 < source.length && source[at + 1] == ')';
    }

    private void fail(GenStatus status, string reason) {
        if (!failed) {
            failed = true;
            failureStatus = status;
            failure = reason;
        }
    }

    private void emit(string text) {
        if (output.length + text.length > options.maxOutput)
            fail(GenStatus.budgetExceeded, "output budget exceeded");
        else
            output ~= text;
    }

    private void walk(size_t index, size_t depth) {
        if (failed)
            return;
        if (depth > options.maxDepth) {
            fail(GenStatus.budgetExceeded, "recursion depth budget exceeded");
            return;
        }
        auto node = graph.expressions[index];
        final switch (node.kind) {
        case ExpressionKind.unknown:
            fail(GenStatus.unsupported,
                    "unknown or unsupported node (action, parameter, external)");
            return;
        case ExpressionKind.terminal:
            string text;
            if (literalBytes(node.source, text))
                emit(text);
            else if (node.source == "eps" || node.source == "eoi" || node.source == "endOfInput") {
            } else if (node.byteTerminal && node.byteWidth == 1 && node.known && !node.alphabet.empty) {
                size_t members;
                foreach (c; 0 .. 256)
                    members += node.alphabet.contains(cast(char)c);
                size_t pick = roll() % members;
                foreach (c; 0 .. 256)
                    if (node.alphabet.contains(cast(char)c)) {
                        if (pick == 0) {
                            emit([cast(char)c].idup);
                            break;
                        }
                        --pick;
                    }
            } else
                fail(GenStatus.unsupported, "terminal without a byte description: " ~ node.source);
            return;
        case ExpressionKind.reference:
            const rule = graph.referenceRule(node);
            if (rule == size_t.max)
                fail(GenStatus.unsupported, "unresolved reference: " ~ node.reference);
            else
                walk(graph.roots[rule], depth + 1);
            return;
        case ExpressionKind.sequence:
            foreach (child; node.children)
                walk(child, depth);
            return;
        case ExpressionKind.choice:
            if (!node.children.length) {
                fail(GenStatus.unsupported, "empty choice never succeeds");
                return;
            }
            size_t chosen;
            if (depth >= options.softDepth) {
                // Terminate: take the cheapest alternative, ties broken by the stream.
                size_t best = infinite + 1, ties;
                foreach (i, child; node.children) {
                    if (minimal[child] < best) {
                        best = minimal[child];
                        chosen = i;
                        ties = 1;
                    } else if (minimal[child] == best && roll() % ++ties == 0)
                        chosen = i;
                }
            } else
                chosen = roll() % node.children.length;
            walk(node.children[chosen], depth + 1);
            return;
        case ExpressionKind.optional:
            if (depth < options.softDepth && chance(1, 2))
                walk(node.children[0], depth + 1);
            return;
        case ExpressionKind.repetition:
            repeat(node.children[0], 0, depth);
            return;
        case ExpressionKind.predicate:
            return; // zero-width: the oracle decides whether the surrounding sequence is accepted
        case ExpressionKind.wrapper:
            if (node.combinator == "oneOrMore")
                repeat(node.children[0], 1, depth);
            else if (node.children.length)
                walk(node.children[0], depth);
            return;
        }
    }

    private void repeat(size_t body, size_t least, size_t depth) {
        size_t count = least;
        if (depth < options.softDepth) {
            const longRun = chance(1, 32);
            const cap = longRun ? options.maxRepeat * 4 : options.maxRepeat;
            if (least == 0) {
                if (!chance(1, 4)) {
                    count = 1;
                    while (count < cap && chance(1, 2))
                        ++count;
                }
            } else
                while (count < cap && chance(1, 2))
                    ++count;
        }
        size_t emptyRounds;
        foreach (i; 0 .. count) {
            const before = output.length;
            walk(body, depth + 1);
            if (output.length == before && ++emptyRounds >= 2)
                return; // a nullable body made no progress twice: stop looping
        }
    }

    /// Next candidate of the stream (always consumes randomness, also on failure).
    Candidate next() {
        failed = false;
        failure = null;
        output = null;
        walk(graph.roots[startRule], 0);
        Candidate result;
        result.status = failed ? failureStatus : GenStatus.ok;
        result.reason = failure;
        result.text = failed ? null : cast(string)output.idup;
        return result;
    }
}

version (unittest) {
    private Expression lit(string text) {
        Expression e;
        e.kind = ExpressionKind.terminal;
        e.known = true;
        e.nullable = Nullable.no;
        e.source = "literal!(\"" ~ text ~ "\")";
        return e;
    }
}

nothrow unittest {
    alias K = ExpressionKind;
    GrammarAnalysis graph;
    graph.names = ["Root", "R"];
    graph.expressions = [
        lit("ab"), // 0
        Expression(K.repetition, [0]), // 1
        Expression(K.sequence, [1, 0]), // 2: ('ab')* 'ab'
        Expression(K.reference, null, "R"), // 3
        lit("x"), // 4
        Expression(K.sequence, [4, 3]), // 5: 'x' R
        lit("y"), // 6
        Expression(K.choice, [5, 6]), // 7: R <- 'x' R / 'y'
        Expression(K.unknown), // 8
    ];
    graph.roots = [2, 7];
    graph.solve();
    // determinism and divergence
    auto one = CandidateGenerator(graph, 0);
    auto two = CandidateGenerator(graph, 0);
    GeneratorOptions other;
    other.seed = 99;
    auto three = CandidateGenerator(graph, 0, other);
    string[] a, b, c;
    foreach (i; 0 .. 40) {
        a ~= one.next().text;
        b ~= two.next().text;
        c ~= three.next().text;
    }
    assert(a == b && a != c);
    foreach (text; a)
        assert(text.length >= 2 && text.length % 2 == 0 && text[$ - 2 .. $] == "ab");
    // repetition lengths are skewed and include the minimal one
    bool sawShort, sawLong;
    foreach (text; a) {
        sawShort = sawShort || text.length == 2;
        sawLong = sawLong || text.length >= 8;
    }
    assert(sawShort && sawLong);
    // right recursion terminates and respects the budgets
    GeneratorOptions deep;
    deep.softDepth = 3;
    auto recursive = CandidateGenerator(graph, 1, deep);
    foreach (i; 0 .. 200) {
        auto candidate = recursive.next();
        assert(candidate.status == GenStatus.ok && candidate.text.length < 64);
        assert(candidate.text[$ - 1] == 'y');
    }
    // hard output stop reports a status, never a truncated candidate
    GeneratorOptions tiny;
    tiny.maxOutput = 1;
    auto bounded = CandidateGenerator(graph, 0, tiny);
    auto over = bounded.next();
    assert(over.status == GenStatus.budgetExceeded && over.text is null);
}

nothrow unittest {
    // minimal lengths, unsupported nodes, nullable loop termination, literal escapes
    alias K = ExpressionKind;
    GrammarAnalysis graph;
    graph.names = ["Unknown", "Loop", "Escapes"];
    graph.expressions = [
        Expression(K.unknown), // 0
        Expression(K.terminal), // 1 placeholder (eps)
        Expression(K.optional, [1]), // 2
        Expression(K.repetition, [2]), // 3: (eps?)*  nullable body
        Expression(K.terminal), // 4: escapes
    ];
    graph.expressions[1].source = "eps";
    graph.expressions[1].known = true;
    graph.expressions[1].nullable = Nullable.yes;
    graph.expressions[4].source = "literal!(\"a\\n\\x41\\\\\")";
    graph.expressions[4].known = true;
    graph.roots = [0, 3, 4];
    graph.solve();
    auto unsupported = CandidateGenerator(graph, 0).next();
    assert(unsupported.status == GenStatus.unsupported && unsupported.reason.length);
    auto loop = CandidateGenerator(graph, 1);
    foreach (i; 0 .. 50)
        assert(loop.next().text.length == 0); // terminates, produces the empty string
    auto escapes = CandidateGenerator(graph, 2).next();
    assert(escapes.status == GenStatus.ok && escapes.text == "a\nA\\");
    string bytes;
    assert(!CandidateGenerator.literalBytes("literal!(\"\\u00e9\")", bytes));
    assert(CandidateGenerator.literalBytes("literal!(\"\xc3\xa9\")", bytes) && bytes == "\xc3\xa9");
}
