module benchmark.json_npegged;
import npegged.grammar;
import benchmark.json_grammar : jsonGrammar, treeTag, spanTag;

mixin(grammar!(Memoization.selective)(jsonGrammar));

// The same language, with compile-time semantic output selection.
private struct TreeProjection {
    mixin(grammar!(Memoization.selective, treeTag)(jsonGrammar));
}

private struct SpanProjection {
    mixin(grammar!(Memoization.selective, spanTag)(jsonGrammar));
}

alias TreeJSON = TreeProjection.JSON;
alias SpanJSON = SpanProjection.JSON;
