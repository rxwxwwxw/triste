module tests.pure_islands_audit;

import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private uint selected(string name) @nogc nothrow pure {
    if (!name.length)
        return uint.max;
    return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : 1;
}

ParseTree dummyAction(bool CT)(ref State!CT state, ParseTree tree) @nogc nothrow {
    return tree;
}

private State!(CT, Check).Node opaqueStub(bool CT, int Check)(ref State!(CT, Check) state, size_t pos) @nogc nothrow {
    return literal!("?")(state, pos);
}

enum auditGrammarDef = `
AuditGrammar:
    Root <- Pure eoi
    Pure <- [a-z]+
    Opaque <- opaqueStub
    CallOpaque <- 'x' Opaque
    Act <- '!' {dummyAction}
    CallAct <- Pure Act
    LeftRec <- LeftRec 'a' / Pure
    MutualA <- 'a' MutualB / 'x'
    MutualB <- 'b' MutualA / 'y'
`;

struct AuditSuite(ParserBackend backend) {
    mixin(grammar!(Memoization.selective, selected, backend)(auditGrammarDef));
}

alias Reference = AuditSuite!(ParserBackend.combinators).AuditGrammar;
alias Candidate = AuditSuite!(ParserBackend.direct).AuditGrammar;

int main() @nogc nothrow {
    alarm(15);

    // =========================================================================
    // 1. Static Invariant Verification: Pure Island Entries
    // =========================================================================
    version (NPeggedPureIslands) {
        static assert(__traits(hasMember, Candidate, "npeggedPureIslandEntries"),
                "Candidate must expose npeggedPureIslandEntries when NPeggedPureIslands is enabled");
        static assert(!__traits(hasMember, Reference, "npeggedPureIslandEntries"),
                "Reference combinators backend must NOT expose npeggedPureIslandEntries");

        // Permitted pure island rules:
        // - Root: closed, acyclic, action-free, shareable
        // - Pure: closed, acyclic, action-free, shareable
        // - opCall: alias to Root
        // Prohibited rules that MUST NEVER be pure islands:
        // - Opaque: references external opaque symbol (known=false)
        // - CallOpaque: calls opaque rule (known=false)
        // - Act: contains semantic action (actionful=true)
        // - CallAct: calls actionful rule (actionful=true)
        // - LeftRec: direct left recursion (leftRecursive=true, shareable=false)
        // - MutualA, MutualB: mutual recursion (shareable=false)
        static assert(Candidate.npeggedPureIslandEntries == ["Root", "Pure", "opCall"],
                "Only Root, Pure, and opCall may be classified as pure islands");
    }

    // =========================================================================
    // 2. Behavioral Verification: Pure Entry vs Action Entry vs Budget Guards
    // =========================================================================
    const pureInput = "abcdef";
    const mixedInput = "abcdef!";

    // A. Pure Entry: Check mode without budgets (Pure Island Active)
    ParseContext ctxUnbounded;
    ctxUnbounded.stepLimit = ctxUnbounded.depthLimit = ctxUnbounded.memoryLimit = size_t.max;
    auto resCandidatePure = check!(Candidate.Root)(ctxUnbounded, pureInput);
    auto resReferencePure = check!(Reference.Root)(ctxUnbounded, pureInput);
    assert(resCandidatePure.status == Status.ok);
    assert(resCandidatePure.status == resReferencePure.status);
    assert(resCandidatePure.end == resReferencePure.end);
    assert(resCandidatePure.failEnd == resReferencePure.failEnd);

    // B. Unbounded records: a hierarchical selection may still fall back
    auto recCandidatePure = parseRecords!(Candidate.Root, selected)(ctxUnbounded, pureInput, size_t
            .max);
    auto recReferencePure = parseRecords!(Reference.Root, selected)(ctxUnbounded, pureInput, size_t
            .max);
    assert(recCandidatePure.status == Status.ok);
    assert(recCandidatePure.status == recReferencePure.status);
    assert(recCandidatePure.nodes.length == recReferencePure.nodes.length);
    assert(recCandidatePure.end == recReferencePure.end);

    // C. Pure Entry: Under explicit finite stepLimit (P06 Guard Diverts to Reference)
    ParseContext ctxBudgeted;
    ctxBudgeted.stepLimit = 3;
    auto resBudgetedCand = check!(Candidate.Root)(ctxBudgeted, pureInput);
    auto resBudgetedRef = check!(Reference.Root)(ctxBudgeted, pureInput);
    assert(resBudgetedCand.status == Status.resourceLimit);
    assert(resBudgetedCand.status == resBudgetedRef.status);
    assert(resBudgetedCand.failEnd == resBudgetedRef.failEnd);

    // D. Action-bearing Entry: Always uses Reference treeFallback
    auto resCandidateAct = check!(Candidate.CallAct)(ctxUnbounded, mixedInput);
    auto resReferenceAct = check!(Reference.CallAct)(ctxUnbounded, mixedInput);
    assert(resCandidateAct.status == Status.ok);
    assert(resCandidateAct.status == resReferenceAct.status);
    assert(resCandidateAct.end == resReferenceAct.end);

    printf("pure islands audit tests passed\n");
    return 0;
}
