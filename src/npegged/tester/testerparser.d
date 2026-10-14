// Derived from Pegged (Boost 1.0).
module npegged.tester.testerparser;
import npegged.grammar;

enum string testerGrammar = `
TesterGrammar:

Root < Node eoi

Node <
    / :'^' identifier
    / identifier (%Branch)*

Branch <
    / OrderedBranch
    / UnorderedBranch
    / ConciseBranch

OrderedBranch <
    / :'->' :'{' Node+ :'}'
    / :'->' Node

UnorderedBranch <
    / :'~>' :'{' Node+ :'}'
    / :'~>' Node

ConciseBranch < :'->' '{..}'

Spacing <: (blank / Comment)*

Comment <-
    / '//' (!eol .)* (eol)
    / '/*' (!'*/' .)* '*/'
    / NestedComment

NestedComment <- '/+' (!NestedCommentEnd . / NestedComment) NestedCommentEnd

# This is needed to make the /+ +/ nest when the grammar is placed into a D nested comment ;)
NestedCommentEnd <- '+/'
`;

mixin(grammar(testerGrammar));

@nogc nothrow unittest {
    ParseContext context;
    auto ordered = TesterGrammar(context, "Root->{A B}");
    assert(ordered.successful && ordered.end == 11);
    auto unordered = TesterGrammar(context, "Root~>{B A}");
    assert(unordered.successful);
    auto invalid = TesterGrammar(context, "Root->{");
    assert(!invalid.successful);
}
