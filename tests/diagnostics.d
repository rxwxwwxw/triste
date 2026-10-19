module tests.diagnostics;
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

private string json(string grammar) nothrow {
    auto result = diagnosticReport(grammar);
    assert(result.status == Status.ok);
    return result.report;
}

int main() nothrow {
    alarm(45);
    // Lint and optimization are separate objects; cuts are never emitted.
    const disjoint = json("D1: Root <- 'a' / 'b'");
    assert(has(disjoint, "\"lint\":{\"hiding\":\"none-proven\"") && has(disjoint, "\"optimization\":{"));
    assert(has(disjoint, "predictiveChoice (emitted today)") && has(disjoint, "\"cutEmitted\":false"));
    assert(!has(disjoint, "\"cutEmitted\":true"));
    assert(has(disjoint, "\"theorem\":\"Proposition 6\"") && has(disjoint, "\"first\":\"disjoint\""));
    // Terminal and lookahead cases: FIRST overlaps, BITES proves disjointness.
    const guarded = json("D2: Root <- !'abc' [a-z]+ / 'abc' [a-z]*");
    assert(has(guarded, "\"first\":\"overlap\"") && has(guarded, "\"bites\":\"proven-disjoint\""));
    assert(has(guarded, "Proposition 5"));
    // Definite shadowing and a literal-choice backend recommendation.
    const shadowed = json("D3: Root <- 'a' / 'ab'");
    assert(has(shadowed, "\"hiding\":\"definite\"") && has(shadowed, "literalChoice2"));
    assert(has(shadowed, "alternatives are not proven BITES-disjoint"));
    // Nullable choice and star: why a cut was (not) a candidate.
    const unsafe = json("D4: Root <- ('a' / 'c'?) 'a'");
    assert(has(unsafe, "\"hiding\":\"possible\"") && has(unsafe, "condition (6) not proven"));
    assert(has(unsafe, "\"cutCandidate\":false"));
    const star = json("D5: Root <- 'a'* ('b' / 'c')");
    assert(has(star, "\"kind\":\"star\"") && has(star, "Proposition 12") && has(star, "\"theorem\":\"Proposition 13\""));
    const hiddenStar = json("D6: Root <- 'a'* ('ab' / 'c')");
    assert(has(hiddenStar, "\"kind\":\"star\"") && has(hiddenStar, "condition (8) not proven"));
    // Unknown parts, effects, left recursion.
    const opaque = json("D7: Root <- 'a' / Opaque Opaque <- external");
    assert(has(opaque, "\"hiding\":\"unknown\"") && has(opaque, "not well-formed"));
    const effects = json("D8: Root <- A 'x' A <- 'a'{act} / 'b'");
    assert(has(effects, "\"cutCandidate\":false") && has(effects, "actionful or its effects are unknown"));
    const left = json("D9: Root <- Root 'a' / 'b'");
    assert(has(left, "\"hiding\":\"unknown\"") && has(left, "\"cutCandidate\":false"));
    // Stability and formats.
    assert(json("D1: Root <- 'a' / 'b'") == disjoint);
    auto text = diagnosticReport("D4: Root <- ('a' / 'c'?) 'a'", EligibilityFormat.text);
    assert(text.status == Status.ok && has(text.report, "lint: hiding=possible") && has(text.report, "optimization:"));
    assert(has(text.report, "cuts are never emitted"));
    assert(diagnosticReport("D1: Root <- 'a'", cast(EligibilityFormat)99).status == Status
            .invalidInput);
    assert(diagnosticReport("Bad: Root <- 'a' #\x80").status == Status.invalidInput);
    assert(diagnosticReport("Broken:").status == Status.invalidInput);
    // The report does not depend on the parser backend or memoization (it is analysis-only), unlike eligibility.
    const a = eligibilityReport!(Memoization.selective, void, ParserBackend.direct)("D1: Root <- 'a' / 'b'");
    const b = eligibilityReport("D1: Root <- 'a' / 'b'");
    assert(a.status == Status.ok && b.status == Status.ok && json("D1: Root <- 'a' / 'b'") == disjoint);
    printf("diagnostics passed\n");
    return 0;
}
