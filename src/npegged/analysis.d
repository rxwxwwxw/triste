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
}

struct FirstFacts {
    CharSetMask first;
    Nullable nullable = Nullable.unknown;
    bool known;
}

/// FIRST is a conservative byte-set superset; unknown facts never enable dispatch.
/// Left edges include every call reachable before proven input consumption.
struct GrammarAnalysis {
nothrow:
    Expression[] expressions;
    string[] names;
    size_t[] roots;
    FirstFacts[] facts;
    size_t[][] leftEdges;
    bool[] leftRecursive;
    bool conservative;

    size_t ruleIndex(string name) const {
        foreach (i, candidate; names)
            if (candidate == name)
                return i;
        return size_t.max;
    }

    private FirstFacts evaluate(size_t index) const {
        const ref expression = expressions[index];
        FirstFacts result;
        final switch (expression.kind) {
        case ExpressionKind.unknown:
            return result;
        case ExpressionKind.terminal:
            return FirstFacts(expression.first, expression.nullable, expression.known);
        case ExpressionKind.reference:
            auto rule = ruleIndex(expression.reference);
            return rule == size_t.max ? result : facts[roots[rule]];
        case ExpressionKind.sequence:
            result.known = true;
            result.nullable = Nullable.yes;
            bool prefix = true;
            foreach (child; expression.children) {
                const value = facts[child];
                if (prefix) {
                    result.first = result.first | value.first;
                    result.known = result.known && value.known && value.nullable != Nullable.unknown;
                    prefix = value.nullable != Nullable.no;
                }
                if (value.nullable == Nullable.no)
                    result.nullable = Nullable.no;
                else if (value.nullable == Nullable.unknown && result.nullable != Nullable.no)
                    result.nullable = Nullable.unknown;
            }
            return result;
        case ExpressionKind.choice:
            result.known = true;
            result.nullable = Nullable.no;
            foreach (child; expression.children) {
                const value = facts[child];
                result.first = result.first | value.first;
                result.known = result.known && value.known;
                if (value.nullable == Nullable.yes)
                    result.nullable = Nullable.yes;
                else if (value.nullable == Nullable.unknown && result.nullable != Nullable.yes)
                    result.nullable = Nullable.unknown;
            }
            return result;
        case ExpressionKind.optional:
        case ExpressionKind.repetition:
            result = facts[expression.children[0]];
            result.nullable = Nullable.yes;
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
        auto start = facts.length;
        facts.length = expressions.length;
        foreach (i; start .. expressions.length)
            facts[i] = evaluate(i);
        return facts[root];
    }

    private void leading(size_t index, ref size_t[] edges) const {
        const ref expression = expressions[index];
        if (expression.kind == ExpressionKind.reference) {
            auto rule = ruleIndex(expression.reference);
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

    private bool selectedBelow(size_t index, const(uint)[] kinds, ref bool[] visiting) const {
        const ref expression = expressions[index];
        if (expression.kind == ExpressionKind.unknown)
            return true;
        if (expression.kind == ExpressionKind.predicate)
            return false;
        if (expression.kind == ExpressionKind.reference) {
            auto rule = ruleIndex(expression.reference);
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
    bool[] selectedLeaves(const(uint)[] kinds) const {
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
        facts = new FirstFacts[expressions.length];
        conservative = false;
        foreach (expression; expressions)
            if (expression.kind == ExpressionKind.unknown
                    || (expression.kind == ExpressionKind.reference
                        && ruleIndex(expression.reference) == size_t.max))
                conservative = true;
        bool changed;
        do {
            changed = false;
            foreach (i; 0 .. expressions.length) {
                auto value = evaluate(i);
                if (value != facts[i]) {
                    facts[i] = value;
                    changed = true;
                }
            }
        }
        while (changed);
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
    graph.roots[0] = 4;
    assert(graph.selectedLeaves([0U, uint.max, uint.max, uint.max])[0]);
    graph.roots[0] = 6;
    assert(!graph.selectedLeaves([0U, uint.max, uint.max, uint.max])[0]);
    graph.roots[0] = 7;
    assert(!graph.selectedLeaves([0U, uint.max, uint.max, uint.max])[0]);
}
