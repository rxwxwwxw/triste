/** P8 follow-up integration check: `check` runs a directly left-recursive rule as its loop form. For every string up to a length
    over a small alphabet the verdict, end and failure frontier equal those of the hand-written loop grammar (which has no left
    recursion), and verdict and end equal those of the seed-growth parse in records mode, which keeps seed growth. Run through
    scripts/left-recursion-check.sh, which applies a timeout. */
module tests.left_recursion;
import npegged.grammar;
import npegged.peg : ParseContext, check, parseRecords;
import core.stdc.stdio : printf, fprintf, stderr;
import core.stdc.stdlib : abort;
import core.sys.posix.unistd : alarm;

uint noRecords(string) @nogc nothrow pure {
    return uint.max;
}

private struct Seed {
    mixin(grammar!(Memoization.selective, void, ParserBackend.combinators)(`
A:
    Root <- Space Expr eoi
    Expr <- Expr ('+' / '-') Space Term / Term
    Term <- Term ('*' / '/') Space Primary / Primary
    Primary <- '(' Space Expr ')' Space / [0-9]+ Space
    Space <: [ ]*
`));
}

private struct Loops {
    mixin(grammar!(Memoization.selective, void, ParserBackend.combinators)(`
A:
    Root <- Space Expr eoi
    Expr <- Term (('+' / '-') Space Term)*
    Term <- Primary (('*' / '/') Space Primary)*
    Primary <- '(' Space Expr ')' Space / [0-9]+ Space
    Space <: [ ]*
`));
}

private struct DirectSeed {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(`
A:
    Root <- Space Expr eoi
    Expr <- Expr ('+' / '-') Space Term / Term
    Term <- Term ('*' / '/') Space Primary / Primary
    Primary <- '(' Space Expr ')' Space / [0-9]+ Space
    Space <: [ ]*
`));
}

int main() {
    alarm(240);
    char[8] buffer;
    enum alphabet = "1+*( )";
    size_t checked;
    foreach (length; 0 .. buffer.length + 1) {
        size_t combinations = 1;
        foreach (_; 0 .. length)
            combinations *= alphabet.length;
        foreach (code; 0 .. combinations) {
            size_t rest = code;
            foreach (i; 0 .. length) {
                buffer[i] = alphabet[rest % alphabet.length];
                rest /= alphabet.length;
            }
            const input = cast(string)buffer[0 .. length];
            ParseContext c1, c2, c3, c4;
            const lowered = check!(Seed.A.opCall)(c1, input);
            const loops = check!(Loops.A.opCall)(c2, input);
            const direct = check!(DirectSeed.A.opCall)(c3, input);
            auto grown = parseRecords!(Seed.A.opCall, noRecords, false)(c4, input);
            const ok = lowered.successful == loops.successful && lowered.end == loops.end
                && lowered.failEnd == loops.failEnd && direct.successful == lowered.successful
                && direct.end == lowered.end && direct.failEnd == lowered.failEnd
                && grown.successful == lowered.successful && (!grown.successful || grown.end == lowered
                        .end);
            if (!ok) {
                fprintf(stderr, "left recursion differs on %.*s\n", cast(int)input.length, input.ptr);
                abort();
            }
            ++checked;
        }
    }
    printf("loop form agrees with seed growth and the hand-written loops on %zu strings\n", checked);
    return 0;
}
