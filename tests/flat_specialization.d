module tests.flat_specialization;

import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private uint selectAll(string name) @nogc nothrow pure {
    return 0;
}

enum grammarDef = `
FlatGrammar:
    Root <- [a-z]+ eoi
`;

enum recGrammarDef = `
RecGrammar:
    Root <- Expr eoi
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`;

struct FlatSuite(ParserBackend backend) {
    mixin(grammar!(Memoization.selective, selectAll, backend)(grammarDef));
}

struct RecSuite(ParserBackend backend) {
    mixin(grammar!(Memoization.selective, selectAll, backend)(recGrammarDef));
}

alias FlatDirect = FlatSuite!(ParserBackend.direct).FlatGrammar;
alias RecDirect = RecSuite!(ParserBackend.direct).RecGrammar;

int main() @nogc nothrow {
    alarm(15);

    // 1. Static classification verification
    version (NPeggedSharedOutput) {
        static assert(!__traits(hasMember, FlatDirect, "npeggedSharedOutputEligible")
                || !FlatDirect.npeggedSharedOutputEligible,
                "Non-recursive grammar must NOT be shared-output eligible");
        static assert(__traits(hasMember, RecDirect, "npeggedSharedOutputEligible")
                && RecDirect.npeggedSharedOutputEligible,
                "Left-recursive grammar must be shared-output eligible");
    }

    // 2. Behavioral verification on FlatGrammar
    const flatInput = "abcdef";
    ParseContext ctx;
    auto resFlat = parseRecords!(FlatDirect.Root, selectAll)(ctx, flatInput);
    assert(resFlat.status == Status.ok);
    assert(resFlat.nodes.length == 1);
    assert(resFlat.end == 6);

    // 3. Behavioral verification on RecGrammar with shared output
    const recInput = "1+1+1+1";
    ParseContext ctxRec;
    version (NPeggedSharedOutput)
        ctxRec.sharedOutput = true;

    auto resRec = parseRecords!(RecDirect.Root, selectAll)(ctxRec, recInput);
    assert(resRec.status == Status.ok);
    assert(resRec.end == 7);

    printf("flat specialization tests passed\n");
    return 0;
}
