module tests.differential;
import npegged.grammar;
import core.stdc.stdio : fprintf, stderr;
import core.stdc.stdlib : abort;

private uint selected(string name) @nogc nothrow pure {
    return name.length ? 1 : uint.max;
}

private struct Pair(string rules, Memoization policy) {
    struct Reference {
        mixin(grammar!(policy, selected)(rules));
    }

    struct Candidate {
        mixin(grammar!(policy, selected, ParserBackend.direct)(rules));
    }
}

private struct Event {
    string name;
    size_t position;
    bool successful;
}

private struct Events {
    Event[4096] values;
    size_t length;
    static void observe(string name, size_t position, bool successful, void* user) @nogc nothrow {
        auto self = cast(Events*)user;
        assert(self.length < self.values.length);
        self.values[self.length++] = Event(name, position, successful);
    }
}

private string treeDifference(ref const ParseTree a, ref const ParseTree b) @nogc nothrow {
    static foreach (field; ["name", "successful", "matches", "input", "begin", "end", "failEnd"])
        if (__traits(getMember, a, field) != __traits(getMember, b, field))
            return "tree." ~ field;
    if (a.children.length != b.children.length)
        return "tree.children.length";
    if (a.failedChild.length != b.failedChild.length)
        return "tree.failedChild.length";
    foreach (i; 0 .. a.children.length) {
        auto difference = treeDifference(a.children[i], b.children[i]);
        if (difference.length)
            return difference;
    }
    foreach (i; 0 .. a.failedChild.length) {
        auto difference = treeDifference(a.failedChild[i], b.failedChild[i]);
        if (difference.length)
            return difference;
    }
    return "";
}

@nogc nothrow unittest {
    ParseTree a, b;
    assert(treeDifference(a, b) == "");
    b.end = 1;
    assert(treeDifference(a, b) == "tree.end");
    ParseTree[1] childA, childB;
    a.children = childA[];
    b = a;
    b.children = childB[];
    childB[0].failEnd = 1;
    assert(treeDifference(a, b) == "tree.failEnd");
    a.children = b.children = null;
    a.failedChild = childA[];
    b.failedChild = childB[];
    assert(treeDifference(a, b) == "tree.failEnd");
}

private void require(bool condition, string grammarName, string input, string mode,
        ref ParseContext context, size_t outputLimit, string field = "") @nogc nothrow {
    if (condition)
        return;
    fprintf(stderr, "differential mismatch grammar=%.*s mode=%.*s field=%.*s steps=%llu depth=%llu memory=%llu output=%llu input(hex)=",
            cast(int)grammarName.length, grammarName.ptr, cast(int)mode.length, mode.ptr,
            cast(int)field.length, field.ptr, cast(ulong)context.stepLimit,
            cast(ulong)context.depthLimit, cast(ulong)context.memoryLimit, cast(ulong)outputLimit);
    foreach (c; input)
        fprintf(stderr, "%02x", cast(uint)cast(ubyte)c);
    fprintf(stderr, "\n");
    abort();
}

private ParseTree observeAction(bool CT)(ref State!CT state, ParseTree tree) @nogc nothrow {
    Events.observe(tree.name, tree.end, tree.successful, state.context.userData);
    return tree;
}

private void assertSameParse(alias Reference, alias Candidate)(string input,
        ParseContext context = ParseContext.init, size_t outputLimit = 256 * 1024 * 1024) @nogc nothrow {
    enum name = __traits(parent, __traits(parent, __traits(parent, Reference))).stringof;
    static foreach (tracing; [false, true]) {
        {
            static foreach (mode; ["recognition", "borrowed records", "owned records", "full tree"]) {
                {
                    Events eventsA, eventsB;
                    context.trace = tracing ? &Events.observe : null;
                    context.userData = &eventsA;
                    static if (mode == "recognition")
                        auto a = check!Reference(context, input);
                    else static if (mode == "full tree")
                        auto a = parse!Reference(context, input);
                    else
                        auto a = parseRecords!(Reference, selected, mode == "owned records")(
                                context, input, outputLimit);
                    context.userData = &eventsB;
                    static if (mode == "recognition")
                        auto b = check!Candidate(context, input);
                    else static if (mode == "full tree")
                        auto b = parse!Candidate(context, input);
                    else
                        auto b = parseRecords!(Candidate, selected, mode == "owned records")(
                                context, input, outputLimit);
                    static foreach (field; ["status", "successful", "end", "failEnd"])
                        require(__traits(getMember, a, field) == __traits(getMember, b, field),
                                name, input, mode, context, outputLimit, field);
                    static if (mode == "full tree") {
                        auto difference = treeDifference(a.tree, b.tree);
                        require(!difference.length, name, input, mode, context, outputLimit, difference);
                    } else static if (mode != "recognition") {
                        require(a.nodes == b.nodes, name, input, mode, context, outputLimit, "nodes");
                        require(a.input == b.input, name, input, mode, context, outputLimit, "input");
                    }
                    require(
                            eventsA.values[0 .. eventsA.length] == eventsB.values[0 .. eventsB.length],
                            name, input, mode ~ ": actions/trace sequence", context, outputLimit);
                }
            }
        }
    }
}

private enum control = `Fixture:
    Root <- (!'z' Item)* eoi
    Item <- '(' [ab]* ')' / 'ab' / 'a' 'b'? / 'b' / '\x00' / 'é' / '\x80'
`;
private enum left = `Fixture:
    Root <- Expr eoi
    Expr <- Expr '+' Number / Number
    Number <- [0-9]+
`;
private enum indirect = `Fixture:
    Root <- Expr eoi
    Expr <- Sum / Number
    Sum <- Expr '+' Number
    Number <- [0-9]+
`;
private enum actions = `Fixture:
    Root <- (&('a'{observeAction}) Item / Item) eoi
    Item <- ('a'{observeAction})+ / 'b'{observeAction}
`;

private enum nullable = `Fixture:
    Root <- Expr eoi
    Expr <- Expr 'a' / 'b'?
`;

int main() @nogc nothrow {
    static foreach (policy; [Memoization.yes, Memoization.selective]) {
        {
            alias P = Pair!(control, policy);
            enum ctA = P.Reference.Fixture("ab");
            enum ctB = P.Candidate.Fixture("ab");
            static assert(ctA == ctB);
            char[4] bytes;
            foreach (length; 0 .. 5)
                foreach (bits; 0 .. (1 << length)) {
                    foreach (i; 0 .. length)
                        bytes[i] = bits & (1 << i) ? 'a' : 'b';
                    assertSameParse!(P.Reference.Fixture.opCall, P.Candidate.Fixture.opCall)(
                            cast(string)bytes[0 .. length]);
                }
            static foreach (rules; [control, left, indirect, nullable, actions]) {
                {
                    alias Q = Pair!(rules, policy);
                    foreach (input; [
                        "", "a", "ab", "aba", "(ab)", "(ab", "z", "\x00", "é", "\x80", "1",
                        "1+2+3", "1+", "1+x", "aaab", "aaaa"
                    ]) {
                        assertSameParse!(Q.Reference.Fixture.opCall, Q.Candidate.Fixture.opCall)(input);
                        foreach (limit; [0, 1, 4, 16, 64]) {
                            ParseContext context;
                            context.stepLimit = limit;
                            assertSameParse!(Q.Reference.Fixture.opCall, Q.Candidate.Fixture.opCall)(
                                    input, context);
                            context = ParseContext.init;
                            context.depthLimit = limit;
                            assertSameParse!(Q.Reference.Fixture.opCall, Q.Candidate.Fixture.opCall)(
                                    input, context);
                            context = ParseContext.init;
                            context.memoryLimit = limit;
                            assertSameParse!(Q.Reference.Fixture.opCall, Q.Candidate.Fixture.opCall)(
                                    input, context);
                            context = ParseContext.init;
                            assertSameParse!(Q.Reference.Fixture.opCall, Q.Candidate.Fixture.opCall)(
                                    input, context, limit);
                        }
                    }
                }
            }
        }
    }
    char[255] longInput;
    foreach (i, ref c; longInput)
        c = i % 2 ? '+' : '1';
    alias Long = Pair!(indirect, Memoization.selective);
    assertSameParse!(Long.Reference.Fixture.opCall, Long.Candidate.Fixture.opCall)(cast(string)longInput[]);
    return 0;
}
