module benchmark.json_comparison;

import benchmark.json_output : OutputMode, NodeKind, JsonOutput, projectTree, fingerprint,
    handwrittenOutput, ambiguousOutput;
import benchmark.json_npegged : NPJson = JSON, NPJsonTree = TreeJSON, NPJsonSpans = SpanJSON;
import benchmark.json_pegged : PJson = JSON;
import npegged.peg : ParseContext, check, parseRecords, CompactResult;
import benchmark.ambiguous_npegged : NPAmbiguous = Ambiguous, NPAmbiguousRecords = AmbiguousRecords;
import benchmark.ambiguous_pegged : PAmbiguous = Ambiguous;
import npegged.storage : Status;
import benchmark.json_grammar : treeTag, spanTag;

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

private CompactResult compactParse(ref ParseContext context, string input, OutputMode mode,
        bool ambiguous, size_t outputLimit) @nogc nothrow {
    if (mode == OutputMode.spans) {
        if (ambiguous)
            return parseRecords!(NPAmbiguousRecords.opCall, spanTag, false)(context, input, outputLimit);
        return parseRecords!(NPJsonSpans.opCall, spanTag, false)(context, input, outputLimit);
    }
    if (ambiguous)
        return parseRecords!(NPAmbiguousRecords.opCall, treeTag, false)(context, input, outputLimit);
    return parseRecords!(NPJsonTree.opCall, treeTag, false)(context, input, outputLimit);
}

@nogc nothrow unittest {
    ParseContext context;
    auto output = compactParse(context, "[1]", OutputMode.tree, false, 1 << 20);
    assert(output.successful && output.nodes.length == 2 && output.nodes[1].parent == 0);
    auto spans = compactParse(context, "[1]", OutputMode.spans, false, 1 << 20);
    assert(spans.nodes.length == 1 && spans.nodes[0].parent == size_t.max);
    assert(compactParse(context, "aac", OutputMode.spans, true, 1 << 20).successful);
    assert(compactParse(context, "aac", OutputMode.tree, true, 1 << 20).successful);
    auto empty = compactParse(context, "{}", OutputMode.spans, false, 0);
    assert(empty.successful && empty.nodes.length == 0 && empty.outputArena.allocationCalls == 0);
}

private Observation summarize(ref CompactResult output) @nogc nothrow {
    return Observation(output.successful, output.successful ? fingerprint(output.nodes) : 0,
            output.nodes.length, output.arena.allocationCalls + output.outputArena.allocationCalls,
            output.arena.requestedBytes + output.outputArena.requestedBytes,
            output.arena.used + output.outputArena.used, true, output.status == Status.mismatch
            ? Status.ok : output.status);
}

@nogc nothrow unittest {
    CompactResult output;
    assert(summarize(output).status == Status.invalidInput);
    output.status = Status.mismatch;
    assert(summarize(output).status == Status.ok && !summarize(output).accepted);
    output.successful = true;
    assert(summarize(output).outputHash != 0);
}

Observation observeNPegged(string input, OutputMode mode, bool ambiguous = false,
        size_t memoryLimit = 256 * 1024 * 1024, size_t outputLimit = 256 * 1024 * 1024) @nogc nothrow {
    ParseContext context;
    context.memoryLimit = memoryLimit;
    if (mode == OutputMode.validation) {
        auto native = ambiguous ? check!(NPAmbiguous.opCall)(context, input) : check!(NPJson.opCall)(
                context, input);
        JsonOutput output;
        output.accepted = native.successful;
        auto result = summarize(output);
        result.allocationCalls = native.arena.allocationCalls;
        result.payloadBytes = native.arena.requestedBytes;
        result.reservedBytes = native.arena.used;
        if (native.status != Status.ok && native.status != Status.mismatch)
            result.status = native.status;
        return result;
    }
    auto native = compactParse(context, input, mode, ambiguous, outputLimit);
    return summarize(native);
}

@nogc nothrow unittest {
    foreach (mode; [OutputMode.validation, OutputMode.spans, OutputMode.tree]) {
        auto np = observeNPegged(` {"a":[-1.5e2,true,false,null]} `, mode);
        auto hw = observeHandwritten(` {"a":[-1.5e2,true,false,null]} `, mode);
        assert(np.accepted && hw.accepted && np.outputHash == hw.outputHash);
        assert(np.outputNodes == hw.outputNodes);
        if (mode == OutputMode.validation)
            assert(np.allocationCalls == 0);
        else
            assert(np.allocationCalls == hw.allocationCalls);
        assert(!observeNPegged("{}x", mode).accepted);
        auto limited = observeNPegged("{}x", mode, false, 0);
        assert(!limited.accepted);
        assert(limited.status == Status.ok);
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
    if (mode == OutputMode.validation) {
        auto np = ambiguous ? check!(NPAmbiguous.opCall)(context, input) : check!(NPJson.opCall)(context,
                input);
        auto p = ambiguous ? PAmbiguous(input) : PJson(input);
        if (np.status != Status.ok && np.status != Status.mismatch)
            return false;
        return (hw.accepted == expected) & ((np.successful
                && np.end == input.length) == expected) & ((p.successful && p.end == input.length) == expected);
    }
    auto np = compactParse(context, input, mode, ambiguous, npOutputLimit);
    auto p = ambiguous ? PAmbiguous(input) : PJson(input);
    if (np.status != Status.ok && np.status != Status.mismatch)
        return false;
    JsonOutput pOutput;
    pOutput.arena.limit = pOutputLimit;
    pOutput.accepted = p.successful && p.end == input.length;
    if (pOutput.accepted && !projectTree(p, mode, pOutput))
        return false;
    if (hw.accepted != expected || np.successful != expected || pOutput.accepted != expected
            || np.nodes.length != hw.nodes.length || hw.nodes != pOutput.nodes)
        return false;
    foreach (i, node; np.nodes) {
        auto common = hw.nodes[i];
        if (node.kind != cast(uint)common.kind || node.begin != common.begin || node.end != common.end
                || node.parent != common.parent)
            return false;
    }
    return true;
}

unittest {
    foreach (mode; [OutputMode.validation, OutputMode.spans, OutputMode.tree]) {
        assert(verifyOutputs(` {"a":[true,false,null,0,"x"],"b":{}} `, mode, true));
        assert(verifyOutputs("[1,]", mode, false));
        assert(!verifyOutputs("[]", mode, false));
        assert(verifyOutputs("{}x", mode, false, false, 0));
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
