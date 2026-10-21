/** O4(b)/(c) integration check: a regular region whose rules emit leaf records produces, through its tagged table,
    exactly the records, verdict, end and status of the same region walked rule by rule. Every string up to a length over
    small alphabets, in span and tree mode, on grammars with ordered-choice ambiguity (`\r\n?`), nested quoting and
    nullable records. Run through scripts/tagged-regions-check.sh, which applies a timeout and memory limit. */
module tests.tagged_regions;
import npegged.grammar;
import npegged.peg : ParseContext, parseRecords, CompactResult;
import core.stdc.stdio : printf, fprintf, stderr;
import core.stdc.stdlib : abort;
import core.sys.posix.unistd : alarm;

uint spanTag(string name) @nogc nothrow pure {
    return name == "R.Field" || name == "R.Item" ? 7 : uint.max;
}

uint treeTag(string name) @nogc nothrow pure {
    return name == "R.Root" ? 3 : spanTag(name);
}

private struct Case(string text, alias Selector) {
    struct Tagged {
        mixin(grammar!(Memoization.selective, Selector, ParserBackend.direct, true)(text));
    }

    struct Walked {
        mixin(grammar!(Memoization.selective, Selector, ParserBackend.direct, false)(text));
    }

    struct Combinators {
        mixin(grammar!(Memoization.selective, Selector, ParserBackend.combinators, true)(text));
    }
}

private enum csv = `R: Root <- Field (Sep Field)* eoi
    Sep <- ',' / '\r' '\n'? / '\n'
    Field <- [ \t]* (('"' ('""' / !'"' .)* '"' / (![," \t\r\n] .)+) [ \t]*)?`;
private enum items = `R: Root <- Item (',' Item)* eoi
    Item <- [a-b]* 'c'?`;
private enum prefixed = `R: Root <- Item ';' Item ';'* eoi
    Item <- 'a'+ / 'b' 'a'*`;

/// On failure `end` is the failure frontier: a tagged region reports the scanner's, as validation mode does, where a walk
/// reports the frontier of the rule it was inside. Everything else must agree exactly.
private bool same(ref CompactResult a, ref CompactResult b, bool frontier) {
    if (a.successful != b.successful || a.status != b.status || a.nodes.length != b.nodes.length
            || (a.successful || frontier) && a.end != b.end)
        return false;
    foreach (i, node; a.nodes)
        if (node != b.nodes[i])
            return false;
    return true;
}

private size_t compare(string text, alias Selector)(string alphabet, size_t maxLength) {
    alias C = Case!(text, Selector);
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
            auto walked = parseRecords!(C.Walked.R.opCall, Selector, false)(c2, input);
            auto combinators = parseRecords!(C.Combinators.R.opCall, Selector, false)(c3, input);
            if (!same(tagged, walked, false) || !same(tagged, combinators, true)) {
                fprintf(stderr, "records differ on %.*s (tagged %d end %zu status %d nodes %zu, walked %d end %zu status %d nodes %zu, combinators %d end %zu status %d nodes %zu)\n",
                        cast(int)input.length, input.ptr, cast(int)tagged.successful, tagged.end,
                        cast(int)tagged.status, tagged.nodes.length, cast(int)walked.successful,
                        walked.end, cast(int)walked.status, walked.nodes.length,
                        cast(int)combinators.successful, combinators.end,
                        cast(int)combinators.status, combinators.nodes.length);
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
    checked += compare!(csv, spanTag)("a,\" \r\n", 7);
    checked += compare!(csv, treeTag)("a,\"\r\n ", 6);
    checked += compare!(items, spanTag)("abc,;", 8);
    checked += compare!(items, treeTag)("abc,", 8);
    checked += compare!(prefixed, spanTag)("ab;", 8);
    printf("tagged regions agree with the walked regions on %zu strings\n", checked);
    return 0;
}
