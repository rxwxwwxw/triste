/** Report-only BITES machinery (B2-B5). Consumes the expression graph; changes no generated code.

    SUCC(e): sound *lower* approximation of the inputs on which e succeeds.
    NULL(e): sound *upper* approximation of the inputs on which e may succeed consuming nothing.
    Unknown, unsupported, recursive or budget-exceeded cases degrade in the sound direction:
    SUCC -> empty, NULL -> universal. See docs/BITES.md for the contract and scope.
*/
module npegged.bites;
import npegged.analysis;
import npegged.language;
import npegged.peg : CharSetMask;

nothrow:

/// Terminal languages shared by every approximation.
private struct TerminalShape {
    bool exact; // SUCC is exactly `succ`
    InputLanguage succ;
    bool zeroWidth; // eps/eoi/empty literal: never bites
    InputLanguage nullable; // inputs where the terminal may succeed empty
    bool known;
}

struct BitesAnalysis {
nothrow:
    GrammarAnalysis* graph;
    Budget budget;
    private InputLanguage[] succMemo, nullMemo;
    private bool[] succDone, nullDone, succActive, nullActive;

    this(ref GrammarAnalysis graph, Budget budget = Budget.init) {
        this.graph = &graph;
        this.budget = budget;
        const count = graph.expressions.length;
        succMemo = new InputLanguage[count];
        nullMemo = new InputLanguage[count];
        succDone = new bool[count];
        nullDone = new bool[count];
        succActive = new bool[count];
        nullActive = new bool[count];
    }

    /// Lower approximation: an overflowed language is replaced by the empty one.
    private InputLanguage lower(InputLanguage value) {
        return value.overflow ? InputLanguage.empty() : value;
    }

    /// Upper approximation: an overflowed language is replaced by the universal one.
    private InputLanguage upper(InputLanguage value) {
        return value.overflow ? InputLanguage.universal() : value;
    }

    static string plainLiteral(string source) {
        // Only escape-free literals are decoded; anything else falls back to FIRST bytes.
        enum head = "literal!(";
        if (source.length < head.length + 3 || source[0 .. head.length] != head)
            return null;
        size_t start = head.length;
        if (source[start] != '"' && source[start] != '\'')
            return null;
        const quote = source[start++];
        string text;
        while (start < source.length && source[start] != quote) {
            if (source[start] == '\\')
                return null;
            text ~= source[start++];
        }
        return start + 1 < source.length && source[start + 1] == ')' ? text : null;
    }

    private TerminalShape terminal(ref Expression node) {
        TerminalShape shape;
        shape.succ = InputLanguage.empty();
        shape.nullable = InputLanguage.universal();
        const source = node.source;
        if (source == "eps") {
            shape.known = shape.exact = shape.zeroWidth = true;
            shape.succ = InputLanguage.universal();
        } else if (source == "eoi" || source == "endOfInput") {
            shape.known = shape.exact = shape.zeroWidth = true;
            shape.succ = InputLanguage.endOfInput();
            shape.nullable = shape.succ;
        } else if (source == "fail") {
            shape.known = shape.exact = true;
            shape.nullable = InputLanguage.empty();
        } else if (auto text = plainLiteral(source)) {
            shape.known = true;
            if (text.length == 0) {
                shape.exact = shape.zeroWidth = true;
                shape.succ = InputLanguage.universal();
            } else {
                shape.exact = true;
                shape.succ = InputLanguage.prefix(text);
                shape.nullable = InputLanguage.empty();
            }
        } else if (node.known && node.byteTerminal && node.byteWidth == 1 && node.nullable == Nullable
                .no) {
            shape.known = shape.exact = true;
            shape.succ = InputLanguage.bytePrefix(node.alphabet);
            shape.nullable = InputLanguage.empty();
        } else if (node.known && node.nullable == Nullable.no) {
            // Consuming terminal we cannot describe exactly: SUCC stays empty, NULL is proven empty.
            shape.known = true;
            shape.nullable = InputLanguage.empty();
        }
        return shape;
    }

    /// Lower approximation of the inputs on which `index` succeeds.
    InputLanguage succ(size_t index) {
        if (index >= graph.expressions.length)
            return InputLanguage.empty();
        if (succDone[index])
            return succMemo[index];
        if (succActive[index])
            return InputLanguage.empty(); // recursion: sound bottom
        succActive[index] = true;
        scope (exit)
            succActive[index] = false;
        auto node = graph.expressions[index];
        InputLanguage result = InputLanguage.empty();
        final switch (node.kind) {
        case ExpressionKind.unknown:
            break;
        case ExpressionKind.terminal:
            result = terminal(node).succ;
            break;
        case ExpressionKind.reference:
            const rule = graph.referenceRule(node);
            if (rule != size_t.max)
                result = succ(graph.roots[rule]);
            break;
        case ExpressionKind.sequence:
            if (!node.children.length)
                result = InputLanguage.universal();
            else if (node.children.length == 1)
                result = succ(node.children[0]);
            break; // longer sequences: the paper's SUCC(other) = empty (precision work is B7)
        case ExpressionKind.choice:
            foreach (child; node.children)
                result = lower(result.unionWith(succ(child), budget));
            break;
        case ExpressionKind.optional:
        case ExpressionKind.repetition:
            result = InputLanguage.universal(); // e? and e* succeed on every input
            break;
        case ExpressionKind.predicate:
            // &e succeeds wherever e does; !e has no lower approximation here.
            if (node.combinator == "posLookahead")
                result = succ(node.children[0]);
            break;
        case ExpressionKind.wrapper:
            // oneOrMore e succeeds where e succeeds; other wrappers are transparent.
            result = succ(node.children[0]);
            break;
        }
        succDone[index] = true;
        succMemo[index] = result;
        return result;
    }

    /// Upper approximation of the inputs on which `index` may succeed without consuming input.
    InputLanguage nul(size_t index) {
        if (index >= graph.expressions.length)
            return InputLanguage.universal();
        if (nullDone[index])
            return nullMemo[index];
        if (nullActive[index])
            return InputLanguage.universal(); // recursion: sound top
        nullActive[index] = true;
        scope (exit)
            nullActive[index] = false;
        auto node = graph.expressions[index];
        InputLanguage result = InputLanguage.universal();
        // Facts can prove non-nullability regardless of the structure below.
        const proven = index < graph.facts.length && graph.facts[index].known
            && graph.facts[index].nullable == Nullable.no;
        if (proven) {
            result = InputLanguage.empty();
        } else
            final switch (node.kind) {
        case ExpressionKind.unknown:
            break;
        case ExpressionKind.terminal:
            result = terminal(node).nullable;
            break;
        case ExpressionKind.reference:
            const rule = graph.referenceRule(node);
            if (rule != size_t.max)
                result = nul(graph.roots[rule]);
            break;
        case ExpressionKind.sequence:
            foreach (child; node.children)
                result = upper(result.intersect(nul(child), budget));
            break;
        case ExpressionKind.choice:
            result = InputLanguage.empty();
            foreach (child; node.children)
                result = upper(result.unionWith(nul(child), budget));
            break;
        case ExpressionKind.optional:
        case ExpressionKind.repetition:
            break; // Σ*
        case ExpressionKind.predicate:
            if (node.combinator == "negLookahead"
                    || node.combinator == "predictiveNot")
                result = upper(succ(node.children[0]).complement());
            break; // &e: Σ* (an upper bound on where e succeeds is not available)
        case ExpressionKind.wrapper:
            result = nul(node.children[0]);
            break;
        }
        nullDone[index] = true;
        nullMemo[index] = result;
        return result;
    }
}

version (unittest) {
    private struct Fixture {
        GrammarAnalysis graph;
        Expression[] nodes;
    }

    private Expression lit(string text) {
        Expression e;
        e.kind = ExpressionKind.terminal;
        e.known = true;
        e.nullable = Nullable.no;
        e.source = "literal!(\"" ~ text ~ "\")";
        e.first.addChar(text[0]);
        return e;
    }

    private Expression plain(string source, Nullable nullable) {
        Expression e;
        e.kind = ExpressionKind.terminal;
        e.known = true;
        e.nullable = nullable;
        e.source = source;
        return e;
    }

    private Expression composite(ExpressionKind kind, string combinator, size_t[] children) {
        Expression e;
        e.kind = kind;
        e.combinator = combinator;
        e.children = children;
        return e;
    }
}

nothrow unittest {
    alias K = ExpressionKind;
    GrammarAnalysis graph;
    graph.names = ["Root"];
    graph.expressions = [
        lit("abc"), // 0
        plain("eps", Nullable.yes), // 1
        plain("eoi", Nullable.yes), // 2
        composite(K.choice, "or", [0, 1]), // 3: 'abc' / eps
        composite(K.predicate, "negLookahead", [0]), // 4: !'abc'
        composite(K.predicate, "posLookahead", [0]), // 5: &'abc'
        composite(K.optional, "option", [0]), // 6
        composite(K.repetition, "zeroOrMore", [0]), // 7
        composite(K.sequence, "and", [4, 0]), // 8: !'abc' 'abc'
        Expression(K.unknown), // 9
        composite(K.sequence, "and", [6, 1]), // 10: 'abc'? eps (nullable sequence)
        composite(K.choice, "or", [0, 9]), // 11: unknown arm
        plain("fail", Nullable.no), // 12
    ];
    graph.roots = [3];
    graph.solve();
    auto bites = BitesAnalysis(graph);
    // terminal prefix
    assert(bites.succ(0).contains("abcd") && !bites.succ(0).contains("ab") && !bites.succ(0).contains(
            ""));
    assert(bites.nul(0).emptiness() == Proof.provenEmpty);
    // ordered choice union; eps arm makes it succeed on everything and be nullable everywhere
    assert(bites.succ(3).contains("") && bites.succ(3).contains("zzz"));
    assert(bites.nul(3).contains("") && bites.nul(3).contains("abc"));
    // eps / eoi
    assert(bites.succ(1).contains("q") && bites.nul(1).contains("q"));
    assert(bites.succ(2).contains("") && !bites.succ(2).contains("a"));
    assert(bites.nul(2).contains("") && !bites.nul(2).contains("a"));
    // !'abc': nullable exactly where 'abc' certainly does not succeed
    assert(bites.nul(4).contains("abd") && bites.nul(4).contains("") && !bites.nul(4).contains("abcd"));
    assert(bites.succ(4).emptiness() == Proof.provenEmpty); // no lower approximation
    // &'abc': succeeds where 'abc' does; nullable bound stays universal
    assert(bites.succ(5).contains("abcz") && !bites.succ(5).contains("abd"));
    assert(bites.nul(5).contains("zzz"));
    // optional/star succeed everywhere and may be empty
    assert(bites.succ(6).contains("x") && bites.nul(6).contains("x"));
    assert(bites.succ(7).contains("") && bites.nul(7).contains("abc"));
    // sequence: proven nonnullable via facts -> NULL empty; SUCC is the paper's conservative empty
    assert(bites.nul(8).emptiness() == Proof.provenEmpty && bites.succ(8).emptiness() == Proof
            .provenEmpty);
    // nullable sequence: intersection of NULLs (universal ∩ universal)
    assert(bites.nul(10).contains("abc") && bites.nul(10).contains(""));
    // unknown node: SUCC bottom, NULL top; a choice with an unknown arm keeps the known arm's SUCC
    assert(bites.succ(9).emptiness() == Proof.provenEmpty && bites.nul(9).contains("anything"));
    assert(bites.succ(11).contains("abc") && bites.nul(11).contains("zzz"));
    // fail never succeeds
    assert(bites.succ(12).emptiness() == Proof.provenEmpty && bites.nul(12).emptiness() == Proof
            .provenEmpty);
}

nothrow unittest {
    // Recursion degrades soundly: A <- A 'a' / eps is cut to bottom (SUCC) and top (NULL) at the back edge.
    alias K = ExpressionKind;
    GrammarAnalysis graph;
    graph.names = ["A"];
    graph.expressions = [
        composite(K.reference, "", []), // 0 -> A
        lit("a"), // 1
        composite(K.sequence, "and", [0, 1]), // 2
        plain("eps", Nullable.yes), // 3
        composite(K.choice, "or", [2, 3]), // 4
    ];
    graph.expressions[0].reference = "A";
    graph.roots = [4];
    graph.solve();
    auto bites = BitesAnalysis(graph);
    assert(bites.succ(4).contains("zz")); // eps arm
    assert(bites.nul(4).contains("a") && bites.nul(4).contains(""));
    // Budget exceeded -> NULL becomes universal (never empty), SUCC becomes empty
    GrammarAnalysis heavy;
    heavy.names = ["R"];
    heavy.expressions = [
        lit("aaaaaaaaaaaaaaaa"), composite(K.predicate, "negLookahead", [0]),
        composite(K.predicate, "negLookahead", [0]), composite(K.sequence, "and", [1, 2])
    ];
    heavy.roots = [3];
    heavy.solve();
    Budget tiny;
    tiny.maxStates = 4;
    auto limited = BitesAnalysis(heavy, tiny);
    assert(limited.nul(3).contains("aaaa")); // universal fallback, not empty
    assert(limited.nul(3).emptiness() != Proof.provenEmpty);
}

version (unittest) {
    /// Reference PEG matcher over the expression graph (test oracle): end offset or -1.
    private ptrdiff_t matchNode(ref GrammarAnalysis graph, size_t index, string input, size_t pos) nothrow {
        auto node = graph.expressions[index];
        final switch (node.kind) {
        case ExpressionKind.unknown:
            return -1;
        case ExpressionKind.terminal:
            if (node.source == "eps")
                return pos;
            if (node.source == "eoi")
                return pos == input.length ? cast(ptrdiff_t)pos : -1;
            if (node.source == "fail")
                return -1;
            const text = BitesAnalysis.plainLiteral(node.source);
            return pos + text.length <= input.length && input[pos .. pos + text.length] == text
                ? cast(ptrdiff_t)(pos + text.length) : -1;
        case ExpressionKind.reference:
            return matchNode(graph, graph.roots[graph.referenceRule(node)], input, pos);
        case ExpressionKind.sequence:
            ptrdiff_t at = pos;
            foreach (child; node.children) {
                at = matchNode(graph, child, input, at);
                if (at < 0)
                    return -1;
            }
            return at;
        case ExpressionKind.choice:
            foreach (child; node.children) {
                const end = matchNode(graph, child, input, pos);
                if (end >= 0)
                    return end;
            }
            return -1;
        case ExpressionKind.optional:
            const end = matchNode(graph, node.children[0], input, pos);
            return end >= 0 ? end : cast(ptrdiff_t)pos;
        case ExpressionKind.repetition:
            ptrdiff_t at = pos;
            while (true) {
                const end = matchNode(graph, node.children[0], input, at);
                if (end < 0 || end == at)
                    return at;
                at = end;
            }
        case ExpressionKind.predicate:
            const hit = matchNode(graph, node.children[0], input, pos) >= 0;
            const wanted = node.combinator == "posLookahead";
            return hit == wanted ? cast(ptrdiff_t)pos : -1;
        case ExpressionKind.wrapper:
            return matchNode(graph, node.children[0], input, pos);
        }
    }

    /// Every string over {a,b,c} up to `maxLength`.
    private string[] sampleInputs(size_t maxLength) nothrow {
        string[] all = [""];
        size_t from;
        foreach (length; 0 .. maxLength) {
            const to = all.length;
            foreach (i; from .. to)
                foreach (c; "abc")
                    all ~= all[i] ~ c;
            from = to;
        }
        return all;
    }
}

nothrow unittest {
    // Sampling supplements the proofs: SUCC never contains a failing input, NULL never misses an empty success.
    alias K = ExpressionKind;
    static void check(ref GrammarAnalysis graph, size_t[] indices) nothrow {
        auto bites = BitesAnalysis(graph);
        foreach (input; sampleInputs(4)) {
            foreach (index; indices) {
                const end = matchNode(graph, index, input, 0);
                if (bites.succ(index).contains(input))
                    assert(end >= 0, "SUCC claimed success on a failing input");
                if (end == 0)
                    assert(bites.nul(index).contains(input), "NULL missed an empty success");
            }
        }
    }

    GrammarAnalysis graph;
    graph.names = ["R"];
    graph.expressions = [
        lit("ab"), // 0
        lit("a"), // 1
        lit("c"), // 2
        plain("eps", Nullable.yes), // 3
        plain("eoi", Nullable.yes), // 4
        composite(K.choice, "or", [0, 1]), // 5: 'ab' / 'a'
        composite(K.predicate, "negLookahead", [0]), // 6: !'ab'
        composite(K.predicate, "posLookahead", [1]), // 7: &'a'
        composite(K.optional, "option", [2]), // 8: 'c'?
        composite(K.repetition, "zeroOrMore", [1]), // 9: 'a'*
        composite(K.sequence, "and", [6, 1]), // 10: !'ab' 'a'
        composite(K.sequence, "and", [7, 9, 4]), // 11: &'a' 'a'* eoi
        composite(K.choice, "or", [10, 8]), // 12: (!'ab' 'a') / 'c'?
        composite(K.sequence, "and", [8, 6]), // 13: 'c'? !'ab'
        composite(K.wrapper, "discard", [13]), // 14
        composite(K.predicate, "negLookahead", [6]), // 15: !!'ab'
        composite(K.sequence, "and", [15, 5]), // 16
        composite(K.choice, "or", [3, 2]), // 17: eps / 'c'
        composite(K.sequence, "and", [9, 8, 4]), // 18
    ];
    graph.roots = [5];
    graph.solve();
    check(graph, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]);
}
