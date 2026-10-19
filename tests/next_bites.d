module tests.next_bites;
import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private bool has(string text, string needle) @nogc nothrow pure {
    if (needle.length > text.length)
        return false;
    foreach (i; 0 .. text.length - needle.length + 1)
        if (text[i .. i + needle.length] == needle)
            return true;
    return false;
}

private string report(string grammar) nothrow {
    auto result = nextBitesReport(grammar);
    assert(result.status == Status.ok);
    return result.report;
}

int main() nothrow {
    alarm(45);
    // Paper examples: nullable choice, star, stopping delimiter.
    const unsafeNullable = report("N1: Root <- ('a' / 'c'?) 'a'");
    assert(has(unsafeNullable, "\"prop10\":false") && has(unsafeNullable, "\"wellFormed\":true"));
    const safeNullable = report("N2: Root <- ('a' / 'c'?) 'b'");
    assert(has(safeNullable, "\"prop10\":true") && has(safeNullable, "\"prop11\":true"));
    const delimiter = report("N3: Root <- (!'a' .)* 'a'");
    assert(has(delimiter, "\"prop12\":true") && has(delimiter, "\"prop13\":true"));
    const hidden = report("N4: Root <- 'a'* ('ab' / 'c')");
    assert(has(hidden, "\"prop12\":false"));
    const fine = report("N5: Root <- 'a'* ('b' / 'c')");
    assert(has(fine, "\"prop12\":true"));
    // Nested rule calls: the call site's continuation reaches the callee's choice.
    const nested = report("N6: Root <- Pick 'a' Pick <- 'a' / 'c'?");
    assert(has(nested, "\"rule\":\"Pick\"") && has(nested, "\"prop10\":false"));
    const nestedSafe = report("N7: Root <- Pick 'b' Pick <- 'a' / 'c'?");
    assert(has(nestedSafe, "\"prop10\":true"));
    // Failure continuation inside a lookahead and a left-recursive/unknown fallback.
    const lookahead = report("N8: Root <- !('a' / 'b') 'c'");
    assert(has(lookahead, "\"kind\":\"choice\"") && has(lookahead, "\"disjoint\":true"));
    const left = report("N9: Root <- Root 'a' / 'b'");
    assert(has(left, "\"wellFormed\":false") && has(left, "\"prop10\":false"));
    const opaque = report("N10: Root <- 'a' / Opaque Opaque <- external");
    assert(has(opaque, "\"trusted\":false") && has(opaque, "\"prop10\":false"));
    // Determinism and error handling.
    assert(report("N1: Root <- ('a' / 'c'?) 'a'") == unsafeNullable);
    assert(nextBitesReport("Bad: Root <- 'a' #\x80").status == Status.invalidInput);
    assert(nextBitesReport("Broken:").status == Status.invalidInput);
    printf("next bites passed\n");
    return 0;
}
