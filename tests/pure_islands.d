module tests.pure_islands;
import npegged.grammar;
import core.stdc.stdio : printf, fprintf, stderr;
import core.sys.posix.unistd : alarm;

version (NPeggedFullMemo)
    enum memo = Memoization.yes;
else version (NoMemo)
    enum memo = Memoization.no;
else
    enum memo = Memoization.selective;
uint selected(string name) @nogc nothrow pure {
    version (StageProjection)
        return name.length ? (__ctfe ? 1 : 2) : uint.max;
    version (RootOnly)
        return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : uint.max;
    else version (LeafOnly)
        return name.length >= 11 && name[$ - 11 .. $] == ".Identifier" ? 1 : uint.max;
    else version (AnonymousSelected)
        return 1;
    else
        return name.length ? 1 : uint.max;
}

version (LegacyProjection)
    alias compiledSelector = void;
else
    alias compiledSelector = selected;
alias runtimeSelector = selected;

struct Event {
    string name, input;
    size_t position, steps, depth;
    bool action, successful;
    string[] matches;
}

struct Effects {
    Event[8192] events;
    size_t length;
    void add(Event event) @nogc nothrow {
        assert(length < events.length);
        events[length++] = event;
    }
}

private void trace(string name, size_t position, bool successful, void* data) @nogc nothrow {
    (cast(Effects*)data).add(Event(name, null, position, 0, 0, false, successful));
}

private ParseTree observe(bool CT)(ref State!CT state, ParseTree tree) @nogc nothrow {
    if (state.context.userData !is null)
        (cast(Effects*)state.context.userData).add(Event(tree.name, state.input, tree.end,
                state.steps, state.depth, true, tree.successful, tree.matches));
    if (tree.matches.length && tree.matches[0] == "reject")
        tree.successful = false;
    if (tree.matches.length && tree.matches[0] == "swap")
        state.input = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"[0 .. state.input.length];
    if (tree.matches.length && tree.matches[0] == "limit")
        state.context.stepLimit = state.steps + 1;
    return tree;
}

private State!(CT, Check).Node opaque(bool CT, int Check)(ref State!(CT, Check) state, size_t pos) @nogc nothrow {
    return literal!("!")(state, pos);
}

struct Suite(ParserBackend backend) {
    mixin(grammar!(memo, compiledSelector, backend)(`
Islands:
    Root <- (Identifier Whitespace)* eoi
    Identifier <~ [a-z]+
    Whitespace <: [ ]*
    ActRoot <- (Action Whitespace)* eoi
    Action <- Identifier{observe}
    OpaqueRoot <- Identifier opaque eoi
    Left <- (Left '+' Identifier / Identifier){observe}
    Cycle <- '(' Cycle ')' / Identifier
    Kept <- ^Identifier eoi
    Fused <~ Identifier ':' Identifier
    Look <- &Identifier Identifier !'z' eoi
`));
}

alias Reference = Suite!(ParserBackend.combinators).Islands;
alias Candidate = Suite!(ParserBackend.direct).Islands;
version (NPeggedPureIslands) {
    static assert(__traits(hasMember, Candidate, "npeggedPureIslandEntries"));
    static assert(!__traits(hasMember, Reference, "npeggedPureIslandEntries"));
    static assert(Candidate.npeggedPureIslandEntries == [
        "Root", "Identifier", "Whitespace", "Kept", "Fused", "Look", "opCall"
    ]);
}

private bool sameTree(scope const ref ParseTree a, scope const ref ParseTree b) @nogc nothrow {
    static foreach (field; ["name", "successful", "matches", "input", "begin", "end", "failEnd"])
        if (__traits(getMember, a, field) != __traits(getMember, b, field))
            return false;
    if (a.children.length != b.children.length || a.failedChild.length != b.failedChild.length)
        return false;
    foreach (i; 0 .. a.children.length)
        if (!sameTree(a.children[i], b.children[i]))
            return false;
    foreach (i; 0 .. a.failedChild.length)
        if (!sameTree(a.failedChild[i], b.failedChild[i]))
            return false;
    return true;
}

private void compare(alias A, alias B)(string input, ParseContext context,
        size_t outputLimit = size_t.max, bool tracing = false) @nogc nothrow {
    static foreach (mode; [0, 1, 2, 3]) {
        {
            Effects first, second;
            context.trace = tracing ? &trace : null;
            context.userData = &first;
            version (NPeggedMetrics) {
                ParseMetrics referenceMetrics, candidateMetrics;
                context.metrics = &referenceMetrics;
            }
            static if (mode == 0)
                auto a = check!A(context, input);
            else static if (mode == 3)
                auto a = parse!A(context, input);
            else
                auto a = parseRecords!(A, runtimeSelector, mode == 2)(context, input, outputLimit);
            context.userData = &second;
            version (NPeggedMetrics)
                context.metrics = &candidateMetrics;
            static if (mode == 0)
                auto b = check!B(context, input);
            else static if (mode == 3)
                auto b = parse!B(context, input);
            else
                auto b = parseRecords!(B, runtimeSelector, mode == 2)(context, input, outputLimit);
            static foreach (field; ["status", "successful", "end", "failEnd"])
                assert(__traits(getMember, a, field) == __traits(getMember, b, field));
            static if (mode == 3)
                assert(sameTree(a.tree, b.tree));
            else static if (mode != 0)
                assert(a.nodes == b.nodes);
            assert(first.events[0 .. first.length] == second.events[0 .. second.length]);
            const inactive = tracing || context.memoryLimit != size_t.max
                || context.depthLimit != size_t.max || context.stepLimit != size_t.max || ((mode == 1
                        || mode == 2) && outputLimit != size_t.max) || mode == 3;
            if (inactive)
                assert(a.arena.used == b.arena.used && a.arena.requestedBytes == b.arena
                        .requestedBytes);
            static if (mode == 1 || mode == 2)
                if (inactive)
                    assert(a.outputArena.used == b.outputArena.used
                            && a.outputArena.requestedBytes == b.outputArena.requestedBytes);
            printf("case %.*s %u %u %llu %llu %llu events=%llu", cast(int)__traits(identifier, B)
                    .length, __traits(identifier, B).ptr, cast(uint)mode, cast(uint)b.status,
                    cast(ulong)b.end, cast(ulong)b.failEnd, cast(ulong)input.length, cast(ulong)second
                        .length);
            static if (mode != 0 && mode != 3)
                foreach (node; b.nodes)
                    printf(" %u:%llu:%llu:%llu", node.kind, cast(ulong)node.begin,
                            cast(ulong)node.end, cast(ulong)node.parent);
            if (inactive)
                printf(" memory=%llu:%llu", cast(ulong)b.arena.used, cast(ulong)b.arena
                        .requestedBytes);
            printf("\n");
        }
    }
}

version (PureIslandsBenchmark) {
} else {
    int main() @nogc nothrow {
        alarm(45);
        ParseContext unlimited;
        unlimited.memoryLimit = unlimited.stepLimit = unlimited.depthLimit = size_t.max;
        foreach (input; [
            "", "a", "abc def", "abc def xyz", "abc reject xyz", "abc swap zz", "abc limit zz",
            "a ", "abc!", "reject", "swap a", "limit a", "a+b", "(a)", "a:b", "\0", "é"
        ]) {
            static foreach (entry; [
                "opCall", "Root", "Identifier", "Whitespace", "ActRoot", "Action", "OpaqueRoot",
                "Left", "Cycle", "Kept", "Fused", "Look"
            ]) {
                static if (memo != Memoization.no || entry != "Left") {
                    compare!(__traits(getMember, Reference, entry), __traits(getMember, Candidate, entry))(
                            input, unlimited);
                    compare!(__traits(getMember, Reference, entry), __traits(getMember, Candidate, entry))(
                            input, unlimited, size_t.max, true);
                }
            }
            foreach (limit; [0, 1, 4, 16, 64, 1024]) {
                auto context = unlimited;
                context.stepLimit = limit;
                compare!(Reference.opCall, Candidate.opCall)(input, context);
                context = unlimited;
                context.memoryLimit = limit;
                compare!(Reference.opCall, Candidate.opCall)(input, context);
                context = unlimited;
                context.depthLimit = limit;
                compare!(Reference.opCall, Candidate.opCall)(input, context);
                compare!(Reference.opCall, Candidate.opCall)(input, unlimited, limit);
            }
            compare!(and!(Reference.Identifier, Reference.Whitespace, Reference.Action,
                    Reference.Whitespace, Reference.Identifier, eoi), and!(Candidate.Identifier,
                    Candidate.Whitespace,
                    Candidate.Action, Candidate.Whitespace, Candidate.Identifier, eoi))(input, unlimited);
        }
        version (NPeggedPureIslands)
            version (NPeggedMetrics) {
                ParseMetrics metrics;
                unlimited.metrics = &metrics;
                auto result = check!(Candidate.Identifier)(unlimited, "abc");
                assert(result.successful && metrics.pureIslandEntries > 0);
                metrics = ParseMetrics.init;
                auto records = parseRecords!(Candidate.Identifier, runtimeSelector)(unlimited, "abc", size_t
                        .max);
                assert(records.successful);
                version (AnonymousSelected)
                    assert(metrics.pureIslandEntries == 0);
                else version (LegacyProjection)
                    assert(metrics.pureIslandEntries == 0);
                else version (StageProjection)
                    assert(metrics.pureIslandEntries == 0);
                else
                    assert(metrics.pureIslandEntries > 0);
                fprintf(stderr, "active=%llu fallback=%llu\n", metrics.pureIslandEntries, metrics
                        .pureIslandFallbacks);
            }
        printf("pure islands oracle passed\n");
        return 0;
    }
}
