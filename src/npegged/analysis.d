/** Cold, conservative grammar graph analysis. No generated parser depends on GC. */
module npegged.analysis;
import npegged.peg : CharSetMask;

nothrow:

enum ExpressionKind {
    unknown,
    terminal,
    reference,
    sequence,
    choice,
    optional,
    repetition,
    predicate,
    wrapper
}

enum Nullable {
    unknown,
    no,
    yes
}

/// An expression graph uses indices so recursive rule references need no cyclic objects.
struct Expression {
    ExpressionKind kind;
    size_t[] children;
    string reference;
    CharSetMask first;
    Nullable nullable = Nullable.unknown;
    bool known;
    string source, combinator;
    string[] arguments;
    CharSetMask alphabet;
    bool byteTerminal;
    size_t byteWidth;
    size_t rule = size_t.max;
}

struct FirstFacts {
    CharSetMask first;
    Nullable nullable = Nullable.unknown;
    bool known;
    bool eofOnly; // Any empty success requires end of input.
}

/// An ordered escape pair followed by an ordinary byte alternative.
struct EscapeLoop {
    size_t prefix, ordinary;
    bool known;
    bool doubled;
}

/// Report-only structural knowledge and conservative possibility of actions.
struct RuleEffect {
    bool known;
    bool actionful = true;
}

@nogc nothrow unittest {
    RuleEffect unknown;
    assert(!unknown.known && unknown.actionful);
}

/// Cold diagnostics for actual emitter choices. H02 refines effect evidence separately.
struct RuleEligibility {
    string name, rootExpression;
    bool known, actionful = true;
    bool leftRecursive, memoized, scalarEligible, directRecognition, directRecords;
    string[] scalarBlockers;
    string directFallback;
    bool selectorConfigured, recordSelected, recordLeaf, recordSubtree;
    uint recordKind = uint.max;

}

@nogc nothrow unittest {
    RuleEligibility row;
    assert(row.recordKind == uint.max && !row.scalarEligible && !row.selectorConfigured);
}

/// FIRST is a conservative byte-set superset; unknown facts never enable dispatch.
/// Left edges include every call reachable before proven input consumption.
struct GrammarAnalysis {
nothrow:
    Expression[] expressions;
    private Expression[] _exprCap;
    string[] names;
    size_t[] roots;
    FirstFacts[] facts;
    private FirstFacts[] _factsCap;

    size_t appendExpression(Expression node) nothrow {
        const index = expressions.length;
        if (index >= _exprCap.length) {
            const cap = index < 32 ? 64 : index * 2;
            auto next = new Expression[cap];
            foreach (i; 0 .. index)
                next[i] = expressions[i];
            _exprCap = next;
        }
        _exprCap[index] = node;
        expressions = _exprCap[0 .. index + 1];
        return index;
    }

    void truncate(size_t count) @nogc nothrow {
        expressions = _exprCap[0 .. count];
        if (facts.length > count)
            facts = _factsCap[0 .. count];
    }

    nothrow unittest {
        GrammarAnalysis graph;
        const idx = graph.appendExpression(Expression(ExpressionKind.terminal));
        assert(idx == 0 && graph.expressions.length == 1);
        graph.truncate(0);
        assert(graph.expressions.length == 0);
    }

    size_t[][] leftEdges;
    bool[] leftRecursive;
    bool conservative;

    size_t referenceRule(ref Expression node) @nogc {
        if (node.rule == size_t.max - 1)
            return size_t.max;
        if (node.rule < names.length && names[node.rule] == node.reference)
            return node.rule;
        const r = ruleIndex(node.reference);
        node.rule = r == size_t.max ? size_t.max - 1 : r;
        return r;
    }

    @nogc nothrow unittest {
        string[1] names = ["First"];
        GrammarAnalysis graph;
        graph.names = names[];
        auto hit = Expression(ExpressionKind.reference, null, "First");
        assert(graph.referenceRule(hit) == 0 && graph.referenceRule(hit) == 0);
        auto miss = Expression(ExpressionKind.reference, null, "Missing");
        assert(graph.referenceRule(miss) == size_t.max && graph.referenceRule(miss) == size_t.max);
    }

    size_t ruleIndex(string name) @nogc {
        foreach (i, candidate; names)
            if (candidate == name)
                return i;
        return size_t.max;
    }

    @nogc nothrow unittest {
        string[2] names = ["First", "Second"];
        GrammarAnalysis graph;
        graph.names = names[];
        assert(graph.ruleIndex("First") == 0 && graph.ruleIndex("Second") == 1);
        assert(graph.ruleIndex("missing") == size_t.max);
    }

    /// Structural unknowns that force the existing grammar-wide conservative policy.
    string[] unknownEvidence() nothrow {
        string[] result;
        foreach (node; expressions)
            if (node.kind == ExpressionKind.unknown || node.kind == ExpressionKind.reference
                    && ruleIndex(node.reference) == size_t.max)
                result ~= node.source;
        return result;
    }

    nothrow unittest {
        GrammarAnalysis graph;
        graph.names = ["Known"];
        Expression known = Expression(ExpressionKind.reference, null, "Known");
        known.source = "Known";
        Expression opaque = Expression(ExpressionKind.reference, null, "External");
        opaque.source = "External";
        Expression action;
        action.source = "action!(literal!(\"a\"), effect)";
        graph.expressions = [known, opaque, action, Expression(ExpressionKind.terminal)];
        assert(graph.unknownEvidence() == ["External", action.source]);
        graph.expressions = null;
        assert(!graph.unknownEvidence().length);
    }

    /// Cold rule-local structural/effect facts. This does not modify solve() policy.
    /// Unknown calls may execute actions. Closed cycles use a monotone fixed point;
    /// structural knowledge is not a proof of termination or acyclicity.
    RuleEffect[] ruleEffects(scope const(bool)[] parameterized = null) nothrow {
        assert(names.length == roots.length);
        assert(!parameterized.length || parameterized.length == names.length);
        auto result = new RuleEffect[names.length];
        auto calls = new size_t[][names.length];
        auto seen = new size_t[expressions.length];
        size_t caller;
        void inspect(size_t index) nothrow {
            assert(index < expressions.length);
            if (seen[index] == caller + 1)
                return;
            seen[index] = caller + 1;
            auto node = expressions[index];
            if (node.kind == ExpressionKind.unknown) {
                result[caller].known = false;
                result[caller].actionful = true;
            } else if (node.kind == ExpressionKind.reference) {
                const callee = referenceRule(node);
                if (callee == size_t.max) {
                    result[caller].known = false;
                    result[caller].actionful = true;
                } else
                    calls[caller] ~= callee;
            } else {
                if (node.combinator == "action")
                    result[caller].actionful = true;
                foreach (child; node.children)
                    inspect(child);
            }
        }

        foreach (i, root; roots) {
            caller = i;
            const unknown = parameterized.length && parameterized[i];
            result[i] = RuleEffect(!unknown, unknown);
            inspect(root);
        }
        bool changed = true;
        while (changed) {
            changed = false;
            foreach (i, edges; calls)
                foreach (callee; edges) {
                    const known = result[i].known && result[callee].known;
                    const actionful = result[i].actionful || result[callee].actionful;
                    if (known != result[i].known || actionful != result[i].actionful) {
                        result[i] = RuleEffect(known, actionful);
                        changed = true;
                    }
                }
        }
        return result;
    }

    nothrow unittest {
        GrammarAnalysis graph;
        assert(!graph.ruleEffects().length);
        graph.names = [
            "Pure", "Opaque", "Caller", "Action", "ActionCaller", "CycleA", "CycleB", "PureCycle"
        ];
        auto action = Expression(ExpressionKind.wrapper, [0]);
        action.combinator = "action";
        graph.expressions = [
            Expression(ExpressionKind.terminal),
            Expression(ExpressionKind.reference, null, "external"),
            Expression(ExpressionKind.reference, null, "Opaque"), action,
            Expression(ExpressionKind.reference, null, "Action"),
            Expression(ExpressionKind.reference, null, "CycleB"),
            Expression(ExpressionKind.reference, null, "CycleA"),
            Expression(ExpressionKind.sequence, [0, 2, 5]),
            Expression(ExpressionKind.reference, null, "PureCycle"),
            Expression(ExpressionKind.sequence, [0, 0]), Expression(ExpressionKind.unknown)
        ];
        graph.roots = [9, 1, 2, 3, 4, 7, 6, 8];
        auto effects = graph.ruleEffects();
        assert(effects[0].known && !effects[0].actionful);
        foreach (i; [1, 2, 5, 6])
            assert(!effects[i].known && effects[i].actionful);
        foreach (i; [3, 4])
            assert(effects[i].known && effects[i].actionful);
        assert(effects[7].known && !effects[7].actionful);
        bool[8] parameterized;
        parameterized[0] = parameterized[3] = true;
        auto guarded = graph.ruleEffects(parameterized[]);
        assert(!guarded[0].known && guarded[0].actionful);
        assert(!guarded[4].known && guarded[4].actionful);
        graph.expressions[7].children = [0, 4, 5];
        auto actionCycle = graph.ruleEffects();
        assert(actionCycle[5].known && actionCycle[5].actionful);
        assert(actionCycle[6].known && actionCycle[6].actionful);
        graph.roots[0] = 10;
        assert(!graph.ruleEffects()[0].known && graph.ruleEffects()[0].actionful);
        // Ordinary analysis flags and arrays are not changed by diagnostic facts.
        assert(!graph.conservative && !graph.leftRecursive.length);
        GrammarAnalysis reverse;
        reverse.names = ["First", "Second", "Unknown"];
        reverse.roots = [0, 1, 2];
        reverse.expressions = [
            Expression(ExpressionKind.reference, null, "Second"),
            Expression(ExpressionKind.reference, null, "Unknown"), Expression.init
        ];
        foreach (effect; reverse.ruleEffects())
            assert(!effect.known && effect.actionful);
    }

    /// Only closed, acyclic expressions with understood effects may be shared.
    bool shareable(size_t index) {
        bool[] visiting = new bool[names.length];
        bool inspect(size_t current) {
            auto node = expressions[current];
            if (node.kind == ExpressionKind.unknown)
                return false;
            if (node.kind == ExpressionKind.reference) {
                const rule = referenceRule(node);
                if (rule == size_t.max || visiting[rule])
                    return false;
                visiting[rule] = true;
                const result = inspect(roots[rule]);
                visiting[rule] = false;
                return result;
            }
            foreach (child; node.children)
                if (!inspect(child))
                    return false;
            return true;
        }

        return inspect(index);
    }

    unittest {
        GrammarAnalysis graph;
        graph.names = ["Token", "Cycle"];
        graph.expressions = [
            Expression(ExpressionKind.terminal), Expression(ExpressionKind.reference, null,
                    "Token"),
            Expression(ExpressionKind.reference, null, "Cycle"),
            Expression(ExpressionKind.reference, null, "External"),
            Expression(ExpressionKind.unknown), Expression(ExpressionKind.sequence, [0, 1]),
            Expression(ExpressionKind.sequence, [0, 4])
        ];
        graph.roots = [0, 2];
        assert(graph.shareable(5));
        assert(!graph.shareable(2));
        assert(!graph.shareable(3));
        assert(!graph.shareable(6));
    }

    private CharSetMask continuation(size_t current) @nogc {
        auto expression = expressions[current];
        if (expression.kind == ExpressionKind.reference)
            return continuation(roots[referenceRule(expression)]);
        const escaped = escapeLoop(current);
        if (escaped.known)
            return expressions[escaped.prefix].first | expressions[escaped.ordinary].first;
        CharSetMask result;
        if (expression.kind == ExpressionKind.terminal)
            return result;
        if (expression.combinator == "zeroOrMore" || expression.combinator == "oneOrMore"
                || expression.combinator == "option")
            return facts[expression.children[0]].first | continuation(expression.children[0]);
        if (expression.kind == ExpressionKind.sequence) {
            for (size_t i = expression.children.length; i > 0; --i) {
                const child = expression.children[i - 1];
                result = result | continuation(child);
                if (i > 1) {
                    const paired = escapeLoop(expression.children[i - 2]);
                    if (paired.known && paired.doubled && expressions[child].byteWidth == 1
                            && expressions[child].first == expressions[paired.prefix].first)
                        result = result | expressions[child].first;
                }
                if (facts[child].nullable == Nullable.no)
                    break;
            }
            return result;
        }
        foreach (child; expression.children)
            result = result | continuation(child);
        return result;
    }

    @nogc nothrow unittest {
        Expression[4] nodes;
        FirstFacts[4] values;
        size_t[1] optional = [1];
        size_t[2] sequence = [0, 2];
        nodes[0].kind = nodes[1].kind = ExpressionKind.terminal;
        nodes[2].kind = ExpressionKind.optional;
        nodes[2].combinator = "option";
        nodes[2].children = optional[];
        nodes[3].kind = ExpressionKind.sequence;
        nodes[3].children = sequence[];
        values[0] = FirstFacts(CharSetMask.fromChars('a'), Nullable.no, true);
        values[1] = FirstFacts(CharSetMask.fromChars('b'), Nullable.no, true);
        values[2] = FirstFacts(values[1].first, Nullable.yes, true);
        GrammarAnalysis graph;
        graph.expressions = nodes[];
        graph.facts = values[];
        assert(graph.continuation(3) == CharSetMask.fromChars('b'));
        assert(graph.continuation(0).empty);

        Expression[10] nodes10;
        FirstFacts[10] values10;
        nodes10[0 .. 4] = nodes[];
        values10[0 .. 4] = values[];
        nodes10[4].kind = ExpressionKind.terminal;
        nodes10[4].byteTerminal = true;
        nodes10[4].byteWidth = 2;
        nodes10[4].first.addChar('"');
        nodes10[4].alphabet = nodes10[4].first;
        nodes10[5].kind = ExpressionKind.terminal;
        nodes10[5].byteTerminal = true;
        nodes10[5].byteWidth = 1;
        nodes10[5].first.addChar('x');
        size_t[2] escChoices = [4, 5];
        nodes10[6].combinator = "or";
        nodes10[6].children = escChoices[];
        size_t[1] escRepeated = [6];
        nodes10[7].combinator = "zeroOrMore";
        nodes10[7].children = escRepeated[];
        nodes10[8].kind = ExpressionKind.terminal;
        nodes10[8].byteTerminal = true;
        nodes10[8].byteWidth = 1;
        nodes10[8].first.addChar('"');
        size_t[2] escSeq = [7, 8];
        nodes10[9].kind = ExpressionKind.sequence;
        nodes10[9].children = escSeq[];
        values10[7] = FirstFacts(CharSetMask.fromChars('"', 'x'), Nullable.yes, true);
        values10[8] = FirstFacts(CharSetMask.fromChars('"'), Nullable.no, true);
        graph.expressions = nodes10[];
        graph.facts = values10[];
        assert(graph.continuation(9) == CharSetMask.fromChars('"'));

        Expression[16] nodes16;
        FirstFacts[16] values16;
        nodes16[0 .. 10] = nodes10[];
        values16[0 .. 10] = values10[];
        nodes16[10].kind = ExpressionKind.terminal;
        nodes16[10].byteTerminal = true;
        nodes16[10].byteWidth = 1;
        nodes16[10].first.addChar('\\');
        nodes16[11].kind = ExpressionKind.terminal;
        nodes16[11].source = "any";
        size_t[2] ordPair = [10, 11];
        nodes16[12].combinator = "and";
        nodes16[12].children = ordPair[];
        size_t[2] ordChoices = [12, 5];
        nodes16[13].combinator = "or";
        nodes16[13].children = ordChoices[];
        size_t[1] ordRep = [13];
        nodes16[14].combinator = "zeroOrMore";
        nodes16[14].children = ordRep[];
        size_t[2] ordSeq = [14, 8];
        nodes16[15].kind = ExpressionKind.sequence;
        nodes16[15].children = ordSeq[];
        values16[14] = FirstFacts(CharSetMask.fromChars('\\', 'x'), Nullable.yes, true);
        values16[15] = values10[8];
        graph.expressions = nodes16[];
        graph.facts = values16[];
        assert(graph.continuation(15).empty);

        nodes16[8].first = CharSetMask.fromChars('z');
        assert(graph.continuation(9).empty);
    }

    /// Conservative PEG/regular-language equivalence, beyond syntactic regularity.
    /// Nullable prefixes must not steal bytes from a following expression, and
    /// ordinary alternatives require disjoint FIRST sets with only a final nullable
    /// alternative; recognized escape loops preserve their earlier pair priority.
    bool regularLeaf(size_t index, bool anchored = false) {
        bool[] visiting = new bool[names.length];
        return regularLeaf(index, visiting, CharSetMask.init, anchored);
    }

    unittest {
        GrammarAnalysis graph;
        graph.names = ["Leaf", "Cycle"];
        graph.roots = [0, 2];
        graph.expressions = [
            Expression(ExpressionKind.terminal, null, null, CharSetMask.init, Nullable.no, true,
                    "digit", null, null, CharSetMask.init, true, 1),
            Expression(ExpressionKind.reference, null, "Leaf"),
            Expression(ExpressionKind.reference, null, "Cycle")
        ];
        assert(graph.regularLeaf(1));
        assert(!graph.regularLeaf(2));
    }

    private bool regularLeaf(size_t index, ref bool[] visiting, CharSetMask follow, bool anchored) {
        auto node = expressions[index];
        if (node.kind == ExpressionKind.reference) {
            const rule = referenceRule(node);
            if (rule == size_t.max || visiting[rule])
                return false;
            visiting[rule] = true;
            const result = regularLeaf(roots[rule], visiting, follow, anchored);
            visiting[rule] = false;
            return result;
        }
        if (node.kind == ExpressionKind.terminal)
            return node.byteTerminal || node.source == "eps";
        if (node.kind == ExpressionKind.unknown || node.kind == ExpressionKind.predicate)
            return false;
        if (escapeLoop(index).known)
            return true;
        if (node.combinator != "and" && node.combinator != "wrapAround" && node.combinator != "or"
                && node.combinator != "predictiveChoice" && node.combinator != "option"
                && node.combinator != "zeroOrMore"
                && node.combinator != "oneOrMore" && node.combinator != "fuse"
                && node.combinator != "discard"
                && node.combinator != "keep" && node.combinator != "drop"
                && node.combinator != "propagate"
                && node.combinator != "named" && node.combinator != "defined" && node.combinator != "branch")
            return false;
        CharSetMask following(size_t start) {
            CharSetMask result;
            foreach (next; node.children[start .. $]) {
                result = result | facts[next].first;
                if (facts[next].nullable == Nullable.no)
                    return result;
            }
            return result | follow;
        }

        foreach (i, child; node.children) {
            auto next = follow;
            if (node.combinator == "and" || node.combinator == "wrapAround")
                next = following(i + 1);
            else if (node.combinator == "zeroOrMore" || node.combinator == "oneOrMore")
                next = next | facts[child].first;
            if (!regularLeaf(child, visiting, next, anchored))
                return false;
        }
        if (node.combinator == "zeroOrMore" || node.combinator == "oneOrMore") {
            const child = node.children[0];
            if (continuation(child).intersects(facts[child].first)) {
                size_t current = child;
                while (true) {
                    auto expression = expressions[current];
                    if (expression.kind == ExpressionKind.reference) {
                        current = roots[referenceRule(expression)];
                        continue;
                    }
                    if (expression.children.length == 1
                            && (expression.kind == ExpressionKind.wrapper
                                || expression.combinator == "zeroOrMore"
                                || expression.combinator == "oneOrMore" || expression.combinator == "option")) {
                        current = expression.children[0];
                        continue;
                    }
                    break;
                }
                bool repeatable = expressions[current].byteTerminal && expressions[current].byteWidth == 1;
                auto body = expressions[current];
                if (!repeatable && body.kind == ExpressionKind.sequence && body.children.length >= 2) {
                    if (facts[body.children[0]].nullable == Nullable.no) {
                        bool safe = true;
                        foreach (tail; body.children[1 .. $]) {
                            if (facts[tail].first.intersects(facts[body.children[0]].first))
                                safe = false;
                        }
                        if (safe)
                            repeatable = true;
                    }
                }
                if (!repeatable && body.kind == ExpressionKind.choice) {
                    bool safe = true;
                    foreach (i, alt; body.children) {
                        if (facts[alt].nullable != Nullable.no)
                            safe = false;
                        foreach (j, other; body.children) {
                            if (i != j && continuation(alt).intersects(facts[other].first))
                                safe = false;
                        }
                    }
                    if (safe)
                        repeatable = true;
                }
                if (!repeatable)
                    return false;
            }
        }
        if (node.combinator == "or" || node.combinator == "predictiveChoice") {
            foreach (i, child; node.children) {
                if (!facts[child].known || facts[child].nullable == Nullable.unknown
                        || facts[child].nullable == Nullable.yes && i + 1 != node.children.length)
                    return false;
                foreach (other; node.children[i + 1 .. $])
                    if (facts[child].first.intersects(facts[other].first))
                        return false;
            }
        }
        if (node.combinator == "and" || node.combinator == "wrapAround") {
            bool variable(size_t current) {
                auto expression = expressions[current];
                if (expression.kind == ExpressionKind.reference)
                    return variable(roots[referenceRule(expression)]);
                if (expression.combinator == "option" || expression.combinator == "zeroOrMore"
                        || expression.combinator == "oneOrMore")
                    return true;
                foreach (child; expression.children)
                    if (variable(child))
                        return true;
                return false;
            }

            foreach (i, child; node.children) {
                if (!variable(child))
                    continue;
                const consumed = continuation(child);
                foreach (offset, next; node.children[i + 1 .. $]) {
                    auto suffix = expressions[next];
                    bool absorbedPrefix;
                    auto prefix = expressions[child];
                    if (prefix.combinator == "option" && prefix.children.length == 1
                            && expressions[prefix.children[0]].byteWidth == 1
                            && suffix.combinator == "zeroOrMore" && suffix.children.length == 1) {
                        CharSetMask bytes;
                        bool byteRun;
                        const escaped = escapeLoop(next);
                        if (escaped.known) {
                            byteRun = true;
                            foreach (word; 0 .. 4)
                                bytes.bits[word] = expressions[escaped.ordinary].first.bits[word] & ~expressions[escaped
                                    .prefix].first.bits[word];
                        } else if (expressions[suffix.children[0]].byteTerminal
                                && expressions[suffix.children[0]].byteWidth == 1) {
                            byteRun = true;
                            bytes = expressions[suffix.children[0]].first;
                        }
                        if (byteRun) {
                            absorbedPrefix = true;
                            foreach (word; 0 .. 4)
                                if (expressions[prefix.children[0]].first.bits[word] & ~bytes.bits[word])
                                    absorbedPrefix = false;
                        }
                    }
                    bool delimited;
                    const escaped = escapeLoop(child);
                    if (escaped.known && escaped.doubled && offset == 0 && anchored
                            && suffix.byteTerminal
                            && suffix.byteWidth == 1 && suffix.first == expressions[escaped.prefix]
                                .first)
                        delimited = !following(i + 2).intersects(suffix.first);
                    else if (offset == 0 && suffix.byteTerminal && suffix.byteWidth == 1
                            && !facts[child].first.intersects(suffix.first)) {
                        if ((expressions[child].combinator == "zeroOrMore"
                                || expressions[child].combinator == "oneOrMore")
                                && expressions[child].children.length == 1) {
                            const childBody = expressions[child].children[0];
                            if (facts[childBody].nullable == Nullable.no)
                                delimited = !following(i + 2).intersects(suffix.first);
                        }
                    }
                    if (!facts[next].known || (consumed.intersects(facts[next].first) && !absorbedPrefix && !delimited))
                        return false;
                    if (facts[next].nullable == Nullable.no)
                        break;
                }
            }
        }
        return true;
    }

    unittest {
        CharSetMask a, b;
        a.addChar('a');
        b.addChar('b');
        GrammarAnalysis graph;
        graph.expressions = [
            Expression(ExpressionKind.terminal, null, null, a, Nullable.no, true,
                    "charClass!(1, 0, 0, 0)", null, null, a, true, 1),
            Expression(ExpressionKind.terminal, null, null, b, Nullable.no, true,
                    "charClass!(2, 0, 0, 0)", null, null, b, true, 1),
            Expression(ExpressionKind.repetition, [0], null, CharSetMask.init, Nullable.unknown,
                    false, null, "zeroOrMore"),
            Expression(ExpressionKind.sequence, [2, 1], null, CharSetMask.init, Nullable.unknown,
                    false, null, "and"),
            Expression(ExpressionKind.sequence, [2, 0], null, CharSetMask.init, Nullable.unknown,
                    false, null, "and"),
            Expression(ExpressionKind.choice, [0, 1], null, CharSetMask.init, Nullable.unknown,
                    false, null, "or"),
            Expression(ExpressionKind.choice, [0, 0], null, CharSetMask.init, Nullable.unknown,
                    false, null, "or"), Expression(ExpressionKind.reference)
        ];
        graph.solve();
        assert(graph.regularLeaf(3));
        assert(!graph.regularLeaf(4));
        assert(graph.regularLeaf(5));
        assert(!graph.regularLeaf(6));
        assert(!graph.regularLeaf(7));

        Expression[5] absorbedNodes;
        absorbedNodes[0] = Expression(ExpressionKind.terminal, null, null, a, Nullable.no, true, "literal!\"a\"");
        absorbedNodes[0].byteTerminal = true;
        absorbedNodes[0].byteWidth = 1;
        absorbedNodes[1] = Expression(ExpressionKind.optional, [0], null, CharSetMask.init,
                Nullable.yes, true, null, "option");
        absorbedNodes[2] = Expression(ExpressionKind.repetition, [0], null, CharSetMask.init,
                Nullable.yes, true, null, "zeroOrMore");
        absorbedNodes[3] = Expression(ExpressionKind.sequence, [1, 2], null, CharSetMask.init,
                Nullable.unknown, false, null, "and");
        GrammarAnalysis agraph;
        agraph.expressions = absorbedNodes[];
        agraph.solve();
        assert(agraph.regularLeaf(3));

        absorbedNodes[4] = Expression(ExpressionKind.terminal, null, null, a | b, Nullable.no, true, "charClass");
        absorbedNodes[4].byteTerminal = true;
        absorbedNodes[4].byteWidth = 1;
        absorbedNodes[1].children = [4];
        agraph.solve();
        assert(!agraph.regularLeaf(3));

        Expression[6] escNodes;
        escNodes[0] = Expression(ExpressionKind.terminal, null, null, a, Nullable.no, true, "literal!\"a\"");
        escNodes[0].byteTerminal = true;
        escNodes[0].byteWidth = 2;
        escNodes[0].alphabet = a;
        escNodes[1] = Expression(ExpressionKind.terminal, null, null, b, Nullable.no, true, "literal!\"b\"");
        escNodes[1].byteTerminal = true;
        escNodes[1].byteWidth = 1;
        escNodes[2] = Expression(ExpressionKind.choice, [0, 1], null, CharSetMask.init,
                Nullable.unknown, false, null, "or");
        escNodes[3] = Expression(ExpressionKind.repetition, [2], null, CharSetMask.init,
                Nullable.yes, true, null, "zeroOrMore");
        escNodes[4] = Expression(ExpressionKind.terminal, null, null, a, Nullable.no, true, "literal!\"a\"");
        escNodes[4].byteTerminal = true;
        escNodes[4].byteWidth = 1;
        escNodes[5] = Expression(ExpressionKind.sequence, [3, 4], null, CharSetMask.init,
                Nullable.unknown, false, null, "and");
        GrammarAnalysis egraph;
        egraph.expressions = escNodes[];
        egraph.solve();
        assert(egraph.regularLeaf(5, true));
        assert(!egraph.regularLeaf(5, false));

        Expression[4] delNodes;
        delNodes[0] = Expression(ExpressionKind.terminal, null, null, a, Nullable.no, true, "literal!\"a\"");
        delNodes[0].byteTerminal = true;
        delNodes[0].byteWidth = 1;
        delNodes[1] = Expression(ExpressionKind.repetition, [0], null, CharSetMask.init,
                Nullable.no, true, null, "oneOrMore");
        delNodes[2] = Expression(ExpressionKind.terminal, null, null, b, Nullable.no, true, "literal!\"b\"");
        delNodes[2].byteTerminal = true;
        delNodes[2].byteWidth = 1;
        delNodes[3] = Expression(ExpressionKind.sequence, [1, 2], null, CharSetMask.init,
                Nullable.unknown, false, null, "and");
        GrammarAnalysis dgraph2;
        dgraph2.expressions = delNodes[];
        dgraph2.solve();
        assert(dgraph2.regularLeaf(3));
        delNodes[1].combinator = "zeroOrMore";
        dgraph2.solve();
        assert(dgraph2.regularLeaf(3));

        CharSetMask c;
        c.addChar('c');
        Expression[15] repNodes;
        repNodes[0] = Expression(ExpressionKind.terminal, null, null, a, Nullable.no, true, "literal!\"a\"");
        repNodes[0].byteTerminal = true;
        repNodes[0].byteWidth = 1;
        repNodes[1] = Expression(ExpressionKind.terminal, null, null, b, Nullable.no, true, "literal!\"b\"");
        repNodes[1].byteTerminal = true;
        repNodes[1].byteWidth = 1;
        repNodes[2] = Expression(ExpressionKind.optional, [1], null, CharSetMask.init,
                Nullable.yes, true, null, "option");
        repNodes[3] = Expression(ExpressionKind.sequence, [0, 2], null, CharSetMask.init,
                Nullable.no, true, null, "and");
        repNodes[4] = Expression(ExpressionKind.terminal, null, null, c, Nullable.no, true, "literal!\"c\"");
        repNodes[4].byteTerminal = true;
        repNodes[4].byteWidth = 1;
        repNodes[5] = Expression(ExpressionKind.sequence, [1, 4], null, CharSetMask.init,
                Nullable.no, true, null, "and");
        repNodes[6] = Expression(ExpressionKind.choice, [3, 5], null, CharSetMask.init, Nullable.no, true,
                null, "or");
        repNodes[7] = Expression(ExpressionKind.repetition, [6], null, CharSetMask.init,
                Nullable.yes, true, null, "zeroOrMore");
        GrammarAnalysis rgraph;
        rgraph.expressions = repNodes[];
        rgraph.solve();
        assert(!rgraph.regularLeaf(7));

        repNodes[8] = Expression(ExpressionKind.wrapper, [0], null, CharSetMask.init,
                Nullable.no, true, null, "named");
        repNodes[9] = Expression(ExpressionKind.reference, null, "A");
        repNodes[10] = Expression(ExpressionKind.repetition, [9], null, CharSetMask.init,
                Nullable.no, true, null, "oneOrMore");
        repNodes[11] = Expression(ExpressionKind.repetition, [10], null, CharSetMask.init,
                Nullable.yes, true, null, "zeroOrMore");
        rgraph.names = ["A", "Root"];
        rgraph.roots = [8, 11];
        rgraph.solve();
        assert(rgraph.regularLeaf(11));

        repNodes[12] = Expression(ExpressionKind.repetition, [0], null, CharSetMask.init,
                Nullable.yes, true, null, "zeroOrMore");
        repNodes[13] = Expression(ExpressionKind.repetition, [1], null, CharSetMask.init,
                Nullable.yes, true, null, "zeroOrMore");
        size_t[2] tailSeq = [1, 12];
        repNodes[14] = Expression(ExpressionKind.sequence, tailSeq[], null, CharSetMask.init,
                Nullable.no, true, null, "and");
        Expression[16] repNodes16;
        repNodes16[0 .. 15] = repNodes[];
        repNodes16[15] = Expression(ExpressionKind.repetition, [14], null, CharSetMask.init,
                Nullable.yes, true, null, "zeroOrMore");
        rgraph.expressions = repNodes16[];
        rgraph.roots = [8, 15];
        rgraph.solve();
        assert(rgraph.regularLeaf(15));

        size_t[2] nullablePrefix = [2, 12];
        repNodes16[14] = Expression(ExpressionKind.sequence, nullablePrefix[], null,
                CharSetMask.init, Nullable.yes, true, null, "and");
        rgraph.solve();
        assert(!rgraph.regularLeaf(15));

        size_t[2] overlapTail = [0, 12];
        repNodes16[14] = Expression(ExpressionKind.sequence, overlapTail[], null, CharSetMask.init,
                Nullable.no, true, null, "and");
        rgraph.solve();
        assert(!rgraph.regularLeaf(15));

        size_t[2] safeChoice = [0, 1];
        repNodes16[14] = Expression(ExpressionKind.choice, safeChoice[], null, CharSetMask.init,
                Nullable.no, true, null, "or");
        rgraph.solve();
        assert(rgraph.regularLeaf(15));

        size_t[2] nullChoice = [2, 1];
        repNodes16[14] = Expression(ExpressionKind.choice, nullChoice[], null, CharSetMask.init,
                Nullable.yes, true, null, "or");
        rgraph.solve();
        assert(!rgraph.regularLeaf(15));

        Expression[5] choiceNodes;
        choiceNodes[0] = Expression(ExpressionKind.terminal, null, null, a, Nullable.no, true, "literal!\"a\"");
        choiceNodes[0].byteTerminal = true;
        choiceNodes[0].byteWidth = 1;
        choiceNodes[1] = Expression(ExpressionKind.optional, [0], null, CharSetMask.init,
                Nullable.yes, true, null, "option");
        choiceNodes[2] = Expression(ExpressionKind.terminal, null, null, b, Nullable.no, true, "literal!\"b\"");
        choiceNodes[2].byteTerminal = true;
        choiceNodes[2].byteWidth = 1;
        choiceNodes[3] = Expression(ExpressionKind.choice, [1, 2], null, CharSetMask.init,
                Nullable.unknown, false, null, "or");
        choiceNodes[4] = Expression(ExpressionKind.choice, [2, 1], null, CharSetMask.init,
                Nullable.unknown, false, null, "or");
        GrammarAnalysis cgraph;
        cgraph.expressions = choiceNodes[];
        cgraph.solve();
        assert(!cgraph.regularLeaf(3));
        assert(cgraph.regularLeaf(4));

        Expression[3] wrapNodes;
        wrapNodes[0] = Expression(ExpressionKind.terminal, null, null, a, Nullable.no, true, "literal!\"a\"");
        wrapNodes[0].byteTerminal = true;
        wrapNodes[0].byteWidth = 1;
        wrapNodes[1] = Expression(ExpressionKind.terminal, null, null, b, Nullable.no, true, "literal!\"b\"");
        wrapNodes[1].byteTerminal = true;
        wrapNodes[1].byteWidth = 1;
        wrapNodes[2] = Expression(ExpressionKind.sequence, [0, 1], null, CharSetMask.init,
                Nullable.unknown, false, null, "wrapAround");
        GrammarAnalysis wgraph;
        wgraph.expressions = wrapNodes[];
        wgraph.solve();
        assert(wgraph.regularLeaf(2));
    }

    /// Pair priority can be encoded by removing escape prefixes from the ordinary
    /// class and retaining its single-byte fallback only at end of input.
    EscapeLoop escapeLoop(size_t index) @nogc {
        auto repeated = expressions[index];
        if ((repeated.combinator != "zeroOrMore" && repeated.combinator != "oneOrMore") || repeated
                .children.length != 1)
            return EscapeLoop.init;
        auto choice = expressions[repeated.children[0]];
        if ((choice.combinator != "or" && choice.combinator != "predictiveChoice") || choice.children
                .length != 2)
            return EscapeLoop.init;
        size_t pairIndex = choice.children[0], ordinaryIndex = choice.children[1];
        while (expressions[pairIndex].combinator == "branch" && expressions[pairIndex].children
                .length == 1)
            pairIndex = expressions[pairIndex].children[0];
        while (expressions[ordinaryIndex].combinator == "branch" && expressions[ordinaryIndex]
                .children.length == 1)
            ordinaryIndex = expressions[ordinaryIndex].children[0];
        auto pair = expressions[pairIndex];
        size_t prefixIndex;
        bool doubled;
        if (pair.kind == ExpressionKind.terminal && pair.byteTerminal && pair.byteWidth == 2
                && pair.first == pair.alphabet) {
            prefixIndex = pairIndex;
            doubled = true;
        } else if (pair.combinator == "and" && pair.children.length == 2) {
            prefixIndex = pair.children[0];
            auto tail = expressions[pair.children[1]];
            if (tail.kind != ExpressionKind.terminal)
                return EscapeLoop.init;
            if (tail.source != "any") {
                if (!tail.byteTerminal || tail.byteWidth != 1 || tail.first != expressions[prefixIndex]
                        .first)
                    return EscapeLoop.init;
                doubled = true;
            }
            if (expressions[prefixIndex].kind != ExpressionKind.terminal
                    || !expressions[prefixIndex].byteTerminal || expressions[prefixIndex].byteWidth != 1)
                return EscapeLoop.init;
        } else
            return EscapeLoop.init;
        auto prefix = expressions[prefixIndex];
        if (doubled) {
            bool found;
            foreach (word; prefix.first.bits)
                if (word) {
                    if (found || (word & (word - 1)))
                        return EscapeLoop.init;
                    found = true;
                }
            if (!found)
                return EscapeLoop.init;
        }
        bool grouped;
        if (expressions[ordinaryIndex].combinator == "oneOrMore" && expressions[ordinaryIndex]
                .children.length == 1) {
            grouped = true;
            ordinaryIndex = expressions[ordinaryIndex].children[0];
        }
        auto ordinary = expressions[ordinaryIndex];
        if (ordinary.kind != ExpressionKind.terminal || !ordinary.byteTerminal
                || ordinary.byteWidth != 1 || (grouped || doubled) && ordinary.first.intersects(prefix
                    .first))
            return EscapeLoop.init;
        return EscapeLoop(prefixIndex, ordinaryIndex, true, doubled);
    }

    @nogc nothrow unittest {
        Expression[7] nodes;
        size_t[2] pair = [0, 1], choices = [2, 3];
        size_t[1] repeated = [4], grouped = [3];
        nodes[0].byteTerminal = nodes[3].byteTerminal = true;
        nodes[0].kind = nodes[1].kind = nodes[3].kind = ExpressionKind.terminal;
        nodes[0].byteWidth = nodes[3].byteWidth = 1;
        nodes[0].first.addChar('\\');
        nodes[1].source = "any";
        nodes[2].combinator = "and";
        nodes[2].children = pair[];
        nodes[3].first = CharSetMask.fromChars('x', '\\');
        nodes[4].combinator = "or";
        nodes[4].children = choices[];
        nodes[5].combinator = "zeroOrMore";
        nodes[5].children = repeated[];
        nodes[6].combinator = "oneOrMore";
        nodes[6].children = grouped[];
        GrammarAnalysis graph;
        graph.expressions = nodes[];
        assert(graph.escapeLoop(5) == EscapeLoop(0, 3, true));
        nodes[1].source = "external";
        assert(!graph.escapeLoop(5).known);
        nodes[1].source = "any";
        choices[1] = 6;
        assert(!graph.escapeLoop(5).known);
        nodes[3].first = CharSetMask.fromChars('x');
        assert(graph.escapeLoop(5).known);
        nodes[5].combinator = "oneOrMore";
        assert(graph.escapeLoop(5).known);
        nodes[4].combinator = "predictiveChoice";
        assert(graph.escapeLoop(5).known);
        nodes[4].combinator = "or";
        nodes[5].combinator = "option";
        assert(!graph.escapeLoop(5).known);

        Expression[16] dnodes;
        dnodes[0].kind = ExpressionKind.terminal;
        dnodes[0].byteTerminal = true;
        dnodes[0].byteWidth = 2;
        dnodes[0].first.addChar('"');
        dnodes[0].alphabet = dnodes[0].first;
        dnodes[1].kind = ExpressionKind.terminal;
        dnodes[1].byteTerminal = true;
        dnodes[1].byteWidth = 1;
        dnodes[1].first.addChar('x');
        size_t[2] dchoices = [0, 1];
        dnodes[2].combinator = "predictiveChoice";
        dnodes[2].children = dchoices[];
        size_t[1] drepeated = [2];
        dnodes[3].combinator = "zeroOrMore";
        dnodes[3].children = drepeated[];
        GrammarAnalysis dgraph;
        dgraph.expressions = dnodes[];
        assert(dgraph.escapeLoop(3) == EscapeLoop(0, 1, true, true));

        dnodes[4].kind = ExpressionKind.terminal;
        dnodes[4].byteTerminal = true;
        dnodes[4].byteWidth = 1;
        dnodes[4].first.addChar('"');
        size_t[2] dand = [4, 4];
        dnodes[5].combinator = "and";
        dnodes[5].children = dand[];
        dchoices[0] = 5;
        assert(dgraph.escapeLoop(3) == EscapeLoop(4, 1, true, true));

        size_t[1] bpair = [5], bord = [1];
        dnodes[6].combinator = "branch";
        dnodes[6].children = bpair[];
        dnodes[7].combinator = "branch";
        dnodes[7].children = bord[];
        dchoices[0] = 6;
        dchoices[1] = 7;
        assert(dgraph.escapeLoop(3) == EscapeLoop(4, 1, true, true));

        size_t[2] diffAnd = [4, 1];
        dnodes[8].combinator = "and";
        dnodes[8].children = diffAnd[];
        dchoices[0] = 8;
        dchoices[1] = 1;
        assert(!dgraph.escapeLoop(3).known);

        size_t[2] nonTermAnd = [4, 2];
        dnodes[9].combinator = "and";
        dnodes[9].children = nonTermAnd[];
        dchoices[0] = 9;
        assert(!dgraph.escapeLoop(3).known);

        dchoices[0] = 1;
        assert(!dgraph.escapeLoop(3).known);

        dnodes[10].kind = ExpressionKind.terminal;
        dnodes[10].byteTerminal = true;
        dnodes[10].byteWidth = 2;
        dnodes[10].first.addChar('"');
        dnodes[10].first.addChar('\'');
        dnodes[10].alphabet = dnodes[10].first;
        dchoices[0] = 10;
        assert(!dgraph.escapeLoop(3).known);

        dnodes[11].kind = ExpressionKind.terminal;
        dnodes[11].byteTerminal = true;
        dnodes[11].byteWidth = 2;
        dchoices[0] = 11;
        assert(!dgraph.escapeLoop(3).known);

        size_t[2] wideAnd = [0, 4];
        dnodes[12].combinator = "and";
        dnodes[12].children = wideAnd[];
        dchoices[0] = 12;
        assert(!dgraph.escapeLoop(3).known);

        dchoices[0] = 5;
        dchoices[1] = 4;
        assert(!dgraph.escapeLoop(3).known);

        dnodes[13].kind = ExpressionKind.wrapper;
        dchoices[1] = 13;
        assert(!dgraph.escapeLoop(3).known);
    }

    private FirstFacts evaluate(size_t index) {
        return evaluateNode(expressions[index]);
    }

    private FirstFacts evaluateNode(ref Expression expression) {
        FirstFacts result;
        final switch (expression.kind) {
        case ExpressionKind.unknown:
            return result;
        case ExpressionKind.terminal:
            return FirstFacts(expression.first, expression.nullable,
                    expression.known, expression.source == "eoi" || expression.source == "endOfInput");
        case ExpressionKind.reference:
            auto rule = referenceRule(expression);
            return rule == size_t.max ? result : facts[roots[rule]];
        case ExpressionKind.sequence:
            result.known = true;
            result.nullable = Nullable.yes;
            bool prefix = true;
            foreach (child; expression.children) {
                const cNull = facts[child].nullable;
                const cKnown = facts[child].known;
                result.eofOnly = result.eofOnly || facts[child].eofOnly;
                if (prefix) {
                    result.first.bits[0] |= facts[child].first.bits[0];
                    result.first.bits[1] |= facts[child].first.bits[1];
                    result.first.bits[2] |= facts[child].first.bits[2];
                    result.first.bits[3] |= facts[child].first.bits[3];
                    result.known = result.known && cKnown && cNull != Nullable.unknown;
                    prefix = cNull != Nullable.no;
                }
                if (cNull == Nullable.no)
                    result.nullable = Nullable.no;
                else if (cNull == Nullable.unknown && result.nullable != Nullable.no)
                    result.nullable = Nullable.unknown;
            }
            result.eofOnly = result.eofOnly && result.nullable == Nullable.yes;
            return result;
        case ExpressionKind.choice:
            result.known = true;
            result.nullable = Nullable.no;
            bool onlyEnd = true;
            foreach (child; expression.children) {
                const cNull = facts[child].nullable;
                result.first.bits[0] |= facts[child].first.bits[0];
                result.first.bits[1] |= facts[child].first.bits[1];
                result.first.bits[2] |= facts[child].first.bits[2];
                result.first.bits[3] |= facts[child].first.bits[3];
                result.known = result.known && facts[child].known;
                if (cNull != Nullable.no && !facts[child].eofOnly)
                    onlyEnd = false;
                if (cNull == Nullable.yes)
                    result.nullable = Nullable.yes;
                else if (cNull == Nullable.unknown && result.nullable != Nullable.yes)
                    result.nullable = Nullable.unknown;
            }
            result.eofOnly = onlyEnd && result.nullable == Nullable.yes;
            return result;
        case ExpressionKind.optional:
        case ExpressionKind.repetition:
            result = facts[expression.children[0]];
            result.nullable = Nullable.yes;
            result.eofOnly = false;
            return result;
        case ExpressionKind.predicate:
            result.nullable = Nullable.yes;
            // Unknown children can contain actions; skipping them changes effects.
            result.known = facts[expression.children[0]].known;
            return result;
        case ExpressionKind.wrapper:
            return facts[expression.children[0]];
        }
    }

    /// Query-only expressions are appended bottom-up after the rule fixed point.
    FirstFacts appendFacts(size_t root) {
        const start = facts.length;
        const needed = expressions.length;
        if (needed > _factsCap.length) {
            const cap = needed < 32 ? 64 : needed * 2;
            auto next = new FirstFacts[cap];
            foreach (i; 0 .. start)
                next[i] = facts[i];
            _factsCap = next;
        }
        facts = _factsCap[0 .. needed];
        foreach (i; start .. needed)
            facts[i] = evaluate(i);
        return facts[root];
    }

    private void leading(size_t index, ref size_t[] edges) {
        auto expression = expressions[index];
        if (expression.kind == ExpressionKind.reference) {
            auto rule = referenceRule(expression);
            if (rule != size_t.max) {
                foreach (existing; edges)
                    if (existing == rule)
                        return;
                edges ~= rule;
            }
            return;
        }
        foreach (child; expression.children) {
            leading(child, edges);
            if (expression.kind == ExpressionKind.sequence && facts[child].nullable == Nullable.no)
                break;
        }
    }

    private bool selectedBelow(size_t index, const(uint)[] kinds, ref bool[] visiting) {
        auto expression = expressions[index];
        if (expression.kind == ExpressionKind.unknown)
            return true;
        if (expression.kind == ExpressionKind.predicate)
            return false;
        if (expression.kind == ExpressionKind.reference) {
            auto rule = referenceRule(expression);
            if (rule == size_t.max || kinds[rule] != uint.max)
                return true;
            if (visiting[rule])
                return false;
            visiting[rule] = true;
            auto selected = selectedBelow(roots[rule], kinds, visiting);
            visiting[rule] = false;
            return selected;
        }
        foreach (child; expression.children)
            if (selectedBelow(child, kinds, visiting))
                return true;
        return false;
    }

    /// Selected leaves can be emitted after success, avoiding speculative allocation.
    bool[] selectedLeaves(const(uint)[] kinds) {
        assert(kinds.length == names.length);
        auto result = new bool[names.length];
        foreach (i, kind; kinds) {
            if (kind == uint.max)
                continue;
            auto visiting = new bool[names.length];
            visiting[i] = true;
            result[i] = !selectedBelow(roots[i], kinds, visiting);
        }
        return result;
    }

    /// Returns true for rules that either have a kind tag or contain descendants with kinds.
    bool[] selectedSubtrees(const(uint)[] kinds) {
        assert(kinds.length == names.length);
        auto result = new bool[names.length];
        foreach (i, kind; kinds) {
            if (kind != uint.max)
                result[i] = true;
            else {
                auto visiting = new bool[names.length];
                visiting[i] = true;
                result[i] = selectedBelow(roots[i], kinds, visiting);
            }
        }
        return result;
    }

    // Tarjan SCC: ordinary recursion after a consumed terminal creates no left edge.
    private void visit(size_t rule, ref ptrdiff_t next, ref ptrdiff_t[] indices, ref ptrdiff_t[] low,
            ref bool[] active, ref size_t[] stack) {
        indices[rule] = low[rule] = next++;
        stack ~= rule;
        active[rule] = true;
        foreach (edge; leftEdges[rule]) {
            if (indices[edge] < 0) {
                visit(edge, next, indices, low, active, stack);
                if (low[edge] < low[rule])
                    low[rule] = low[edge];
            } else if (active[edge] && indices[edge] < low[rule])
                low[rule] = indices[edge];
        }
        if (low[rule] != indices[rule])
            return;
        size_t start = stack.length;
        do {
            --start;
            active[stack[start]] = false;
        }
        while (stack[start] != rule);
        bool cyclic = stack.length - start > 1;
        foreach (edge; leftEdges[rule])
            cyclic = cyclic || edge == rule;
        foreach (member; stack[start .. $])
            leftRecursive[member] = cyclic;
        stack.length = start;
    }

    void solve() {
        assert(names.length == roots.length);
        if (_exprCap.length < expressions.length)
            _exprCap = expressions;
        if (_factsCap.length < _exprCap.length)
            _factsCap = new FirstFacts[_exprCap.length];
        facts = _factsCap[0 .. expressions.length];
        conservative = false;
        foreach (i; 0 .. expressions.length) {
            if (expressions[i].kind == ExpressionKind.unknown)
                conservative = true;
            else if (expressions[i].kind == ExpressionKind.reference) {
                if (referenceRule(expressions[i]) == size_t.max)
                    conservative = true;
            }
        }
        auto dynamic = new bool[expressions.length];
        foreach (i; 0 .. expressions.length) {
            facts[i] = evaluate(i);
            if (expressions[i].kind == ExpressionKind.reference)
                dynamic[i] = true;
            else {
                foreach (child; expressions[i].children)
                    if (dynamic[child]) {
                        dynamic[i] = true;
                        break;
                    }
            }
        }
        size_t[] dynIndices;
        foreach (i, d; dynamic)
            if (d)
                dynIndices ~= i;
        auto changedAt = new uint[expressions.length];
        changedAt[] = 1;
        uint iter = 1;
        bool changed = true;
        while (changed) {
            changed = false;
            ++iter;
            foreach (i; dynIndices) {
                bool inputChanged;
                if (expressions[i].kind == ExpressionKind.reference) {
                    const rule = referenceRule(expressions[i]);
                    inputChanged = rule != size_t.max && changedAt[roots[rule]] >= iter - 1;
                } else {
                    foreach (child; expressions[i].children)
                        if (changedAt[child] >= iter - 1) {
                            inputChanged = true;
                            break;
                        }
                }
                if (!inputChanged)
                    continue;
                auto value = evaluate(i);
                if (value != facts[i]) {
                    facts[i] = value;
                    changedAt[i] = iter;
                    changed = true;
                }
            }
        }
        leftEdges = new size_t[][roots.length];
        foreach (i, root; roots)
            leading(root, leftEdges[i]);
        leftRecursive = new bool[roots.length];
        auto indices = new ptrdiff_t[roots.length];
        indices[] = -1;
        auto low = new ptrdiff_t[roots.length];
        auto active = new bool[roots.length];
        size_t[] stack;
        ptrdiff_t next;
        foreach (i; 0 .. roots.length)
            if (indices[i] < 0)
                visit(i, next, indices, low, active, stack);
    }
}

unittest {
    alias K = ExpressionKind;
    alias N = Nullable;
    CharSetMask a, b;
    a.addChar('a');
    b.addChar('b');
    GrammarAnalysis graph;
    graph.names = ["A", "B", "C", "D"];
    graph.expressions = [
        Expression(K.reference, null, "B"), // 0
        Expression(K.reference, null, "A"), // 1
        Expression(K.terminal, null, null, a, N.no, true), // 2
        Expression(K.terminal, null, null, b,
                N.no, true), // 3
        Expression(K.choice, [1, 2]), // 4: B <- A / 'a'
        Expression(K.sequence, [2, 0]), // 5: C <- 'a' B (ordinary recursion excluded)
        Expression(K.optional, [2]), // 6
        Expression(K.sequence, [6, 1]), // 7: D <- 'a'? A
        Expression(K.unknown), // 8
        Expression(K.repetition, [3]), // 9
        Expression(K.predicate, [0]), // 10
        Expression(K.wrapper, [9]), // 11
        Expression(K.sequence, [8, 3]), // 12 unknown prefix, proven nonnullable suffix
        Expression(K.reference, null, "external"), // 13
        Expression(K.sequence, [6, 3]), // 14 nullable prefix union
        Expression(K.sequence), // 15 empty sequence
        Expression(K.choice), // 16 empty choice
        Expression(K.choice, [8, 15]), // 17 nullable wins over unknown
        Expression(K.sequence, [8]), // 18 unknown nullability
    ];
    graph.roots = [0, 4, 5, 7];
    graph.solve();
    assert(graph.conservative);
    assert(graph.leftRecursive == [true, true, false, false]);
    assert(graph.leftEdges[3] == [0]);
    assert(graph.facts[14].known && graph.facts[14].nullable == N.no);
    assert(graph.facts[14].first.contains('a') && graph.facts[14].first.contains('b'));
    assert(!graph.facts[12].known && graph.facts[12].nullable == N.no);
    assert(graph.facts[11].nullable == N.yes);
    assert(graph.facts[10].nullable == N.yes && graph.facts[10].first.empty);
    assert(graph.facts[17].nullable == N.yes && !graph.facts[17].known);
    assert(graph.facts[18].nullable == N.unknown);
    assert(graph.ruleIndex("missing") == size_t.max);
    // Direct and predicate-hidden cycles; an edge to a completed SCC is harmless.
    graph.expressions ~= Expression(K.sequence, [10, 0]); // 19
    graph.roots = [19, 4, 5, 7];
    graph.solve();
    assert(graph.leftRecursive[0] && graph.leftRecursive[1]);
    graph.expressions ~= Expression(K.wrapper, [14]);
    assert(graph.appendFacts(graph.expressions.length - 1).first.contains('b'));
    GrammarAnalysis empty;
    empty.solve();
    assert(!empty.conservative && empty.leftRecursive.length == 0);
}

unittest {
    alias K = ExpressionKind;
    GrammarAnalysis graph;
    graph.names = ["Root", "Leaf", "Predicate", "Cycle"];
    graph.expressions = [
        Expression(K.reference, null, "Leaf"), Expression(K.terminal), Expression(K.predicate,
                [0]), Expression(K.sequence, [2, 1]), Expression(K.reference, null, "Cycle"),
        Expression(K.choice, [4, 1]), Expression(K.reference, null, "outside"), Expression(K.unknown)
    ];
    graph.roots = [0, 1, 3, 5];
    assert(graph.selectedLeaves([0U, 1U, 2U, uint.max]) == [false, true, true, false]);
    assert(graph.selectedSubtrees([0U, 1U, 2U, uint.max]) == [true, true, true, false]);
    assert(graph.selectedSubtrees([uint.max, 1U, uint.max, uint.max]) == [true, true, false, false]);
    assert(graph.selectedSubtrees([uint.max, uint.max, uint.max, uint.max]) == [
        false, false, false, false
    ]);
    graph.roots[0] = 4;
    assert(graph.selectedLeaves([0U, uint.max, uint.max, uint.max])[0]);
    assert(graph.selectedSubtrees([0U, uint.max, uint.max, uint.max])[0]);
    graph.roots[0] = 6;
    assert(!graph.selectedLeaves([0U, uint.max, uint.max, uint.max])[0]);
    assert(graph.selectedSubtrees([0U, uint.max, uint.max, uint.max])[0]);
    graph.roots[0] = 7;
    assert(!graph.selectedLeaves([0U, uint.max, uint.max, uint.max])[0]);
    assert(graph.selectedSubtrees([0U, uint.max, uint.max, uint.max])[0]);
}
