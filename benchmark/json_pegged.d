module benchmark.json_pegged;
import pegged.grammar;
import benchmark.json_grammar : jsonGrammar;

mixin(grammar(jsonGrammar));

unittest {
    import pegged.parser : MetaPegged = Pegged;

    // The vendored dynamic builder expects Sequence directly under Expression.
    // Bridge its older AST format only while exercising the optional hook API.
    auto savedMetaBefore = MetaPegged.before;
    MetaPegged.before = MetaPegged.before.dup;
    MetaPegged.before["LongestExpression"] = (ParseTree p) @safe { return MetaPegged.Sequence(p); };
    scope (exit)
        MetaPegged.before = savedMetaBefore;
    auto savedBefore = JSON.before;
    auto savedAfter = JSON.after;
    auto savedRules = JSON.rules;
    scope (exit) {
        JSON.before = savedBefore;
        JSON.after = savedAfter;
        JSON.rules = savedRules;
        JSON.forgetMemo();
    }
    JSON.rules = JSON.rules.dup;
    assert(JSON.isRule("JSON.Document") && !JSON.isRule("Other.Document"));
    JSON.forgetMemo();
    auto input = ParseTree("", false, [], "{}");
    assert(JSON.Document(input).successful);
    assert(JSON.Document(input).successful);
    JSON.addRuleBefore("Document", "HookBefore <- 'z'");
    assert(JSON.Document("z").successful);
    assert(JSON.Document("true").successful);
    JSON.addRuleAfter("Document", "HookAfter <- 'y'");
    assert(JSON.Document("y").successful);
    assert(JSON.Document("true").successful);
    assert(!JSON.Document("?").successful);
}
