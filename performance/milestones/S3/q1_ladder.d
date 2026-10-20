module s3_q1_ladder;

import benchmark.measurement : Observation, consume, opaqueInput;
import npegged.peg : State, ParseContext, CheckResult, check, literal, option, and, eoi, defined, CharSetMask;
import npegged.dfa : compileDFA, RegularExpression, RegularKind, dfaToken, tryDFAEntry;
import npegged.storage : Status;
import core.time : MonoTime;
import core.stdc.stdio : printf;

private alias Original = and!(option!(literal!"a"), eoi);
private enum table = () {
    CharSetMask mask;
    mask.addChar('a');
    return compileDFA([
        RegularExpression(RegularKind.bytes, mask),
        RegularExpression(RegularKind.optional, CharSetMask.init, [0]),
        RegularExpression(RegularKind.endOfInput),
        RegularExpression(RegularKind.sequence, CharSetMask.init, [1, 2])
    ], 3);
}();
private alias Token = dfaToken!(Original, table);

private auto entry(ref State!(false, 1) state, size_t pos) @nogc nothrow {
    return state.rule!(defined!(Token, "Tiny.Root"), "Tiny.Root", false)(pos);
}

// The exact Q1 grammar/table and rule body, with the generated-entry protocol.
// This adapter isolates entry cost; generator eligibility is checked separately.
private struct Q1Bridge {
    pragma(inline, true) static auto Root(ref State!(false, 1) state, size_t pos) @nogc nothrow {
        return entry(state, pos);
    }

    pragma(inline, true) static bool npeggedTryCheck(string Entry)(ref ParseContext context,
            scope string input, ref CheckResult result) @nogc nothrow if (Entry == "Root") {
        return tryDFAEntry!(Original, table)(context, input, result);
    }
}

private auto bridgeReference(ref State!(false, 1) state, size_t pos) @nogc nothrow {
    return Q1Bridge.Root(state, pos);
}

@nogc nothrow unittest {
    foreach (input; ["", "a", "b", "aa", "a\0"])
        foreach (limit; 0 .. 16) {
            ParseContext context;
            context.stepLimit = limit;
            context.memoryLimit = 0;
            auto exact = check!bridgeReference(context, input);
            auto lean = check!(Q1Bridge.Root)(context, input);
            assert(exact.status == lean.status && exact.successful == lean.successful);
            assert(exact.end == lean.end && exact.failEnd == lean.failEnd);
            assert(exact.arena.allocationCalls == lean.arena.allocationCalls);
        }
}

/// Same validation-mode Observation contract as the main timing harness.
Observation observe(size_t rung, string input) @nogc nothrow {
    Observation result;
    result.accepted = true;
    if (rung == 0)
        return result; // Empty body: valid fixtures only. No parser or handwritten work.
    const accepted = input.length == 0 || input == "a";
    if (rung == 1) {
        result.accepted = accepted;
        result.status = accepted ? Status.ok : Status.mismatch;
        return result;
    }
    CheckResult owner;
    if (rung == 2) {
        owner.successful = accepted;
        owner.status = accepted ? Status.ok : Status.mismatch;
    } else if (rung < 6) {
        ParseContext context;
        owner.arena.limit = context.memoryLimit;
        State!(false, 1) state;
        state.arena = &owner.arena;
        state.input = input;
        state.context = context;
        if (rung == 3) {
            owner.successful = accepted;
            owner.status = accepted ? Status.ok : Status.mismatch;
        } else {
            auto node = rung == 4 ? state.rule!(Original, "Tiny.Root", false)(0) : entry(state, 0);
            node = state.finish(node);
            owner.successful = node.successful;
            owner.status = state.status != Status.ok ? state.status : node.successful ? Status.ok : Status
                .mismatch;
        }
    } else {
        ParseContext context;
        if (rung == 7) {
            auto checked = check!bridgeReference(context, input);
            result.accepted = checked.successful;
            result.status = checked.status;
            return result;
        }
        if (rung == 8) {
            auto checked = check!(Q1Bridge.Root)(context, input);
            result.accepted = checked.successful;
            result.status = checked.status;
            return result;
        }
        auto checked = check!entry(context, input);
        result.accepted = checked.successful;
        result.status = checked.status;
        return result;
    }
    result.accepted = owner.successful;
    result.status = owner.status;
    return result;
}

@nogc nothrow unittest {
    foreach (input; ["", "a"])
        foreach (rung; 0 .. 9)
            assert(equivalent(observe(rung, input), observe(6, input)));
    foreach (input; ["b", "aa", "a\0"])
        foreach (rung; 1 .. 7)
            assert(equivalent(observe(rung, input), observe(6, input)));
    assert(!equivalent(observe(0, "b"), observe(6, "b")));
}

bool equivalent(Observation a, Observation b) @nogc nothrow pure {
    return a == b;
}

@nogc nothrow unittest {
    auto reference = observe(6, "a");
    auto changed = reference;
    changed.outputHash = 1;
    assert(!equivalent(changed, reference));
    changed = reference;
    changed.status = Status.resourceLimit;
    assert(!equivalent(changed, reference));
}

int main() @nogc nothrow {
    enum iterations = 1_000_000;
    enum string[9] names = [
        "floor", "handwritten", "result_arena", "state_context", "rule_body", "defined_dfa",
        "check", "exact_bridge", "lean_bridge"
    ];
    printf("fixture,rung,iteration,input_bytes,elapsed_ns,successful,status\n");
    foreach (input; ["", "a"]) {
        foreach (rung; 0 .. 9)
            if (!equivalent(observe(rung, input), observe(6, input)))
                return 1;
        // Rotate layer order per sample, with three discarded warmup blocks.
        foreach (sample; 0 .. 24)
            foreach (offset; 0 .. 9) {
                const rung = (sample + offset) % 9;
                const start = MonoTime.currTime;
                foreach (i; 0 .. iterations) {
                    auto result = observe(rung, opaqueInput(input));
                    consume(result.accepted, result.outputHash, result.outputNodes, result.status);
                }
                const elapsed = (MonoTime.currTime - start).total!"nsecs";
                if (sample >= 3)
                    printf("%s,%s,%d,%zu,%.9f,1,ok\n", input.length ? "one".ptr : "empty".ptr,
                            names[rung].ptr, sample - 3, input.length, cast(double)elapsed / iterations);
            }
    }
    return 0;
}
