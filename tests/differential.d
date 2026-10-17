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

private bool sameTree(ref const ParseTree a, ref const ParseTree b) @nogc nothrow {
    if (a.name != b.name || a.successful != b.successful || a.matches != b.matches
            || a.input != b.input || a.begin != b.begin || a.end != b.end || a.failEnd != b.failEnd
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

private void require(bool condition, string grammarName, string input, string mode,
        ref ParseContext context, size_t outputLimit) @nogc nothrow {
    if (condition)
        return;
    fprintf(stderr, "differential mismatch grammar=%.*s mode=%.*s steps=%llu depth=%llu memory=%llu output=%llu input(hex)=",
            cast(int)grammarName.length, grammarName.ptr, cast(int)mode.length, mode.ptr,
            cast(ulong)context.stepLimit, cast(ulong)context.depthLimit,
            cast(ulong)context.memoryLimit, cast(ulong)outputLimit);
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
    enum name = __traits(parent, Reference).stringof;
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
                    require(a.status == b.status && a.successful == b.successful && a.end == b.end
                            && a.failEnd == b.failEnd, name, input,
                            mode ~ ": status/success/end/failEnd", context, outputLimit);
                    static if (mode == "full tree")
                        require(sameTree(a.tree, b.tree), name, input, mode ~ ": fields", context, outputLimit);
                    else static if (mode != "recognition")
                        require(a.nodes == b.nodes && a.input == b.input, name, input,
                                mode ~ ": nodes/input", context, outputLimit);
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
