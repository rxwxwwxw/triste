/** R03 policy on/off oracle. Default builds exercise the retained reference path. */
module tests.narrow_invalidation;
import npegged.grammar;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
mixin(grammar!(Memoization.selective, void, backend)(`NarrowNested:
    Root <- Expr eoi
    Expr <- Expr '+' Atom / Atom
    Atom <- '(' Expr ')' / 'n'
`));
mixin(grammar!(Memoization.selective, void, backend)(`NarrowIndirect:
    Root <- A eoi
    A <- B / 'a'
    B <- A 'a'
`));
mixin(grammar!(Memoization.selective, void, backend)(`NarrowMutual:
    Root <- A eoi
    A <- B 'a' / 'a'
    B <- A 'b' / 'a'
`));
mixin(grammar!(Memoization.selective, void, backend)(`NarrowNullable:
    Root <- A eoi
    A <- A 'a' / eps
`));
mixin(grammar!(Memoization.selective, void, backend)(`NarrowCached:
    Root <- H eoi
    H <- B / 'a'
    B <- &C D
    D <- C 'a'
    C <- H
`));
private State!(CT, Check).Node opaque(bool CT, int Check)(ref State!(CT, Check) state, size_t pos) nothrow {
    return literal!"n"(state, pos);
}

mixin(grammar!(Memoization.selective, void, backend)(`NarrowOpaque:
    Root <- A eoi
    A <- A 'n' / opaque
`));
private struct Effects {
    size_t actions, callbacks;
}

private ParseTree effect(bool CT)(ref State!CT state, ParseTree tree) nothrow {
    ++(cast(Effects*)state.context.userData).actions;
    return tree;
}

mixin(grammar!(Memoization.selective, void, backend)(`NarrowAction:
    Root <- A eoi
    A <- (A 'a' / 'a'){effect}
`));
private void observe(string name, size_t position, bool accepted, void* user) @nogc nothrow {
    ++(cast(Effects*)user).callbacks;
}

private bool same(alias Parser)(string input, ParseContext context) @nogc nothrow {
    Effects first, second;
    context.userData = &first;
    version (NPeggedNarrowInvalidation)
        context.narrowInvalidation = false;
    auto a = check!(Parser.opCall)(context, input);
    context.userData = &second;
    version (NPeggedNarrowInvalidation)
        context.narrowInvalidation = true;
    auto b = check!(Parser.opCall)(context, input);
    return a.status == b.status && a.successful == b.successful && a.end == b.end
        && a.failEnd == b.failEnd && first.actions == second.actions && first.callbacks == second
            .callbacks;
}

int main() @nogc nothrow {
    ParseContext maximum;
    maximum.stepLimit = maximum.depthLimit = maximum.memoryLimit = size_t.max;
    static foreach (Parser; AliasSeq!(NarrowNested, NarrowIndirect, NarrowMutual, NarrowNullable,
            NarrowCached, NarrowOpaque, NarrowAction)) {
        foreach (input; [
            "", "n", "n+n", "(n)", "((n+n))", "(n+n)+(n+(n+n))", "(n+n)+", "()", "n+(", "\0n",
            "é", "\x80", "aaa", "bbbaa"
        ]) {
            if (!same!Parser(input, maximum))
                return 1;
            foreach (limit; [0, 1, 4, 16, 64, 1024, 4096]) {
                auto context = maximum;
                context.stepLimit = limit;
                if (!same!Parser(input, context))
                    return 2;
                context = maximum;
                context.depthLimit = limit;
                if (!same!Parser(input, context))
                    return 3;
                context = maximum;
                context.memoryLimit = limit;
                if (!same!Parser(input, context))
                    return 4;
            }
            auto traced = maximum;
            traced.trace = &observe;
            if (!same!Parser(input, traced))
                return 5;
        }
    }
    char[4] bytes;
    enum alphabet = "n+()";
    size_t combinations = 1;
    foreach (length; 0 .. 5) {
        foreach (encoded; 0 .. combinations) {
            auto value = encoded;
            foreach (ref c; bytes[0 .. length]) {
                c = alphabet[value % 4];
                value /= 4;
            }
            if (!same!NarrowNested(cast(string)bytes[0 .. length], maximum))
                return 6;
        }
        combinations *= 4;
    }
    version (NPeggedMetrics)
        version (NPeggedNarrowInvalidation) {
            ParseMetrics metrics;
            maximum.metrics = &metrics;
            maximum.narrowInvalidation = true;
            auto positive = check!(NarrowNested.opCall)(maximum, "(((n)))");
            if (!positive.successful || !metrics.narrowCalls || !metrics.narrowKept)
                return 7;
            metrics = ParseMetrics.init;
            auto indirect = check!(NarrowIndirect.opCall)(maximum, "aaa");
            if (metrics.narrowCalls)
                return 8;
            auto nullable = check!(NarrowNullable.opCall)(maximum, "aaa");
            auto unknown = check!(NarrowOpaque.opCall)(maximum, "nnn");
            Effects effects;
            maximum.userData = &effects;
            auto action = check!(NarrowAction.opCall)(maximum, "aaa");
            if (metrics.narrowCalls || !effects.actions)
                return 9;
        }
    return 0;
}

private template AliasSeq(T...) {
    alias AliasSeq = T;
}
