module benchmark.json_comparison;

import benchmark.json_output : OutputMode, JsonOutput, projectTree, fingerprint, handwrittenOutput, ambiguousOutput;
import benchmark.json_npegged : NPJson = JSON;
import benchmark.json_pegged : PJson = JSON;
import npegged.peg : ParseContext;
import benchmark.ambiguous_npegged : NPAmbiguous = Ambiguous;
import benchmark.ambiguous_pegged : PAmbiguous = Ambiguous;
import npegged.storage : Status;

public import benchmark.measurement : Observation;

private Observation summarize(ref JsonOutput output) @nogc nothrow {
    return Observation(output.accepted, output.accepted ? fingerprint(output.nodes) : 0,
            output.nodes.length, output.arena.allocationCalls, output.arena.requestedBytes,
            output.arena.used, true, output.arena.status);
}

@nogc nothrow unittest {
    JsonOutput output;
    auto failed = summarize(output);
    assert(!failed.accepted && failed.outputHash == 0 && failed.outputNodes == 0);
    output.accepted = true;
    auto empty = summarize(output);
    assert(empty.accepted && empty.outputHash != 0 && empty.allocatorMeasured);
    output.arena.status = Status.outOfMemory;
    assert(summarize(output).status == Status.outOfMemory);
}

Observation observeHandwritten(string input, OutputMode mode, bool ambiguous = false) @nogc nothrow {
    auto output = ambiguous ? ambiguousOutput(input, mode) : handwrittenOutput(input, mode);
    return summarize(output);
}

@nogc nothrow unittest {
    auto output = observeHandwritten("[null]", OutputMode.tree);
    assert(output.accepted && output.outputNodes == 2 && output.allocationCalls == 1);
    assert(!observeHandwritten("[", OutputMode.tree).accepted);
}

Observation observeNPegged(string input, OutputMode mode, bool ambiguous = false,
        size_t memoryLimit = 256 * 1024 * 1024, size_t outputLimit = 256 * 1024 * 1024) @nogc nothrow {
    ParseContext context;
    context.memoryLimit = memoryLimit;
    auto native = ambiguous ? NPAmbiguous(context, input) : NPJson(context, input);
    JsonOutput output;
    output.arena.limit = outputLimit;
    // Both benchmark grammars include eoi in their start rule.
    output.accepted = native.successful;
    if (output.accepted && mode != OutputMode.validation) {
        if (!projectTree(native.tree, mode, output))
            output.reject();
    }
    auto result = summarize(output);
    result.allocationCalls += native.arena.allocationCalls;
    result.payloadBytes += native.arena.requestedBytes;
    result.reservedBytes += native.arena.used;
    if (native.status != Status.ok && native.status != Status.mismatch)
        result.status = native.status;
    return result;
}

@nogc nothrow unittest {
    foreach (mode; [OutputMode.validation, OutputMode.spans, OutputMode.tree]) {
        auto np = observeNPegged(` {"a":[-1.5e2,true,false,null]} `, mode);
        auto hw = observeHandwritten(` {"a":[-1.5e2,true,false,null]} `, mode);
        assert(np.accepted && hw.accepted && np.outputHash == hw.outputHash);
        assert(np.outputNodes == hw.outputNodes && np.allocationCalls > hw.allocationCalls);
        assert(!observeNPegged("{}x", mode).accepted);
        auto limited = observeNPegged("{}x", mode, false, 0);
        assert(!limited.accepted && limited.status == Status.resourceLimit);
        if (mode != OutputMode.validation) {
            auto outputLimited = observeNPegged(`"x"`, mode, false, 256 * 1024 * 1024, 0);
            assert(!outputLimited.accepted && outputLimited.status == Status.resourceLimit);
            assert(outputLimited.outputNodes == 0);
        }
    }
}

Observation observePegged(string input, OutputMode mode, bool ambiguous = false, size_t outputLimit = 256 * 1024 * 1024) {
    auto native = ambiguous ? PAmbiguous(input) : PJson(input);
    JsonOutput output;
    output.arena.limit = outputLimit;
    // Both benchmark grammars include eoi in their start rule.
    output.accepted = native.successful;
    if (output.accepted && mode != OutputMode.validation) {
        if (!projectTree(native, mode, output))
            output.reject();
    }
    auto result = summarize(output);
    // Pegged's GC is measured separately; these counts cover the output adapter only.
    result.allocatorMeasured = false;
    return result;
}

unittest {
    foreach (mode; [OutputMode.validation, OutputMode.spans, OutputMode.tree]) {
        auto p = observePegged(`{"a":[0,"x",false]}`, mode);
        auto hw = observeHandwritten(`{"a":[0,"x",false]}`, mode);
        assert(p.accepted && p.outputHash == hw.outputHash && p.outputNodes == hw.outputNodes);
        assert(!p.allocatorMeasured && !observePegged("[", mode).accepted);
        if (mode != OutputMode.validation) {
            auto limited = observePegged(`"x"`, mode, false, 0);
            assert(!limited.accepted && limited.status == Status.resourceLimit && !limited
                    .outputNodes);
        }
    }
}

/// Compare full ordered records before timing; hashes are only the timed sink.
bool verifyOutputs(string input, OutputMode mode, bool expected, bool ambiguous = false,
        size_t memoryLimit = 256 * 1024 * 1024, size_t npOutputLimit = 256 * 1024 * 1024,
        size_t pOutputLimit = 256 * 1024 * 1024) {
    auto hw = ambiguous ? ambiguousOutput(input, mode) : handwrittenOutput(input, mode);
    ParseContext context;
    context.memoryLimit = memoryLimit;
    auto np = ambiguous ? NPAmbiguous(context, input) : NPJson(context, input);
    auto p = ambiguous ? PAmbiguous(input) : PJson(input);
    if (np.status != Status.ok && np.status != Status.mismatch)
        return false;
    JsonOutput npOutput, pOutput;
    npOutput.arena.limit = npOutputLimit;
    pOutput.arena.limit = pOutputLimit;
    npOutput.accepted = np.successful & (np.end == input.length);
    pOutput.accepted = p.successful & (p.end == input.length);
    if (mode != OutputMode.validation) {
        if (npOutput.accepted && !projectTree(np.tree, mode, npOutput))
            return false;
        if (pOutput.accepted && !projectTree(p, mode, pOutput))
            return false;
    }
    // Evaluate all three acceptance checks and both complete record comparisons.
    return (hw.accepted == expected) & (npOutput.accepted == expected) & (
            pOutput.accepted == expected) & (hw.nodes == npOutput.nodes) & (hw.nodes == pOutput.nodes);
}

unittest {
    foreach (mode; [OutputMode.validation, OutputMode.spans, OutputMode.tree]) {
        assert(verifyOutputs(` {"a":[true,false,null,0,"x"],"b":{}} `, mode, true));
        assert(verifyOutputs("[1,]", mode, false));
        assert(!verifyOutputs("[]", mode, false));
        assert(!verifyOutputs("{}x", mode, false, false, 0));
        if (mode != OutputMode.validation) {
            assert(!verifyOutputs(`"x"`, mode, true, false, 256 * 1024 * 1024, 0));
            assert(!verifyOutputs(`"x"`, mode, true, false, 256 * 1024 * 1024, 256 * 1024 * 1024, 0));
        }
    }
}

unittest {
    foreach (mode; [OutputMode.validation, OutputMode.spans, OutputMode.tree]) {
        foreach (input; ["b", "aac"]) {
            assert(verifyOutputs(input, mode, true, true));
            assert(observePegged(input, mode, true).outputHash == observeNPegged(input, mode, true)
                    .outputHash);
        }
        assert(verifyOutputs("aad", mode, false, true));
        assert(observeHandwritten("aac", mode, true).accepted);
    }
}
