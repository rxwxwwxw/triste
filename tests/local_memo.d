module tests.local_memo;

import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

uint selected(string name) @nogc nothrow pure {
    return name.length ? 1 : uint.max;
}

struct Event {
    size_t position, steps, depth;
    bool successful;
    string name, input;
}

struct Events {
    Event[1024] data;
    size_t length;
    void put(Event event) @nogc nothrow {
        assert(length < data.length);
        data[length++] = event;
    }
}

private void trace(string name, size_t pos, bool success, void* data) @nogc nothrow {
    (cast(Events*)data).put(Event(pos, 0, 0, success, name));
}

private ParseTree observe(bool CT)(ref State!CT state, ParseTree tree) @nogc nothrow {
    (cast(Events*)state.context.userData).put(Event(tree.end, state.steps, state.depth,
            tree.successful, tree.name, state.input));
    state.context.stepLimit = state.steps + 1;
    return tree;
}

private State!(CT, Check).Node external(bool CT, int Check)(ref State!(CT, Check) state, size_t pos) @nogc nothrow {
    return literal!"!"(state, pos);
}

version (Combinators)
    enum backend = ParserBackend.combinators;
else
    enum backend = ParserBackend.direct;

struct Suite(Memoization memo, bool Actions = false) {
    enum effects = Actions ? `Effect <- Atom{observe} EffectCaller <- Atom Effect Atom` : "";
    mixin(grammar!(memo, selected, backend)(`
LocalMemo:
    Root <- (Pair / Single)* eoi
    Pair <- Atom ':' Atom ';'
    Single <- Atom ';'
    Atom <- 'ab' / 'a' / 'b'
    Long <~ 'a'+
    Overlap <- (&Long Long '!' / Long '?') eoi
    Probe <- (&Atom Atom '!' / Atom '?') eoi
    Recursive <- Recursive '+' Atom / Atom
    IndirectA <- IndirectB '+' Atom / Atom
    IndirectB <- IndirectA
    Cycle <- 'x' Cycle / Atom
    Opaque <- external
    UnknownCaller <- Opaque Atom
` ~ effects));
}

alias Reference = Suite!(Memoization.yes).LocalMemo;
alias Candidate = Suite!(Memoization.selective).LocalMemo;
alias ActionReference = Suite!(Memoization.yes, true).LocalMemo;
alias ActionCandidate = Suite!(Memoization.selective, true).LocalMemo;

version (NPeggedLocalMemo) {
    static assert(__traits(hasMember, Candidate, "npeggedLocalMemoRules"));
    static assert(!__traits(hasMember, Reference, "npeggedLocalMemoRules"));
    static assert(Candidate.npeggedLocalMemoRules == ["Pair", "Single", "Atom", "Probe"]);
}

private bool sameTree(scope const ref ParseTree a, scope const ref ParseTree b) @nogc nothrow {
    if (a.name != b.name || a.begin != b.begin || a.end != b.end || a.failEnd != b.failEnd
            || a.successful != b.successful || a.input != b.input || a.matches != b.matches
            || a.children.length != b.children.length || a.failedChild.length != b.failedChild.length)
        return false;
    foreach (i; 0 .. a.children.length)
        if (!sameTree(a.children[i], b.children[i]))
            return false;
    foreach (i; 0 .. a.failedChild.length)
        if (!sameTree(a.failedChild[i], b.failedChild[i]))
            return false;
    return true;
}

private void compare(alias A, alias B)(string input, ParseContext context, size_t outputLimit = size_t
        .max) @nogc nothrow {
    static foreach (mode; 0 .. 4) {
        {
            Events first, second;
            ParseMetrics am, bm;
            context.userData = &first;
            context.metrics = &am;
            static if (mode == 0)
                auto a = check!A(context, input);
            else static if (mode == 3)
                auto a = parse!A(context, input);
            else
                auto a = parseRecords!(A, selected, mode == 2)(context, input, outputLimit);
            context.userData = &second;
            context.metrics = &bm;
            static if (mode == 0)
                auto b = check!B(context, input);
            else static if (mode == 3)
                auto b = parse!B(context, input);
            else
                auto b = parseRecords!(B, selected, mode == 2)(context, input, outputLimit);
            assert(a.status == b.status);
            static if (mode == 3)
                assert(sameTree(a.tree, b.tree));
            else {
                assert(a.successful == b.successful && a.end == b.end && a.failEnd == b.failEnd);
                static if (mode != 0)
                    assert(a.nodes == b.nodes);
            }
            assert(first.data[0 .. first.length] == second.data[0 .. second.length]);
            bool inactive = mode == 3 || context.trace !is null || context.stepLimit != size_t.max
                || context.depthLimit != size_t.max || context.memoryLimit != size_t.max;
            static if (mode == 1 || mode == 2)
                inactive = inactive || outputLimit != size_t.max;
            if (inactive) {
                assert(a.arena.used == b.arena.used && a.arena.requestedBytes == b.arena
                        .requestedBytes);
                assert(am.memoCalls == bm.memoCalls && am.memoHits == bm.memoHits);
            }
            printf("%.*s %u %u %llu\n", cast(int)__traits(identifier, B).length,
                    __traits(identifier, B).ptr, cast(uint)mode, cast(uint)b.status, cast(ulong)input
                        .length);
        }
    }
}

version (LocalMemoBenchmark) {
} else
    int main() @nogc nothrow {
    alarm(45);
    ParseContext context;
    context.stepLimit = context.depthLimit = context.memoryLimit = size_t.max;
    foreach (input; [
        "", "a;", "a:b;", "a;ab:b;a;", "a", "ab!", "a?", "aaaa?", "a+a+a", "xxa", "!a", "aaa", "\0",
        "é"
    ]) {
        static foreach (entry; [
            "opCall", "Root", "Atom", "Pair", "Single", "Long", "Overlap", "Probe", "Recursive",
            "IndirectA", "Cycle", "Opaque", "UnknownCaller"
        ]) {
            {
                compare!(__traits(getMember, Reference, entry), __traits(getMember, Candidate, entry))(
                        input, context);
                auto traced = context;
                traced.trace = &trace;
                compare!(__traits(getMember, Reference, entry), __traits(getMember, Candidate, entry))(
                        input, traced);
            }
        }
        foreach (limit; [0, 1, 4, 16, 64, 1024]) {
            auto limited = context;
            limited.stepLimit = limit;
            compare!(Reference.Root, Candidate.Root)(input, limited);
            limited = context;
            limited.depthLimit = limit;
            compare!(Reference.Root, Candidate.Root)(input, limited);
            limited = context;
            limited.memoryLimit = limit;
            compare!(Reference.Root, Candidate.Root)(input, limited);
            compare!(Reference.Root, Candidate.Root)(input, context, limit);
        }
        compare!(and!(Candidate.Atom, ActionReference.Effect, Candidate.Atom),
                and!(Candidate.Atom, ActionCandidate.Effect, Candidate.Atom))(input, context);
        compare!(ActionReference.EffectCaller, ActionCandidate.EffectCaller)(input, context);
        compare!(ActionReference.Root, ActionCandidate.Root)(input, context);
    }
    version (NPeggedLocalMemo) {
        ParseMetrics before, after;
        context.metrics = &before;
        auto a = check!(Reference.Root)(context, "a;b;a:b;");
        context.metrics = &after;
        auto b = check!(Candidate.Root)(context, "a;b;a:b;");
        assert(a.successful && b.successful);
        assert(after.memoCalls < before.memoCalls);
        assert(b.arena.requestedBytes < a.arena.requestedBytes);
    }
    printf("local memo oracle passed\n");
    return 0;
}
