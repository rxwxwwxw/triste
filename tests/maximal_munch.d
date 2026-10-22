/** X2 integration check: an ordered choice of literals that is prefix-closed and lists longer literals first behaves as
    maximal munch, so a region containing it is compiled to one DFA with stop guards. For every string up to a length over
    small alphabets, `check` and `accept` of the compiled grammars equal those of the same grammars with a predicate that
    forces the walked combinators, in both backends. Run through scripts/maximal-munch-check.sh, which applies a timeout. */
module tests.maximal_munch;
import npegged.grammar;
import npegged.peg : ParseContext, check, accept, parseRecords, CompactResult;
import core.stdc.stdio : printf, fprintf, stderr;
import core.stdc.stdlib : abort;
import core.sys.posix.unistd : alarm;

private struct Case(string compiled, string walked) {
    struct Dfa {
        mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(compiled));
    }

    struct DfaCombinators {
        mixin(grammar!(Memoization.selective, void, ParserBackend.combinators)(compiled));
    }

    struct Walked {
        mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(walked));
    }
}

private enum ops = `'<<=' / '<<' / '<=' / '<' / '>>=' / '>>' / '>=' / '>' / '==' / '=' / '!=' / '!' / '&&' / '&' / '|'`;
private enum opsCompiled = "M: Root <- Space (Op Space)* eoi\n Op <- " ~ ops ~ "\n Space <: [ \\t]*";
private enum opsWalked = "M: Root <- Space (Op Space)* eoi\n Op <- &. (" ~ ops ~ ")\n Space <: [ \\t]*";
// Greedy fails on `abz` although `a bz` would match: the guard must keep the DFA from accepting it.
private enum tokensCompiled = "M: Root <- (T ';'?)* eoi\n T <- 'ab' / 'a' / 'bz' / 'b'";
private enum tokensWalked = "M: Root <- (T ';'?)* eoi\n T <- &. ('ab' / 'a' / 'bz' / 'b')";

private size_t compare(string compiled, string walked)(string alphabet, size_t maxLength) {
    alias C = Case!(compiled, walked);
    static assert(C.Dfa.M._dfa_Root.valid && C.DfaCombinators.M._dfa_Root.valid);
    static assert(!__traits(hasMember, C.Walked.M, "_dfa_Root"));
    char[8] buffer;
    size_t checked;
    foreach (length; 0 .. maxLength + 1) {
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
            ParseContext c1, c2, c3, c4, c5;
            const dfa = check!(C.Dfa.M.opCall)(c1, input);
            const viaCombinators = check!(C.DfaCombinators.M.opCall)(c2, input);
            const walkedResult = check!(C.Walked.M.opCall)(c3, input);
            const accepted = accept!(C.Dfa.M.opCall)(c4, input);
            const acceptedWalked = accept!(C.Walked.M.opCall)(c5, input);
            const same = dfa.successful == walkedResult.successful && dfa.end == walkedResult.end
                && dfa.failEnd == walkedResult.failEnd
                && dfa.successful == viaCombinators.successful && dfa.end == viaCombinators.end
                && dfa.failEnd == viaCombinators.failEnd
                && accepted.accepted == acceptedWalked.accepted
                && accepted.accepted == (dfa.successful && dfa.end == input.length);
            if (!same) {
                fprintf(stderr,
                        "maximal munch differs on %.*s: dfa %d/%zu/%zu walked %d/%zu/%zu\n",
                        cast(int)input.length, input.ptr, cast(int)dfa.successful, dfa.end,
                        dfa.failEnd, cast(int)walkedResult.successful, walkedResult.end, walkedResult
                            .failEnd);
                abort();
            }
            ++checked;
        }
    }
    return checked;
}

uint spanTag(string name) @nogc nothrow pure {
    return name == "R.Op" || name == "R.Word" ? 7 : uint.max;
}

uint treeTag(string name) @nogc nothrow pure {
    return name == "R.Root" ? 3 : spanTag(name);
}

private struct RecordCase(string compiled, string walked, alias Selector) {
    struct Tagged {
        mixin(grammar!(Memoization.selective, Selector, ParserBackend.direct, true)(compiled));
    }

    struct Walked {
        mixin(grammar!(Memoization.selective, Selector, ParserBackend.direct, false)(walked));
    }

    struct Combinators {
        mixin(grammar!(Memoization.selective, Selector, ParserBackend.combinators, true)(compiled));
    }
}

private bool sameRecords(ref CompactResult a, ref CompactResult b, bool frontier) {
    if (a.successful != b.successful || a.status != b.status || a.nodes.length != b.nodes.length
            || (a.successful || frontier) && a.end != b.end)
        return false;
    foreach (i, node; a.nodes)
        if (node != b.nodes[i])
            return false;
    return true;
}

// Leaf records over a maximal-munch operator choice: the tagged table must fire the same events as the walk.
private enum recordOpsCompiled = "R: Root <- Space (Op Space / Word Space)* eoi\n Op <- " ~ ops
    ~ "\n Word <- [a-b]+\n Space <: [ \\t]*";
private enum recordOpsWalked = "R: Root <- Space (Op Space / Word Space)* eoi\n Op <- &. (" ~ ops
    ~ ")\n Word <- [a-b]+\n Space <: [ \\t]*";

private size_t compareRecords(string compiled, string walked, alias Selector)(string alphabet, size_t maxLength) {
    alias C = RecordCase!(compiled, walked, Selector);
    static assert(C.Tagged.R._dfa_Root.tagged.valid);
    char[8] buffer;
    size_t checked;
    foreach (length; 0 .. maxLength + 1) {
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
            ParseContext c1, c2, c3;
            auto tagged = parseRecords!(C.Tagged.R.opCall, Selector, false)(c1, input);
            auto walkedResult = parseRecords!(C.Walked.R.opCall, Selector, false)(c2, input);
            auto combinators = parseRecords!(C.Combinators.R.opCall, Selector, false)(c3, input);
            if (!sameRecords(tagged, walkedResult, false) || !sameRecords(tagged, combinators, true)) {
                fprintf(stderr, "maximal munch records differ on %.*s\n", cast(int)input.length, input
                        .ptr);
                abort();
            }
            ++checked;
        }
    }
    return checked;
}

int main() {
    alarm(240);
    size_t checked;
    checked += compare!(opsCompiled, opsWalked)("<=>!&| x\t", 6);
    checked += compare!(tokensCompiled, tokensWalked)("abz;", 8);
    checked += compareRecords!(recordOpsCompiled, recordOpsWalked, spanTag)("<=>!a \t", 6);
    checked += compareRecords!(recordOpsCompiled, recordOpsWalked, treeTag)("<=a ", 6);
    printf("maximal-munch regions agree with the walked choices on %zu strings\n", checked);
    return 0;
}
