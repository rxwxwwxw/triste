module tests.fuzz_differential;
import npegged.grammar;
import core.stdc.stdio : printf, fopen, fclose, fgets, FILE;
import core.stdc.string : strlen;
import core.sys.posix.unistd : alarm;

private enum expr = "Expr: Num <- [0-9]+ Sum <- Term (('+' / '-') Term)* Term <- Num / '(' Sum ')' Root <- Sum eoi";

private struct Reference {
    mixin(grammar!(Memoization.selective, void, ParserBackend.combinators)(expr));
}

private struct Candidate {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(expr));
}

private struct LeftB {
    mixin(grammar!(Memoization.selective)("X: Root <- 'a'* 'b'"));
}

private struct RightC {
    mixin(grammar!(Memoization.selective)("X: Root <- 'a'* 'c'"));
}

private struct Letters {
    mixin(grammar!(Memoization.selective)("L: Root <- [a-z]+ eoi"));
}

private struct Utf8A {
    mixin(grammar!(Memoization.selective, void, ParserBackend.combinators)("U: Root <- 'é'+ eoi"));
}

private struct Utf8B {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)("U: Root <- 'é'+ eoi"));
}

private bool hasHigh(string text) @nogc nothrow pure {
    foreach (c; text)
        if (cast(ubyte)c >= 0x80)
            return true;
    return false;
}

int main() nothrow {
    alarm(120);
    // 1. Real backend pair: no disagreement; labels come from the parser; retained invalid inputs really are invalid.
    FuzzOptions options;
    options.seed = 3;
    options.iterations = 1500;
    auto backends = fuzzDifferential!(Reference.Expr.Root, Candidate.Expr.Root)(expr, "Root",
            "combinators", "direct", options);
    assert(backends.status == Status.ok && backends.mismatches.length == 0 && backends.iterations >= 1500);
    assert(backends.validMutants > 0 && backends.invalidMutants > 0 && backends.randomInputs > 0
            && backends.validSeeds > 0);
    foreach (text; backends.invalidSamples) {
        ParseContext context;
        auto verdict = check!(Reference.Expr.Root)(context, text);
        assert(!(verdict.status == Status.ok && verdict.successful && verdict.end == text.length));
    }
    // Deterministic replay: identical options give an identical report.
    auto again = fuzzDifferential!(Reference.Expr.Root, Candidate.Expr.Root)(expr, "Root",
            "combinators", "direct", options);
    assert(again.iterations == backends.iterations && again.validMutants == backends.validMutants
            && again.invalidSamples == backends.invalidSamples);
    // 2. A seeded mismatch (two different grammars) is found, shrunk to a 1-minimal input, and replayable.
    FuzzOptions seeded;
    seeded.seed = 11;
    seeded.iterations = 300;
    auto found = fuzzDifferential!(LeftB.X.Root, RightC.X.Root)("X: Root <- 'a'* 'b'", "Root",
            "leftB", "rightC", seeded);
    assert(found.mismatches.length > 0 && found.regressionLines.length == found.mismatches.length);
    foreach (mismatch; found.mismatches) {
        assert(mismatch.shrunk.length == 1 && mismatch.shrunk.length <= mismatch.original.length);
        assert(mismatch.shrunk == "b" || mismatch.shrunk == "c");
    }
    assert(replayStillMismatches!(LeftB.X.Root, RightC.X.Root)(found.regressionLines[0]));
    assert(!replayStillMismatches!(LeftB.X.Root, LeftB.X.Root)(found.regressionLines[0])); // an identical pair agrees
    assert(!replayStillMismatches!(LeftB.X.Root, RightC.X.Root)("not a regression line"));
    auto foundAgain = fuzzDifferential!(LeftB.X.Root, RightC.X.Root)("X: Root <- 'a'* 'b'", "Root",
            "leftB", "rightC", seeded);
    assert(foundAgain.regressionLines == found.regressionLines);
    // 3. A valid mutation is not mislabeled: letters stay valid; everything labeled invalid is retained and verified.
    FuzzOptions letters;
    letters.seed = 5;
    letters.iterations = 800;
    auto labeled = fuzzDifferential!(Letters.L.Root, Letters.L.Root)("L: Root <- [a-z]+ eoi", "Root", "p",
            "p", letters);
    assert(labeled.mismatches.length == 0 && labeled.validMutants > 0 && labeled.invalidMutants > 0);
    foreach (text; labeled.invalidSamples) {
        ParseContext context;
        auto verdict = check!(Letters.L.Root)(context, text);
        assert(!(verdict.status == Status.ok && verdict.successful && verdict.end == text.length));
    }
    // 4. Invalid UTF-8 and truncation at end of input: both backends agree on damaged multi-byte input.
    FuzzOptions utf8;
    utf8.seed = 9;
    utf8.iterations = 1200;
    auto damaged = fuzzDifferential!(Utf8A.U.Root, Utf8B.U.Root)("U: Root <- 'é'+ eoi", "Root",
            "combinators", "direct", utf8);
    assert(damaged.mismatches.length == 0 && damaged.invalidMutants > 0);
    bool sawDamaged;
    foreach (text; damaged.invalidSamples)
        sawDamaged = sawDamaged || hasHigh(text);
    assert(sawDamaged);
    // 5. Wall-clock budget: the run stops early and says so.
    FuzzOptions budget;
    budget.iterations = 50_000_000;
    budget.deadlineMillis = 30;
    auto stopped = fuzzDifferential!(Letters.L.Root, Letters.L.Root)("L: Root <- [a-z]+ eoi", "Root", "p",
            "p", budget);
    assert(stopped.deadlineHit && stopped.iterations < 50_000_000);
    // 6. Versioned regression seeds on disk still agree for the backends pair.
    auto file = fopen("tests/regression/fuzz-seeds.txt", "r");
    assert(file !is null);
    scope (exit)
        fclose(file);
    char[512] buffer;
    size_t replayed;
    while (fgets(buffer.ptr, buffer.length, file)) {
        string line = cast(string)buffer[0 .. strlen(buffer.ptr)].idup;
        while (line.length && (line[$ - 1] == '\n' || line[$ - 1] == '\r'))
            line = line[0 .. $ - 1];
        if (!line.length || line[0] == '#')
            continue;
        assert(!replayStillMismatches!(Reference.Expr.Root, Candidate.Expr.Root)(line));
        ++replayed;
    }
    assert(replayed == 5);
    printf("fuzz differential passed\n");
    return 0;
}
