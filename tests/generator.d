module tests.generator;
import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private bool contains(const string[] values, string wanted) @nogc nothrow pure {
    foreach (value; values)
        if (value == wanted)
            return true;
    return false;
}

int main() nothrow {
    alarm(60);
    enum choices = "C: Root <- 'a' / 'bb' / [0-9] / 'cd' 'e'?";
    // Same seed -> same stream; different seeds explore differently.
    GeneratorOptions seeded;
    seeded.seed = 7;
    auto first = generateCandidates(choices, "Root", 200, seeded);
    auto again = generateCandidates(choices, "Root", 200, seeded);
    assert(first.status == Status.ok && first.texts == again.texts && first.texts.length == 200);
    GeneratorOptions other;
    other.seed = 8;
    assert(generateCandidates(choices, "Root", 200, other).texts != first.texts);
    // Every branch is explored within a modest sample (uniform ordered-choice proposals).
    foreach (wanted; ["a", "bb", "cd", "cde"])
        assert(contains(first.texts, wanted));
    bool digit;
    foreach (text; first.texts)
        digit = digit || (text.length == 1 && text[0] >= '0' && text[0] <= '9');
    assert(digit);
    // Recursion has a hard stop and productive grammars finish.
    auto recursive = generateCandidates("R: Root <- 'x' Root / 'y'", "Root", 300);
    assert(recursive.texts.length == 300);
    foreach (text; recursive.texts)
        assert(text.length < 200 && text[$ - 1] == 'y');
    GeneratorOptions limited;
    limited.maxDepth = 2;
    limited.softDepth = 100; // never take the cheap branch: depth budget must stop the walk
    auto stopped = generateCandidates("R: Root <- 'x' Root / 'x' Root / 'y'", "Root", 100, limited);
    bool sawBudget;
    foreach (status; stopped.statuses)
        sawBudget = sawBudget || status == GenStatus.budgetExceeded;
    assert(sawBudget && stopped.texts.length < 100);
    // A nullable loop body cannot cause non-progress loops.
    auto nullable = generateCandidates("N: Root <- ('a'?)* 'b'", "Root", 100);
    assert(nullable.status == Status.ok && nullable.texts.length == 100);
    // End of input terminal contributes nothing; repetition lengths are skewed and include empty.
    auto stars = generateCandidates("E: Root <- 'a'* eoi", "Root", 400);
    bool empty, longer;
    foreach (text; stars.texts) {
        empty = empty || text.length == 0;
        longer = longer || text.length >= 5;
    }
    assert(empty && longer);
    // UTF-8 literals roundtrip byte for byte.
    auto utf8 = generateCandidates("U: Root <- 'é' 'ü'", "Root", 3);
    assert(utf8.texts.length == 3 && utf8.texts[0] == "éü");
    // Unsupported constructs report a status and reason instead of candidates.
    auto action = generateCandidates("A: Root <- 'a'{act}", "Root", 5);
    assert(action.status == Status.ok && action.texts.length == 0
            && action.statuses[0] == GenStatus.unsupported && action.reasons[0].length);
    auto external = generateCandidates("X: Root <- 'a' / Opaque Opaque <- external", "Root", 50);
    bool unsupported;
    foreach (status; external.statuses)
        unsupported = unsupported || status == GenStatus.unsupported;
    assert(unsupported);
    // Budget on output size.
    GeneratorOptions tiny;
    tiny.maxOutput = 3;
    auto big = generateCandidates("B: Root <- 'abcdef'", "Root", 2, tiny);
    assert(big.texts.length == 0 && big.statuses[0] == GenStatus.budgetExceeded);
    // Errors.
    assert(generateCandidates("Broken:", "Root", 1).status == Status.invalidInput);
    assert(generateCandidates("B: Root <- 'a'", "Missing", 1).status == Status.invalidInput);
    assert(generateCandidates("Bad: Root <- 'a' #\x80", "Root", 1).status == Status.invalidInput);
    printf("generator passed\n");
    return 0;
}
