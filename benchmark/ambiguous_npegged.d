module benchmark.ambiguous_npegged;
import npegged.grammar;
import benchmark.json_grammar : treeTag;

enum ambiguousGrammar = `Ambiguous:
    Start <- ('a'* 'b' / 'a'* 'c') eoi
`;
mixin(grammar!(Memoization.selective)(ambiguousGrammar));
private struct RecordProjection {
    mixin(grammar!(Memoization.selective, treeTag)(ambiguousGrammar));
}

alias AmbiguousRecords = RecordProjection.Ambiguous;
