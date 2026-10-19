module tests.ll_regions;
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

/// Class of a named rule's closed region in the JSON report.
private string classOf(string grammar, string rule) nothrow {
    auto result = conversionReport(grammar);
    assert(result.status == Status.ok);
    const key = "{\"rule\":\"" ~ rule ~ "\",\"class\":\"";
    foreach (i; 0 .. result.report.length - key.length) {
        if (result.report[i .. i + key.length] == key) {
            size_t end = i + key.length;
            while (result.report[end] != '"')
                ++end;
            return result.report[i + key.length .. end];
        }
    }
    assert(false, "rule missing from report");
}

int main() nothrow {
    alarm(45);
    // Known LL(1) grammar, including nested rules and a trailing eoi.
    enum expr = "E: Num <- [0-9]+ Expr <- Term (('+' / '-') Term)* Term <- Num / '(' Expr ')' Root <- Expr eoi";
    foreach (rule; ["Num", "Expr", "Term", "Root"])
        assert(classOf(expr, rule) == "certifiedLL1");
    // Predicates (safe-looking and unsafe) have no CFG counterpart.
    assert(classOf("P: Root <- !'a' 'b'", "Root") == "PEGOnly");
    assert(classOf("P: Root <- &'a' 'a'", "Root") == "PEGOnly");
    // Prefix capture and shadowing.
    assert(classOf("S: Root <- ('a' / 'aa') 'b'", "Root") == "PEGOnly");
    assert(classOf("S: Root <- 'a' / 'ab'", "Root") == "PEGOnly");
    // Bounded lookahead: FIRST overlaps but BITES separates the alternatives.
    assert(classOf("B: Root <- 'ab' / 'ac'", "Root") == "boundedLookaheadCandidate");
    // Greedy repetition: hides what follows or does not.
    assert(classOf("G: Root <- 'a'* 'a'", "Root") == "CFGCandidateUnproven");
    assert(classOf("G: Root <- 'a'* 'b'", "Root") == "certifiedLL1");
    assert(classOf("G: Root <- 'a'+ 'b'", "Root") == "certifiedLL1");
    assert(classOf("G: Root <- 'a'? 'a'", "Root") == "CFGCandidateUnproven");
    assert(classOf("G: Root <- ('a' 'b'?)* 'c'", "Root") != "PEGOnly");
    // Nullable alternatives, positional continuation.
    assert(classOf("N: Root <- ('a' / 'c'?) 'b'", "Root") == "certifiedLL1");
    assert(classOf("N: Root <- ('a' / 'c'?) 'a'", "Root") == "CFGCandidateUnproven");
    assert(classOf("N: Root <- 'c'? / 'a'", "Root") == "CFGCandidateUnproven");
    // Left recursion, actions, unknown nodes.
    assert(classOf("L: Root <- Root 'a' / 'b'", "Root") == "PEGOnly");
    assert(classOf("A: Root <- 'a'{act}", "Root") == "unknown");
    assert(classOf("U: Root <- 'a' / Opaque Opaque <- external", "Root") == "unknown");
    // Region closure: a caller inherits its callee's worse class, a callee does not inherit its caller's.
    enum closure = "C: Root <- Leaf 'x' Leaf <- 'a' / 'ab'";
    assert(classOf(closure, "Root") == "PEGOnly" && classOf(closure, "Leaf") == "PEGOnly");
    enum clean = "C: Root <- Leaf 'x' Leaf <- 'a' Other <- !'q' 'r'";
    assert(classOf(clean, "Root") == "certifiedLL1" && classOf(clean, "Other") == "PEGOnly");
    // Witnesses and blockers are reported with node indices; formats are stable.
    auto witnessed = conversionReport("W: Root <- 'a' / 'ab'");
    assert(has(witnessed.report, "ordered-choice shadowing") && has(witnessed.report, "\"node\":"));
    auto text = conversionReport("W: Root <- 'a'* 'a'", EligibilityFormat.text);
    assert(text.status == Status.ok && has(text.report, "greedy repetition may consume input that follows it"));
    assert(conversionReport(expr).report == conversionReport(expr).report);
    assert(conversionReport("E: Root <- 'a'", cast(EligibilityFormat)99).status == Status
            .invalidInput);
    assert(conversionReport("Bad: Root <- 'a' #\x80").status == Status.invalidInput);
    assert(conversionReport("Broken:").status == Status.invalidInput);
    printf("ll regions passed\n");
    return 0;
}
