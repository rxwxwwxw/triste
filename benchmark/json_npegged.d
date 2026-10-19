module benchmark.json_npegged;
import npegged.grammar;

version (NPeggedLL1)
    private enum backend = ParserBackend.ll1;
else version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
import benchmark.json_grammar : jsonGrammar, treeTag, spanTag;

mixin(grammar!(Memoization.selective, void, backend)(jsonGrammar));

// The same language, with compile-time semantic output selection.
private struct TreeProjection {
    mixin(grammar!(Memoization.selective, treeTag, backend)(jsonGrammar));
}

private struct SpanProjection {
    mixin(grammar!(Memoization.selective, spanTag, backend)(jsonGrammar));
}

alias TreeJSON = TreeProjection.JSON;
alias SpanJSON = SpanProjection.JSON;
