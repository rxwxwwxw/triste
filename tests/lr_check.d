/** L5/L6a integration check: for rules whose closed region is certified LL(1), the LR(1) table recognizer built from the CFG
    reading accepts exactly what the generated PEG parsers accept, on every string up to a length over small alphabets.
    This is evidence for the certificate, not a proof of it. Run through scripts/lr-check.sh, which applies a timeout. */
module tests.lr_check;
import npegged.grammar;
import npegged.lr : lrAccepts;
import core.stdc.stdio : printf, fprintf, stderr;
import core.stdc.stdlib : abort;
import core.sys.posix.unistd : alarm;

private struct Case(string text, bool withDirect) {
    struct Reference {
        mixin(grammar!(Memoization.selective)(text));
    }

    static if (withDirect) {
        struct Direct {
            mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(text));
        }
    }
}

private enum numbers = `L: Num <- [0-9]+ Expr <- Num ('+' Num)* Root <- Expr eoi`;
private enum nested = `L: Root <- Item eoi Item <- 'a' Item 'b' / 'c'`;
private enum words = `L: Root <- Word (' ' Word)* eoi Word <- [a-c]+`;

private size_t compare(string text, string alphabet, size_t maxLength, bool withDirect = true)() {
    alias C = Case!(text, withDirect);
    const built = lrBuild(text, "Root");
    if (built.status != Status.ok || built.automaton.truncated || built.automaton.conflicts.length) {
        fprintf(stderr, "no conflict-free LR(1) tables for %s\n", (text ~ "\0").ptr);
        abort();
    }
    char[8] buffer;
    size_t checked;
    foreach (length; 0 .. maxLength + 1) {
        size_t combinations = 1;
        foreach (_; 0 .. length)
            combinations *= alphabet.length;
        foreach (code; 0 .. combinations) {
            size_t digit = code;
            foreach (i; 0 .. length) {
                buffer[i] = alphabet[digit % alphabet.length];
                digit /= alphabet.length;
            }
            const input = cast(string)buffer[0 .. length];
            ParseContext context;
            const pegReference = accept!(C.Reference.L.Root)(context, input).accepted;
            static if (withDirect)
                const pegDirect = accept!(C.Direct.L.Root)(context, input).accepted;
            else
                const pegDirect = pegReference; // recursive rules: the direct backend cannot infer @nogc, so only the combinators run
            const lr = lrAccepts(built.grammar, built.automaton, input);
            if (!lr.ok || lr.accepted != pegReference || pegReference != pegDirect) {
                fprintf(stderr,
                        "LR/PEG disagreement for %s input=%.*s lr=%d reference=%d direct=%d\n",
                        (text ~ "\0")
                            .ptr, cast(int)length, input.ptr, lr.accepted, pegReference, pegDirect);
                abort();
            }
            ++checked;
        }
    }
    return checked;
}

int main() {
    alarm(120);
    printf("numbers: %zu strings agree\n", compare!(numbers, "1+x", 7)());
    printf("nested: %zu strings agree\n", compare!(nested, "abc", 7, false)());
    printf("words: %zu strings agree\n", compare!(words, "ab ", 7)());
    return 0;
}
