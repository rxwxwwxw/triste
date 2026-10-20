module tests.entry;
import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private uint tag(string name) @nogc nothrow pure {
    return name.length ? 1 : uint.max;
}

private struct Pair(string source, Memoization memo = Memoization.selective) {
    struct ReferenceImpl {
        mixin(grammar!(memo, tag, ParserBackend.combinators)(source));
    }

    struct CandidateImpl {
        mixin(grammar!(memo, tag, ParserBackend.direct)(source));
    }

    alias Reference = ReferenceImpl.Entry;
    alias Candidate = CandidateImpl.Entry;
}

private void compare(alias P)(string input) @nogc nothrow {
    foreach (limit; 0 .. 32)
        foreach (depth; 0 .. 3) {
            ParseContext context;
            context.stepLimit = limit;
            context.depthLimit = depth;
            context.memoryLimit = 0;
            auto a = check!(P.Reference.Root)(context, input);
            auto b = check!(P.Candidate.Root)(context, input);
            assert(a.successful == b.successful && a.status == b.status);
            assert(a.end == b.end && a.failEnd == b.failEnd);
            assert(a.arena.allocationCalls == b.arena.allocationCalls && a.arena.used == b.arena.used);
            auto c = check!(P.Candidate.opCall)(context, input);
            assert(c.successful == b.successful && c.status == b.status && c.end == b.end && c
                    .failEnd == b.failEnd);
        }
    ParseContext context;
    auto a = parseRecords!(P.Reference.Root, tag, false)(context, input);
    auto b = parseRecords!(P.Candidate.Root, tag, false)(context, input);
    assert(a.status == b.status && a.successful == b.successful && a.end == b.end && a.failEnd == b
            .failEnd);
    assert(a.nodes == b.nodes);
    auto ta = parse!(P.Reference.Root)(context, input);
    auto tb = parse!(P.Candidate.Root)(context, input);
    assert(ta.status == tb.status && ta.successful == tb.successful && ta.end == tb.end && ta.failEnd == tb
            .failEnd);
    assert(ta.tree.toString().data == tb.tree.toString().data);
}

@nogc nothrow unittest {
    alias Nullable = Pair!("Entry: Root <- [a-z]* eoi");
    alias Decimal = Pair!("Entry: Root <- [0-9]+ ('.' [0-9]+)? eoi");
    alias Prefix = Pair!("Entry: Root <- 'a'*");
    version (NPeggedLeanEntry)
        static assert(__traits(hasMember, Nullable.Candidate, "npeggedTryCheck"));
    else
        static assert(!__traits(hasMember, Nullable.Candidate, "npeggedTryCheck"));
    foreach (input; [
        "", "a", "abc", "a!", "!", "a\0", "aaaaaaaa", "aaaaaaaaa", "é", "123", "1.", "1.2", "aaab"
    ]) {
        compare!Nullable(input);
        compare!Decimal(input);
        compare!Prefix(input);
    }
}

@nogc nothrow unittest {
    alias Referenced = Pair!("Entry: Root <- Leaf+ eoi Leaf <- [a-z]");
    alias Memoized = Pair!("Entry: Root <- [a-z]* eoi", Memoization.yes);
    alias Literal = Pair!("Entry: Root <- 'a' eoi");
    static assert(!__traits(hasMember, Memoized.Candidate, "npeggedTryCheck"));
    static assert(!__traits(hasMember, Literal.Candidate, "npeggedTryCheck"));
    foreach (input; ["", "a", "ab!", "abc"]) {
        compare!Referenced(input);
        compare!Memoized(input);
        compare!Literal(input);
    }
}

@nogc nothrow unittest {
    alias P = Pair!("Entry: Root <- [a-z]* eoi");
    static void trace(string name, size_t pos, bool success, void* data) @nogc nothrow {
        ++*cast(size_t*)data;
    }

    foreach (input; ["", "a", "abc", "!"])
        foreach (limit; 0 .. 12) {
            size_t ra, rb;
            ParseContext ca, cb;
            ca.stepLimit = cb.stepLimit = limit;
            ca.trace = cb.trace = &trace;
            ca.userData = &ra;
            cb.userData = &rb;
            auto a = check!(P.Reference.Root)(ca, input);
            auto b = check!(P.Candidate.Root)(cb, input);
            assert(a.status == b.status && a.successful == b.successful && a.end == b.end && a
                    .failEnd == b.failEnd);
            assert(ra == rb);
        }
}

int main() @nogc nothrow {
    alarm(60);
    printf("S3 entry parity passed\n");
    return 0;
}
