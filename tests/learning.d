module tests.learning;
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

private bool has(string text, string needle) @nogc nothrow pure {
    if (needle.length > text.length)
        return false;
    foreach (i; 0 .. text.length - needle.length + 1)
        if (text[i .. i + needle.length] == needle)
            return true;
    return false;
}

private ParseTree act(bool CT)(ref State!CT state, ParseTree tree) @nogc nothrow {
    return tree;
}

private enum grammarText = "M: Root <- Item (',' Item)* eoi Item <- 'a' / 'bb' / 'c' 'd'? / [0-9]+";

private string[] corpus(string policy, size_t count, ulong seed) nothrow {
    alias P = Compiled!grammarText;
    GeneratorOptions options;
    options.seed = seed;
    auto set = generateWithPolicy!(P.M.Root)(grammarText, "Root", count, policy, options);
    assert(set.policyOk && set.accepted.texts.length == count);
    return set.accepted.texts;
}

int main() nothrow {
    alarm(120);
    alias P = Compiled!grammarText;
    // Synthetic "sample" corpus with known weights: 70% 'a', 10% 'bb', 10% 'c', 10% digits; 'd' after 'c' 25%.
    enum truth = "choice Item 0 weights 70 10 10 10\noptional Item 0 probability 0.25\nrepeat Root 0 histogram 0:4 1:3 2:2 5:1\n";
    auto sample = corpus(truth, 3000, 17);
    auto holdout = corpus(truth, 1000, 99);
    auto model = learnPolicy!(P.M.Root)(grammarText, "Root", sample);
    assert(model.status == Status.ok && model.accepted == 3000 && model.invalid == 0 && model
            .unattributable == 0);
    // Learned shares are close to the true weights (marginal statistics, large sample).
    assert(model.choiceShares.length >= 4);
    size_t aShare;
    foreach (share; model.choiceShares)
        if (share > 600 && share < 800)
            aShare = share;
    assert(aShare > 640 && aShare < 760);
    assert(has(model.provenance, "marginal statistics") && has(model.policyText, "choice Item 0 weights"));
    // The learned policy is valid and replayable: generate from it, and compare to the holdout.
    auto regenerated = generateWithPolicy!(P.M.Root)(grammarText, "Root", 1000, model.policyText);
    assert(regenerated.policyOk && regenerated.accepted.texts.length == 1000);
    auto learned = compareToHoldout!(P.M.Root)(grammarText, "Root", holdout, regenerated.accepted
            .texts);
    auto defaults = generateWithPolicy!(P.M.Root)(grammarText, "Root", 1000, "");
    auto baseline = compareToHoldout!(P.M.Root)(grammarText, "Root", holdout, defaults.accepted.texts);
    assert(learned.status == Status.ok && learned.choiceShareDistance < baseline.choiceShareDistance);
    assert(learned.choiceShareDistance < 60 && learned.lengthDistance < baseline.lengthDistance + 1);
    // Invalid and unattributable inputs are ignored with correct counts, and teach nothing.
    string[] noisy = sample[0 .. 500];
    noisy ~= "zzz";
    noisy ~= "a,";
    noisy ~= "";
    noisy ~= "\xff\xfe";
    auto withNoise = learnPolicy!(P.M.Root)(grammarText, "Root", noisy);
    auto clean = learnPolicy!(P.M.Root)(grammarText, "Root", sample[0 .. 500]);
    assert(withNoise.accepted == 500 && withNoise.invalid == 4
            && withNoise.policyText[withNoise.policyText.length - 1] == '\n');
    assert(withNoise.choiceShares == clean.choiceShares);
    // Replay reproducibility: the same corpus gives the same model, and order does not matter.
    auto again = learnPolicy!(P.M.Root)(grammarText, "Root", sample);
    string[] reversed;
    foreach_reverse (text; sample)
        reversed ~= text;
    auto flipped = learnPolicy!(P.M.Root)(grammarText, "Root", reversed);
    assert(again.policyText == model.policyText && flipped.policyText == model.policyText);
    // Actions: the derivation cannot follow them, so those inputs are counted and ignored (no side effects are run).
    alias Act = Compiled!"A: Root <- 'a'{act} / 'b'";
    auto actions = learnPolicy!(Act.A.Root)("A: Root <- 'a'{act} / 'b'", "Root", [
        "a", "b", "a", "x"
    ]);
    assert(actions.status == Status.ok && actions.invalid == 1 && actions.unattributable == 3 && actions
            .accepted == 0);
    // Errors and corpus-free behavior.
    assert(learnPolicy!(P.M.Root)("Broken:", "Root", sample).status == Status.invalidInput);
    assert(learnPolicy!(P.M.Root)(grammarText, "Missing", sample).status == Status.invalidInput);
    auto empty = learnPolicy!(P.M.Root)(grammarText, "Root", []);
    assert(empty.status == Status.ok && empty.accepted == 0 && parseUsable(empty.policyText));
    printf("learning passed\n");
    return 0;
}

/// The learned text must be accepted by the policy parser (smoothed, so valid even with no data).
private bool parseUsable(string text) nothrow {
    alias P = Compiled!grammarText;
    auto generated = generateWithPolicy!(P.M.Root)(grammarText, "Root", 3, text);
    return generated.policyOk;
}
