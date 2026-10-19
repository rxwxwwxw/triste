module tests.acceptance_oracle;
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

/// Independent re-check: the parser accepts the whole text.
private bool accepted(alias parser)(string text) nothrow {
    ParseContext context;
    auto verdict = check!parser(context, text);
    return verdict.status == Status.ok && verdict.successful && verdict.end == text.length;
}

private AcceptedSet run(string definition, string rule, size_t count, size_t attempts = 10_000, ulong seed = 3)() nothrow {
    alias P = Compiled!definition;
    mixin("alias parser = P." ~ nameOf(definition) ~ "." ~ rule ~ ";");
    GeneratorOptions options;
    options.seed = seed;
    auto set = generateAccepted!parser(definition, rule, count, options, attempts);
    // The contract: everything reported valid is independently accepted by the reference parser.
    foreach (text; set.texts)
        assert(accepted!parser(text));
    return set;
}

int main() nothrow {
    alarm(90);
    // Candidate trap: ('a' / 'ab') 'c' proposes "abc", which the PEG rejects (the first alternative hides 'ab').
    auto trap = run!("T: Root <- ('a' / 'ab') 'c'", "Root", 30);
    assert(trap.status == Status.ok && trap.texts.length == 30 && !trap.exhausted);
    assert(trap.rejected > 0 && trap.proposed == trap.texts.length + trap.rejected);
    foreach (text; trap.texts)
        assert(text == "ac");
    // Impossible branch: 'a'* 'a' eoi never accepts anything, so the budget runs out and nothing is listed as valid.
    auto impossible = run!("I: Root <- 'a'* 'a' eoi", "Root", 5, 300);
    assert(impossible.exhausted && impossible.texts.length == 0 && impossible.rejected > 0);
    // Lookahead: candidates starting with 'b' are rejected, others accepted.
    auto guarded = run!("L: Root <- !'b' [a-c]+ eoi", "Root", 40, 10_000, 11);
    assert(guarded.texts.length == 40 && guarded.rejected > 0);
    foreach (text; guarded.texts)
        assert(text.length && text[0] != 'b');
    // A disjoint grammar: every proposal is accepted, no retries needed.
    auto disjoint = run!("D: Root <- ('a' / 'b' 'c' / 'd')+ eoi", "Root", 50);
    assert(disjoint.texts.length == 50 && disjoint.rejected == 0 && disjoint.proposed == 50);
    // Attempt budget: too small to reach the requested count is reported, not hidden.
    auto starved = run!("T: Root <- ('a' / 'ab') 'c'", "Root", 100, 5);
    assert(starved.exhausted && starved.texts.length < 100);
    // Unsupported constructs: generation failures are counted with reasons; no candidate is invented.
    auto action = run!("A: Root <- 'a'{act}", "Root", 3, 20);
    assert(action.exhausted && action.texts.length == 0 && action.generationFailures == 20 && action
            .proposed == 0);
    assert(action.failureReasons.length == 1);
    // Reproducible: same seed, same accepted samples; another seed differs.
    auto again = run!("T: Root <- ('a' / 'ab') 'c'", "Root", 30);
    assert(again.texts == trap.texts);
    auto mixed = run!("M: Root <- Num (',' Num)* eoi Num <- [0-9]+", "Root", 25);
    auto mixed2 = run!("M: Root <- Num (',' Num)* eoi Num <- [0-9]+", "Root", 25, 10_000, 4);
    assert(mixed.texts.length == 25 && mixed.texts != mixed2.texts);
    // Errors.
    alias Q = Compiled!"E: Root <- 'a'";
    assert(generateAccepted!(Q.E.Root)("Broken:", "Root", 1).status == Status.invalidInput);
    assert(generateAccepted!(Q.E.Root)("E: Root <- 'a'", "Missing", 1).status == Status.invalidInput);
    printf("acceptance oracle passed\n");
    return 0;
}
