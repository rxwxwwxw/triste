/** R06 parser oracle. Run with scripts/shared-output-check.sh bounds. */
module tests.shared_output;
import npegged.grammar;
import npegged.records : CompactNode;
import core.sys.posix.unistd : alarm;
import core.stdc.stdio : printf, fprintf, stderr;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
version (NPeggedFullMemo)
    private enum memo = Memoization.yes;
else
    private enum memo = Memoization.selective;
private uint selected(string name) @nogc nothrow pure {
    version (LeafOnly)
        return name.length >= 5 && name[$ - 5 .. $] == ".Atom" ? 1 : uint.max;
    else version (RootOnly)
        return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : uint.max;
    else
        return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : 1;
}

mixin(grammar!(memo, selected, backend)(`
SharedDirect:
    Root <- Expr eoi
    Expr <- Expr '+' Atom / Atom
    Atom <- '(' Expr ')' / 'n'
`));
mixin(grammar!(memo, selected, backend)(`
SharedIndirect:
    Root <- Expr eoi
    Expr <- Sum / Atom
    Sum <- Expr '+' Atom
    Atom <- '(' Expr ')' / 'n'
`));
mixin(grammar!(memo, selected, backend)(`
SharedMutual:
    Root <- A eoi
    A <- B 'a' / 'n'
    B <- A 'b' / 'n'
`));
mixin(grammar!(memo, selected, backend)(`
SharedNullable:
    Root <- A eoi
    A <- A 'n' / eps
`));
mixin(grammar!(memo, selected, backend)(`
SharedProbe:
    Root <- &Expr Expr eoi
    Expr <- Expr '+' Atom / Atom
    Atom <- '(' Expr ')' / 'n'
`));
mixin(grammar!(memo, selected, backend)(`
SharedReplace:
    Root <- Expr eoi
    Expr <- Expr 'n' / 'n' 'n' / 'n'
`));
mixin(grammar!(memo, selected, backend)(`
SharedInsideProbe:
    Root <- Expr eoi
    Expr <- &Expr Expr 'n' / 'n'
`));
mixin(grammar!(memo, selected, backend)(`
SharedLongest:
    Root <- (Short | Long) eoi
    Short <- Expr
    Long <- Expr Expr
    Expr <- Expr 'n' / 'n'
`));
private State!(CT, Check).Node opaque(bool CT, int Check)(ref State!(CT, Check) state, size_t pos) nothrow {
    return literal!"n"(state, pos);
}

private struct Event {
    bool action;
    string name;
    size_t position;
    bool successful;
}

private struct Effects {
    size_t actions, length;
    Event[4096] events;
    void record(bool action, string name, size_t position, bool successful) @nogc nothrow {
        assert(length < events.length);
        events[length++] = Event(action, name, position, successful);
        if (action)
            ++actions;
    }
}

private ParseTree effect(bool CT)(ref State!CT state, ParseTree tree) nothrow {
    (cast(Effects*)state.context.userData).record(true, tree.name, tree.end, tree.successful);
    return tree;
}

private void observe(string name, size_t position, bool accepted, void* user) @nogc nothrow {
    (cast(Effects*)user).record(false, name, position, accepted);
}

mixin(grammar!(memo, selected, backend)(`
SharedOpaque:
    Root <- Expr eoi
    Expr <- Expr 'n' / opaque
`));
mixin(grammar!(memo, selected, backend)(`
SharedAction:
    Root <- Expr eoi
    Expr <- (Expr 'n' / 'n'){effect}
`));
version (NPeggedSharedOutput) {
    static assert(!SharedOpaque.npeggedSharedOutputEligible && !SharedAction
            .npeggedSharedOutputEligible);
    version (RootOnly)
        static assert(!SharedDirect.npeggedSharedOutputEligible);
    else
        static assert(SharedDirect.npeggedSharedOutputEligible && SharedIndirect
                .npeggedSharedOutputEligible);

}

private template Types(T...) {
    alias Types = T;
}

private void compare(alias Parser, bool owned)(string input, size_t steps = size_t.max,
        size_t depth = size_t.max, size_t memory = size_t.max, size_t output = size_t.max, bool tracing = false) @nogc nothrow {
    ParseContext before, after;
    Effects beforeEffects, afterEffects;
    before.userData = &beforeEffects;
    after.userData = &afterEffects;
    before.trace = after.trace = tracing ? &observe : null;
    before.stepLimit = after.stepLimit = steps;
    before.depthLimit = after.depthLimit = depth;
    before.memoryLimit = after.memoryLimit = memory;
    version (NPeggedSharedOutput)
        after.sharedOutput = true;
    version (NPeggedMetrics) {
        ParseMetrics beforeMetrics, afterMetrics;
        before.metrics = &beforeMetrics;
        after.metrics = &afterMetrics;
    }
    auto reference = parseRecords!(Parser, selected, owned)(before, input, output);
    auto candidate = parseRecords!(Parser, selected, owned)(after, input, output);
    assert(reference.status == candidate.status);
    assert(reference.successful == candidate.successful);
    assert(reference.end == candidate.end && reference.failEnd == candidate.failEnd);
    assert(reference.nodes == candidate.nodes);
    assert(beforeEffects.actions == afterEffects.actions);
    assert(beforeEffects.events[0 .. beforeEffects.length] == afterEffects.events[0 .. afterEffects
            .length]);
    version (NPeggedSharedOutput)
        version (NPeggedMetrics) {
            assert(afterMetrics.snapshotBytes == afterMetrics.output.snapshotBytes);
            static if (!__traits(parent, Parser).npeggedSharedOutputEligible)
                assert(afterMetrics.output.sharedSnapshots == 0);
            if (tracing || steps != size_t.max || depth != size_t.max || memory != size_t.max || output != size_t
                    .max)
                assert(afterMetrics.output.sharedSnapshots == 0);
        }
    enum name = __traits(parent, Parser).stringof;
    printf("case %.*s %u %llu %llu %llu %llu %u ", cast(int)name.length, name.ptr, cast(uint)owned,
            cast(ulong)steps, cast(ulong)depth, cast(ulong)memory, cast(ulong)output, cast(uint)tracing);
    foreach (c; input)
        printf("%02x", cast(uint)cast(ubyte)c);
    printf(" %u %u %llu %llu %llu", cast(uint)candidate.status, cast(uint)candidate.successful,
            cast(ulong)candidate.end, cast(ulong)candidate.failEnd, cast(ulong)candidate.nodes.length);
    foreach (node; candidate.nodes)
        printf(" %u:%llu:%llu:%llu", node.kind, cast(ulong)node.begin, cast(ulong)node.end, cast(ulong)node
                .parent);
    printf(" events=%llu", cast(ulong)afterEffects.length);
    foreach (event; afterEffects.events[0 .. afterEffects.length])
        printf(" %u:%.*s:%llu:%u", cast(uint)event.action, cast(int)event.name.length,
                event.name.ptr, cast(ulong)event.position, cast(uint)event.successful);
    if (tracing || steps != size_t.max || depth != size_t.max || memory != size_t.max || output != size_t
            .max)
        printf(" memory=%llu:%llu:%llu:%llu", cast(ulong)candidate.arena.used,
                cast(ulong)candidate.arena.requestedBytes, cast(ulong)candidate.outputArena.used,
                cast(ulong)candidate.outputArena.requestedBytes);
    printf("\n");
    static if (owned)
        assert(reference.input == candidate.input);
}

int main() @nogc nothrow {
    alarm(45);
    static foreach (Parser; Types!(SharedDirect, SharedIndirect, SharedMutual, SharedNullable,
            SharedProbe, SharedReplace)) {
        foreach (input; [
            "", "n", "nn", "nnn", "n+n", "n+n+n", "(n+n)+n", "((n)+n)", "n+", "n+n+", "(n",
            "nab", "nbaba", "\0", "é"
        ]) {
            compare!(Parser.opCall, true)(input);
            compare!(Parser.opCall, false)(input);
            compare!(Parser.opCall, true)(input, size_t.max, size_t.max, size_t.max, size_t.max, true);
            foreach (limit; [0, 1, 4, 16, 64, 1024]) {
                compare!(Parser.opCall, true)(input, cast(size_t)limit);
                compare!(Parser.opCall, true)(input, size_t.max, cast(size_t)limit);
                compare!(Parser.opCall, true)(input, size_t.max, size_t.max, cast(size_t)limit);
                compare!(Parser.opCall, true)(input, size_t.max, size_t.max, size_t.max, cast(size_t)limit);
            }
        }
    }
    char[512] input;
    foreach (i, ref c; input)
        c = i % 2 ? '+' : 'n';
    compare!(SharedDirect.opCall, true)(cast(string)input[0 .. 511]);
    compare!(SharedIndirect.opCall, false)(cast(string)input[0 .. 511]);
    compare!(SharedDirect.opCall, true)(cast(string)input[0 .. 511], size_t.max, size_t.max,
            size_t.max, size_t.max, true);
    char[256] repeated = 'n';
    compare!(SharedNullable.opCall, true)(cast(string)repeated[]);
    compare!(SharedReplace.opCall, true)(cast(string)repeated[]);
    compare!(SharedInsideProbe.opCall, true)(cast(string)repeated[]);
    compare!(SharedLongest.opCall, true)(cast(string)repeated[]);
    compare!(SharedOpaque.opCall, true)(cast(string)repeated[]);
    compare!(SharedAction.opCall, true)(cast(string)repeated[]);
    compare!(SharedAction.opCall, false)(cast(string)repeated[], size_t.max, size_t.max, size_t.max, size_t
            .max, true);
    version (NPeggedSharedOutput)
        version (NPeggedMetrics) {
            ParseContext context;
            ParseMetrics metrics;
            context.metrics = &metrics;
            context.sharedOutput = true;
            context.stepLimit = context.depthLimit = context.memoryLimit = size_t.max;
            auto result = parseRecords!(SharedDirect.opCall, selected)(context, cast(string)input[0 .. 511],
                    size_t.max);
            assert(result.successful);
            version (RootOnly)
                assert(metrics.output.sharedSnapshots == 0);
            else {
                assert(metrics.output.sharedSnapshots > 0);
                assert(metrics.output.sharedReusedNodes > 0 && metrics.output.sharedFrozenNodes > 0);
            }
            assert(metrics.snapshotBytes == metrics.output.snapshotBytes);
            fprintf(stderr, "frozen=%llu reused=%llu snapshots=%llu restore=%llu\n",
                    metrics.snapshotBytes, metrics.output.sharedReusedNodes,
                    metrics.output.sharedSnapshots, metrics.output.restoreBytes);
        }
    char[8] tiny;
    enum alphabet = "n+()";
    foreach (length; 0 .. 5)
        foreach (code; 0 .. (1UL << (length * 2))) {
            auto value = code;
            foreach (i; 0 .. length) {
                tiny[i] = alphabet[value % 4];
                value /= 4;
            }
            compare!(SharedDirect.opCall, false)(cast(string)tiny[0 .. length]);
            compare!(SharedIndirect.opCall, false)(cast(string)tiny[0 .. length]);
            compare!(SharedProbe.opCall, false)(cast(string)tiny[0 .. length]);
        }
    printf("shared output oracle passed\n");
    return 0;
}
