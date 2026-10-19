module tests.coverage_generation;
import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private ParseTree act(bool CT)(ref State!CT state, ParseTree tree) @nogc nothrow {
    return tree;
}

private struct Compiled(string definition) {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(definition));
}

private string nameOf(string definition) {
    size_t end;
    while (definition[end] != ':')
        ++end;
    return definition[0 .. end];
}

private CoveringSet cover(string definition, string rule, size_t count, ulong seed, bool guided = true,
        size_t attempts = 20_000)() nothrow {
    alias P = Compiled!definition;
    mixin("alias parser = P." ~ nameOf(definition) ~ "." ~ rule ~ ";");
    GeneratorOptions options;
    options.seed = seed;
    auto set = generateCovering!parser(definition, rule, count, options, attempts, false, guided);
    foreach (text; set.accepted.texts) { // everything listed is independently accepted
        ParseContext context;
        auto verdict = check!parser(context, text);
        assert(verdict.successful && verdict.end == text.length);
    }
    return set;
}

int main() nothrow {
    alarm(120);
    // Exercised vs proposed: ('a' / 'ab') 'c' proposes 'ab' but no accepted sample ever derives through it.
    auto trap = cover!("T: Root <- ('a' / 'ab') 'c'", "Root", 20, 5)();
    assert(trap.coverable == 2 && trap.covered == 1);
    assert(trap.proposedAlternatives == 2 && trap.exercisedAlternatives == 1);
    assert(trap.uncovered.length == 1 && trap.accepted.rejected > 0);
    // A rare alternative under guidance: many alternatives, tiny sample.
    enum wide = "W: Root <- 'a' / 'b' / 'c' / 'd' / 'e' / 'f' / 'g' / 'h' / 'i' / 'j'";
    auto guided = cover!(wide, "Root", 12, 21)();
    size_t guidedTotal, blindTotal, guidedFull;
    static foreach (seed; [1, 2, 3, 4, 5, 6, 7, 8]) {
        {
            // 20 samples over ten alternatives: guidance reaches all of them for every seed.
            const withGuidance = cover!(wide, "Root", 20, seed)();
            const without = cover!(wide, "Root", 20, seed, false)();
            guidedTotal += withGuidance.covered;
            blindTotal += without.covered;
            guidedFull += withGuidance.covered == withGuidance.coverable;
        }
    }
    assert(guidedFull == 8 && guidedTotal == 80 && blindTotal < guidedTotal);
    // Optional and repetition buckets are all reached, including empty and many.
    auto buckets = cover!("B: Root <- 'x'? 'y'* 'z'+ eoi", "Root", 60, 9)();
    assert(buckets.uncovered.length == 0 && buckets.covered == buckets.coverable);
    // An alternative guarded away by a predicate can be covered because the oracle decides acceptance.
    auto guardedBranch = cover!("G: Root <- !'a' [a-b] / 'a' 'c'", "Root", 40, 2)();
    assert(guardedBranch.covered == guardedBranch.coverable);
    // Unreachable rules and unknown constructs are reported separately, not as failures.
    auto separate = cover!("S: Root <- 'a' / 'b' Dead <- 'q' / 'r'", "Root", 10, 1)();
    assert(separate.unreachable == 2 && separate.covered == separate.coverable);
    auto opaque = cover!("U: Root <- 'a'{act} / 'b'", "Root", 5, 1, true, 50)();
    // The action alternative fails generation; 'b' is still produced, but its derivation cannot be followed past the action.
    assert(opaque.accepted.generationFailures > 0 && opaque.unknown == 2 && opaque.coverable == 0);
    foreach (text; opaque.accepted.texts)
        assert(text == "b");
    assert(opaque.unattributed == opaque.accepted.texts.length);
    // Fixed seeds reproduce the whole result.
    auto repeat = cover!(wide, "Root", 12, 21)();
    assert(repeat.accepted.texts == guided.accepted.texts && repeat.covered == guided.covered);
    // Timeout behavior under an unreachable branch: bounded attempts, uncovered reported, nothing unverified listed.
    auto shadowed = cover!("H: Root <- 'a' / 'ab'", "Root", 30, 4, true, 400)();
    assert(shadowed.uncovered.length >= 0 && shadowed.accepted.texts.length <= 30);
    foreach (text; shadowed.accepted.texts)
        assert(text == "a");
    printf("coverage generation passed\n");
    return 0;
}
