module tests.pure_islands_budget;

import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private uint selected(string name) @nogc nothrow pure {
    return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : 1;
}

ParseTree dummyAction(bool CT)(ref State!CT state, ParseTree tree) @nogc nothrow {
    return tree;
}

struct Event {
    string name;
    size_t position;
    bool successful;
}

struct TraceLog {
    Event[64] events;
    size_t count;
    void add(Event e) @nogc nothrow {
        if (count < events.length)
            events[count++] = e;
    }
}

private void traceCallback(string name, size_t pos, bool succ, void* data) @nogc nothrow {
    (cast(TraceLog*)data).add(Event(name, pos, succ));
}

enum grammarDef = `
BudgetIslands:
    Root <- [a-z]+ eoi
    Mixed <- Root Act
    Act <- '!' {dummyAction}
`;

struct Suite(ParserBackend backend) {
    mixin(grammar!(Memoization.selective, selected, backend)(grammarDef));
}

alias Reference = Suite!(ParserBackend.combinators).BudgetIslands;
alias Candidate = Suite!(ParserBackend.direct).BudgetIslands;

int main() @nogc nothrow {
    alarm(15);
    const input = "abc";
    const mixedInput = "abc!";

    // Verify static classification
    version (NPeggedPureIslands) {
        static assert(__traits(hasMember, Candidate, "npeggedPureIslandEntries"));
        static assert(Candidate.npeggedPureIslandEntries == ["Root", "opCall"]);
    }

    // =========================================================================
    // 1. StepLimit Sweep: Direct Lowered Execution vs. TreeFallback Execution
    // =========================================================================
    // Direct recognition completes in 4 steps; Reference treeFallback takes 11 steps.
    // For 4 <= stepLimit < 11:
    //   - Unguarded direct recognition succeeds (status=ok, failEnd=3)
    //   - TreeFallback fails with resourceLimit (status=resourceLimit)
    //   - Guarded Candidate.Root correctly falls back to TreeFallback to preserve
    //     exact reference semantics under finite step budgets.
    foreach (step; 0 .. 16) {
        ParseContext ctx;
        ctx.stepLimit = step;

        // Candidate via API check (guarded pure island)
        auto resCandidate = check!(Candidate.Root)(ctx, input);

        // Reference via API check (reference path)
        auto resReference = check!(Reference.Root)(ctx, input);

        // Guarded candidate MUST match reference status and failEnd exactly
        assert(resCandidate.status == resReference.status, "Candidate and Reference status mismatch at stepLimit");
        assert(resCandidate.failEnd == resReference.failEnd, "Candidate and Reference failEnd mismatch at stepLimit");
        assert(resCandidate.end == resReference.end, "Candidate and Reference end mismatch at stepLimit");

        // Unguarded direct engine execution:
        CheckResult resDirect;
        State!(false, 1) stateDirect;
        stateDirect.arena = &resDirect.arena;
        stateDirect.input = input;
        stateDirect.context = ctx;
        auto nodeDirect = stateDirect.finish(Candidate._Root!(false, 1)(stateDirect, 0));
        resDirect.status = stateDirect.status != Status.ok ? stateDirect.status
            : (nodeDirect.successful ? Status.ok : Status.mismatch);

        if (step >= 4 && step < 11) {
            // Document the exact budget-edge failure: direct succeeded while reference failed
            assert(resDirect.status == Status.ok, "Direct path should succeed for step >= 4");
            assert(resReference.status == Status.resourceLimit, "Reference path should fail for step < 11");
        }
    }

    // =========================================================================
    // 2. MemoryLimit Sweep: Zero Allocation vs. ParseTree Allocation
    // =========================================================================
    // Direct recognition allocates 0 arena bytes.
    // TreeFallback allocates ParseTree nodes on the arena.
    // Under tight memory limits (e.g. 16 to 128 bytes):
    //   - Unguarded direct recognition succeeds (0 bytes allocated)
    //   - Reference treeFallback fails with resourceLimit / memoryFailure
    foreach (memLimit; [0, 16, 32, 64, 128, 4096, 65536]) {
        ParseContext ctx;
        ctx.memoryLimit = memLimit;

        auto resCandidate = check!(Candidate.Root)(ctx, input);
        auto resReference = check!(Reference.Root)(ctx, input);

        // Guarded candidate preserves exact reference memory contract
        assert(resCandidate.status == resReference.status, "MemoryLimit status mismatch");
        assert(resCandidate.failEnd == resReference.failEnd, "MemoryLimit failEnd mismatch");

        // Unguarded direct execution requires 0 bytes
        CheckResult resDirect;
        resDirect.arena.limit = memLimit;
        State!(false, 1) stateDirect;
        stateDirect.arena = &resDirect.arena;
        stateDirect.input = input;
        stateDirect.context = ctx;
        auto nodeDirect = stateDirect.finish(Candidate._Root!(false, 1)(stateDirect, 0));
        resDirect.status = stateDirect.status != Status.ok ? stateDirect.status
            : (nodeDirect.successful ? Status.ok : Status.mismatch);

        if (memLimit > 0 && memLimit < 256) {
            // Direct uses 0 bytes so it succeeds, while reference runs out of memory
            assert(resDirect.status == Status.ok);
            assert(resReference.status == Status.resourceLimit || resReference.status == Status
                    .outOfMemory);
        }
    }

    // =========================================================================
    // 3. DepthLimit Sweep
    // =========================================================================
    foreach (depth; 0 .. 8) {
        ParseContext ctx;
        ctx.depthLimit = depth;

        auto resCandidate = check!(Candidate.Root)(ctx, input);
        auto resReference = check!(Reference.Root)(ctx, input);

        assert(resCandidate.status == resReference.status, "DepthLimit status mismatch");
        assert(resCandidate.failEnd == resReference.failEnd, "DepthLimit failEnd mismatch");
    }

    // =========================================================================
    // 4. Tracing Observability
    // =========================================================================
    // Trace callbacks observe per-combinator evaluation in reference tree mode,
    // which direct lowered loops do not emit.
    {
        TraceLog refLog, candLog;
        ParseContext ctxRef;
        ctxRef.trace = &traceCallback;
        ctxRef.userData = &refLog;

        ParseContext ctxCand;
        ctxCand.trace = &traceCallback;
        ctxCand.userData = &candLog;

        auto resRef = check!(Reference.Root)(ctxRef, input);
        auto resCand = check!(Candidate.Root)(ctxCand, input);

        assert(resCand.status == resRef.status);
        assert(candLog.count == refLog.count, "Trace event count mismatch");
        foreach (i; 0 .. refLog.count) {
            assert(candLog.events[i].name == refLog.events[i].name);
            assert(candLog.events[i].position == refLog.events[i].position);
            assert(candLog.events[i].successful == refLog.events[i].successful);
        }
    }

    // =========================================================================
    // 5. Records Mode (parseRecords)
    // =========================================================================
    foreach (step; 0 .. 16) {
        ParseContext ctx;
        ctx.stepLimit = step;

        auto recCandidate = parseRecords!(Candidate.Root, selected)(ctx, input);
        auto recReference = parseRecords!(Reference.Root, selected)(ctx, input);

        assert(recCandidate.status == recReference.status);
        assert(recCandidate.failEnd == recReference.failEnd);
        assert(recCandidate.nodes.length == recReference.nodes.length);
    }

    // =========================================================================
    // 6. Mixed Public Entry (Pure -> Action)
    // =========================================================================
    // Mixed entry is NOT classified as a pure island (contains action Act).
    // It must execute the reference tree path regardless of flags.
    foreach (step; [0, 2, 5, 10, 20]) {
        ParseContext ctx;
        ctx.stepLimit = step;

        auto resCand = check!(Candidate.Mixed)(ctx, mixedInput);
        auto resRef = check!(Reference.Mixed)(ctx, mixedInput);

        assert(resCand.status == resRef.status);
        assert(resCand.failEnd == resRef.failEnd);
        assert(resCand.end == resRef.end);
    }

    printf("pure islands budget test passed\n");
    return 0;
}
