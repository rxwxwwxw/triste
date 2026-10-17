/** Run through scripts/memo-dependencies.py: bounded diagnostic regression corpus. */
module tests.memo_dependency;
import npegged.grammar;
import core.stdc.stdio : printf;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
version (NPeggedSelectiveMemo)
    private enum memo = Memoization.selective;
else
    private enum memo = Memoization.yes;
mixin(grammar!(memo, void, backend)(`TraceDirect:
    Root <- Expr eoi
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));
mixin(grammar!(memo, void, backend)(`TraceIndirect:
    Root <- Expr eoi
    Expr <- Sum / Number
    Sum <- Expr '+' Number
    Number <- ~[0-9]+
`));
mixin(grammar!(memo, void, backend)(`TraceMutual:
    Root <- A eoi
    A <- B 'a' / 'a'
    B <- A 'b' / 'a'
`));
mixin(grammar!(memo, void, backend)(`TraceNullable:
    Root <- A eoi
    A <- A 'a' / eps
`));
mixin(grammar!(memo, void, backend)(`TraceNested:
    Root <- Expr eoi
    Expr <- Expr '+' Atom / Atom
    Atom <- '(' Expr ')' / 'n'
`));
mixin(grammar!(memo, void, backend)(`TraceOverlap:
    Root <- (A 'x' / A 'y') eoi
    A <- A 'a' / 'a'
`));
mixin(grammar!(memo, void, backend)(`TraceCached:
    Root <- H eoi
    H <- B / 'a'
    B <- &C D
    D <- C 'a'
    C <- H
`));

mixin(grammar!(memo, void, backend)(`TraceHeads:
    Root <- A eoi
    A <- A 'a' / B
    B <- B 'b' / 'b'
`));

private void verify(alias Parser)(string input, MemoTraceEvent[] first, MemoTraceEvent[] second) @nogc nothrow {
    ParseContext context;
    auto reference = check!(Parser.opCall)(context, input);
    assert(reference.status == Status.ok || reference.status == Status.mismatch);
    MemoTrace trace = MemoTrace(first);
    context.memoTrace = &trace;
    auto actual = check!(Parser.opCall)(context, input);
    assert(reference.status == actual.status && reference.successful == actual.successful
            && reference.end == actual.end && reference.failEnd == actual.failEnd);
    assert(!trace.truncated);
    MemoTrace repeated = MemoTrace(second);
    context.memoTrace = &repeated;
    auto again = check!(Parser.opCall)(context, input);
    assert(again.status == actual.status && trace.events == repeated.events);
    foreach (limit; [0, 1, 4, 16, 64]) {
        ParseContext plain;
        plain.stepLimit = limit;
        auto a = check!(Parser.opCall)(plain, input);
        MemoTrace shortTrace = MemoTrace(first[0 .. 1]);
        plain.memoTrace = &shortTrace;
        auto b = check!(Parser.opCall)(plain, input);
        assert(a.status == b.status && a.successful == b.successful && a.end == b.end && a.failEnd == b
                .failEnd);
    }
    // Repeat after the short-buffer tests overwrote first storage.
    MemoTrace emitted = MemoTrace(first);
    context.memoTrace = &emitted;
    auto result = check!(Parser.opCall)(context, input);
    assert(!emitted.truncated && result.status == reference.status);
    foreach (i, event; emitted.events)
        printf("%s,%.*s,%zu,%u,%zu,%zu,%zu,%zu,%u,%.*s\n", (Parser.stringof ~ "\0").ptr,
                cast(int)input.length, input.ptr, i, cast(uint)event.kind, event.caller,
                event.entry, event.position, event.end, cast(uint)event.successful,
                cast(int)event.rule.length, event.rule.ptr);
    printf("%s,%.*s,%zu,7,0,0,0,%zu,%u,\n", (Parser.stringof ~ "\0").ptr, cast(int)input.length,
            input.ptr, emitted.events.length, result.end, cast(uint)result.successful);
}

int main() @nogc nothrow {
    MemoTraceEvent[8192] first, second;
    printf("grammar,input,sequence,kind,caller,entry,position,end,successful,rule\n");
    static foreach (Parser; AliasSeq!(TraceDirect, TraceIndirect, TraceMutual, TraceNullable,
            TraceNested, TraceOverlap, TraceCached, TraceHeads)) {
        foreach (input; [
            "", "a", "aaa", "aaay", "aaba", "1", "1+2+3", "1+", "n", "n+n", "(n+n)+(n+(n+n))",
            "(((n)))", "bbb", "bbbaa"
        ])
            verify!Parser(input, first[], second[]);
    }
    ParseContext context;
    auto cached = check!(TraceCached.opCall)(context, "aaa");
    assert(cached.successful && cached.end == 3);
    return 0;
}

private template AliasSeq(T...) {
    alias AliasSeq = T;
}
