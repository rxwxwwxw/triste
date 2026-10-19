module tests.policy_generation;
import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private struct Compiled(string definition) {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(definition));
}

private string nameOf(string definition) {
    size_t end;
    while (definition[end] != ':')
        ++end;
    return definition[0 .. end];
}

private PolicyGeneration generate(string definition, string rule, size_t count, string policy,
        ulong seed = 1, size_t maxOutput = 4096)() nothrow {
    alias P = Compiled!definition;
    mixin("alias parser = P." ~ nameOf(definition) ~ "." ~ rule ~ ";");
    GeneratorOptions options;
    options.seed = seed;
    options.maxOutput = maxOutput;
    auto set = generateWithPolicy!parser(definition, rule, count, policy, options);
    foreach (text; set.accepted.texts) { // independently accepted by the reference parser
        ParseContext context;
        auto verdict = check!parser(context, text);
        assert(verdict.successful && verdict.end == text.length);
    }
    return set;
}

private size_t countOf(const string[] texts, string wanted) nothrow {
    size_t n;
    foreach (text; texts)
        n += text == wanted;
    return n;
}

int main() nothrow {
    alarm(120);
    enum pick = "P: Root <- 'a' / 'b' / 'c'";
    // Deterministic samples; weights shape the distribution; the stream reproduces exactly.
    auto heavy = generate!(pick, "Root", 600, "choice Root 0 weights 8 1 1")();
    auto again = generate!(pick, "Root", 600, "choice Root 0 weights 8 1 1")();
    assert(heavy.policyOk && heavy.accepted.texts == again.accepted.texts);
    const a = countOf(heavy.accepted.texts, "a"), b = countOf(heavy.accepted.texts, "b");
    assert(a > 420 && a < 540 && b > 20 && b < 110); // roughly 80% / 10%
    assert(heavy.metadata == again.metadata && heavy.metadata.length > 40);
    // Zero weights disable a branch; it never appears.
    auto disabled = generate!(pick, "Root", 200, "choice Root 0 weights 1 0 1")();
    assert(disabled.policyOk && countOf(disabled.accepted.texts, "b") == 0 && countOf(disabled
            .accepted.texts, "a") > 0);
    // Malformed policies are rejected with messages, and nothing is generated.
    static foreach (bad; [
        "choice Root 0 weights -1 2 3", "choice Root 0 weights nan 1 1",
        "choice Root 0 weights 0 0 0", "optional Root 0 probability 7",
        "attenuation 0", "zero-weights deny\nchoice Root 0 weights 1 0 1"
    ]) {
        {
            auto rejected = generate!(pick, "Root", 5, bad)();
            assert(!rejected.policyOk && rejected.problems.length && rejected.accepted.texts.length == 0);
        }
    }
    // Policies that do not bind to the grammar are reported, not ignored.
    auto unbound = generate!(pick, "Root", 5, "choice Missing 0 weights 1 1")();
    assert(!unbound.policyOk && unbound.problems.length == 1);
    auto wrongCount = generate!(pick, "Root", 5, "choice Root 0 weights 1 1")();
    assert(!wrongCount.policyOk && wrongCount.problems.length == 1);
    // Long-tail repetition from a histogram: mostly short with rare long runs.
    auto tail = generate!("T: Root <- 'x'* 'y'", "Root", 400, "repeat Root 0 histogram 0:6 1:6 2:6 40:1")();
    size_t longer, shortest;
    foreach (text; tail.accepted.texts) {
        longer += text.length >= 41;
        shortest += text.length <= 3;
    }
    assert(tail.policyOk && longer > 5 && longer < 60 && shortest > 300);
    // Optional probability.
    auto optional = generate!("O: Root <- 'a'? 'b'", "Root", 400, "optional Root 0 probability 0.9")();
    size_t withA;
    foreach (text; optional.accepted.texts)
        withA += text == "ab";
    assert(withA > 330 && withA < 395);
    auto never = generate!("O: Root <- 'a'? 'b'", "Root", 100, "optional Root 0 probability 0")();
    assert(countOf(never.accepted.texts, "b") == 100);
    // Recursion attenuation shortens recursive derivations without removing them.
    enum recursive = "R: Root <- 'x' Root / 'y'";
    auto plain = generate!(recursive, "Root", 300, "")();
    auto attenuated = generate!(recursive, "Root", 300, "attenuation 0.5")();
    size_t plainLength, attenuatedLength;
    foreach (text; plain.accepted.texts)
        plainLength += text.length;
    foreach (text; attenuated.accepted.texts)
        attenuatedLength += text.length;
    assert(plain.policyOk && attenuated.policyOk && attenuatedLength < plainLength);
    assert(attenuated.accepted.texts.length == 300);
    // Output-length budget is respected: oversize derivations are generation failures, never truncated samples.
    auto bounded = generate!("L: Root <- 'x'* 'y'", "Root", 50, "repeat Root 0 histogram 100:1", 1, 20)();
    assert(bounded.policyOk && bounded.accepted.texts.length == 0 && bounded.accepted
            .generationFailures > 0);
    printf("policy generation passed\n");
    return 0;
}
