module benchmark.ambiguous_npegged;
import npegged.grammar;

version (NPeggedLL1)
    private enum backend = ParserBackend.ll1;
else version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
import benchmark.json_grammar : treeTag;

enum ambiguousGrammar = `Ambiguous:
    Start <- ('a'* 'b' / 'a'* 'c') eoi
`;
mixin(grammar!(Memoization.selective, void, backend)(ambiguousGrammar));
private struct RecordProjection {
    mixin(grammar!(Memoization.selective, treeTag, backend)(ambiguousGrammar));
}

alias AmbiguousRecords = RecordProjection.Ambiguous;
