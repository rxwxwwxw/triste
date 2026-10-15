module benchmark.ambiguous_pegged;
import pegged.grammar;

mixin(grammar(`Ambiguous:
    Start <- ('a'* 'b' / 'a'* 'c') eoi
`));

unittest {
    import pegged.parser : MetaPegged = Pegged;

    // The vendored dynamic builder expects Sequence directly under Expression.
    // Bridge its older AST format only while exercising the optional hook API.
    auto savedMetaBefore = MetaPegged.before;
    MetaPegged.before = MetaPegged.before.dup;
    MetaPegged.before["LongestExpression"] = (ParseTree p) @safe { return MetaPegged.Sequence(p); };
    scope (exit)
        MetaPegged.before = savedMetaBefore;
    auto savedBefore = Ambiguous.before;
    auto savedAfter = Ambiguous.after;
    auto savedRules = Ambiguous.rules;
    scope (exit) {
        Ambiguous.before = savedBefore;
        Ambiguous.after = savedAfter;
        Ambiguous.rules = savedRules;
        Ambiguous.forgetMemo();
    }
    Ambiguous.rules = Ambiguous.rules.dup;
    assert(Ambiguous.isRule("Ambiguous.Start") && !Ambiguous.isRule("Other.Start"));
    Ambiguous.forgetMemo();
    auto input = ParseTree("", false, [], "aac");
    assert(Ambiguous.Start(input).successful);
    assert(Ambiguous.Start(input).successful); // exercise a cached rule result
    Ambiguous.addRuleBefore("Start", "HookBefore <- 'z'");
    assert(Ambiguous.Start("z").successful);
    assert(Ambiguous.Start("aac").successful);
    Ambiguous.addRuleAfter("Start", "HookAfter <- 'y'");
    assert(Ambiguous.Start("y").successful);
    assert(Ambiguous.Start("aac").successful);
    assert(!Ambiguous.Start("?").successful);
}
