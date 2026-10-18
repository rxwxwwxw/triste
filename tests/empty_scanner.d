module tests.empty_scanner;
import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

uint selected(string name) @nogc nothrow pure {
    return name.length ? 1 : uint.max;
}

enum source = `EmptySP:
    Root <- Sp 'x' eoi
    Sp <: [ \t\r\n]* ('#' (!'\n' .)* [ \t\r\n]*)*
`;
struct Suite(ParserBackend backend) {
    mixin(grammar!(Memoization.selective, selected, backend)(source));
}

alias Reference = Suite!(ParserBackend.combinators).EmptySP;
alias Candidate = Suite!(ParserBackend.direct).EmptySP;
private bool contains(string text, string needle) @nogc nothrow pure {
    foreach (i; 0 .. text.length)
        if (text.length - i >= needle.length && text[i .. i + needle.length] == needle)
            return true;
    return false;
}

enum generated = grammar!(Memoization.selective, selected, ParserBackend.direct)(source);
static assert(contains(generated, "_empty_Sp_p3_1_byte"));
static assert(contains(generated, "_empty_Sp_p3_2_byte"));
private bool sameTree(scope const ref ParseTree a, scope const ref ParseTree b) @nogc nothrow {
    if (a.name != b.name || a.input != b.input || a.begin != b.begin || a.end != b.end
            || a.failEnd != b.failEnd || a.successful != b.successful || a.matches != b.matches
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

private struct TraceEvent {
    string name;
    size_t position;
    bool successful;
}

private TraceEvent[2048] traceEvents;
private size_t traceLength;
private void trace(string name, size_t position, bool successful, void*) @nogc nothrow {
    assert(traceLength < traceEvents.length);
    traceEvents[traceLength++] = TraceEvent(name, position, successful);
}

private void compare(alias A, alias B)(string input, ParseContext context, size_t outputLimit = size_t
        .max) @nogc nothrow {
    static foreach (mode; 0 .. 4) {
        {
            traceLength = 0;
            static if (mode == 0)
                auto a = check!A(context, input);
            else static if (mode == 3)
                auto a = parse!A(context, input);
            else
                auto a = parseRecords!(A, selected, mode == 2)(context, input, outputLimit);
            auto before = traceLength;
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
            assert(traceLength == before * 2);
            assert(traceEvents[0 .. before] == traceEvents[before .. traceLength]);
            assert(a.arena.used == b.arena.used && a.arena.requestedBytes == b.arena.requestedBytes);
            printf("%u,%u,%llu\n", cast(uint)mode, cast(uint)b.status, cast(ulong)input.length);
        }
    }
}

int main() @nogc nothrow {
    alarm(45);
    ParseContext context;
    char[2] bytes;
    foreach (first; 0 .. 256) {
        bytes[0] = cast(char)first;
        foreach (second; ['x', ' ', '#', '\n', '\0']) {
            bytes[1] = second;
            foreach (length; 0 .. 3) {
                compare!(Reference.Sp, Candidate.Sp)(cast(string)bytes[0 .. length], context);
                compare!(Reference.Root, Candidate.Root)(cast(string)bytes[0 .. length], context);
            }
        }
    }
    foreach (input; ["", "x", " ", "#", "#comment\n", " \t#one\n#two\n x", "é", "\0"]) {
        foreach (limit; 0 .. 129) {
            auto limited = context;
            limited.stepLimit = limit;
            compare!(Reference.Sp, Candidate.Sp)(input, limited);
            compare!(Reference.Root, Candidate.Root)(input, limited);
        }
        foreach (limit; [0, 1, 2, 4, 16, 64, 256]) {
            auto limited = context;
            limited.depthLimit = limit;
            compare!(Reference.Sp, Candidate.Sp)(input, limited);
            limited = context;
            limited.memoryLimit = limit;
            compare!(Reference.Sp, Candidate.Sp)(input, limited);
            compare!(Reference.Sp, Candidate.Sp)(input, context, limit);
        }
        auto traced = context;
        traced.trace = &trace;
        compare!(Reference.Root, Candidate.Root)(input, traced);
    }
    printf("empty scanner oracle passed\n");
    return 0;
}
