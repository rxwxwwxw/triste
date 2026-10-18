module tests.rule_effects;
import npegged.grammar;
import core.memory : GC;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private void expect(scope ref EligibilityResult report, size_t index, bool known, bool actionful) nothrow {
    assert(report.status == Status.ok);
    assert(report.rules[index].known == known);
    assert(report.rules[index].actionful == actionful);
}

int main() nothrow {
    alarm(45);
    auto mixed = eligibilityReport!(Memoization.selective, void, ParserBackend.direct)(`
MixedEffects:
    Root <- Pure eoi
    Pure <- 'a' 'b'?
    Opaque <- external
    CallOpaque <- 'x' Opaque
    Effect <- Pure{effect}
    CallEffect <- &Effect / Pure
    CycleA <- 'a' CycleB / Opaque
    CycleB <- 'b' CycleA / 'b'
    PureA <- 'a' PureB / 'a'
    PureB <- 'b' PureA / 'b'
    Left <- Left 'a' / Pure
    Nested <- (CallOpaque{inner}){outer}
    Literal <- 'action!('
`);
    version (EligibilityGCStress)
        GC.collect();
    expect(mixed, 0, true, false);
    expect(mixed, 1, true, false);
    expect(mixed, 2, false, true);
    expect(mixed, 3, false, true);
    expect(mixed, 4, true, true);
    expect(mixed, 5, true, true);
    expect(mixed, 6, false, true);
    expect(mixed, 7, false, true);
    expect(mixed, 8, true, false);
    expect(mixed, 9, true, false);
    expect(mixed, 10, true, false);
    expect(mixed, 11, false, true);
    expect(mixed, 12, true, false);
    assert(mixed.conservative);
    // Facts are descriptive: the existing whole-grammar barriers still apply.
    assert(!mixed.rules[1].scalarEligible && mixed.rules[1].memoized);
    printf("%.*s\n", cast(int)mixed.report.length, mixed.report.ptr);
    auto parameters = eligibilityReport!(Memoization.selective, void, ParserBackend.direct)(`
Parameters:
    Root <- Param!('a')
    Param(P) <- P
    Pure <- 'x'
`);
    expect(parameters, 0, false, true);
    expect(parameters, 1, false, true);
    expect(parameters, 2, true, false);
    auto grammarParameters = eligibilityReport("Generic(T=identifier): Root <- 'x' Other <- T");
    expect(grammarParameters, 0, false, true);
    expect(grammarParameters, 1, false, true);
    auto literal = eligibilityReport!(Memoization.selective, void, ParserBackend.direct)("Literal: Root <- 'action!('");
    expect(literal, 0, true, false);
    assert(literal.actionRules.length == 1 && !literal.rules[0].scalarEligible);
    printf("rule effects oracle passed\n");
    return 0;
}
