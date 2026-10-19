module tests.prefix_discrimination;

import npegged.analysis;
import npegged.grammar;
import core.memory : GC;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private ptrdiff_t indexOf(string input, string needle) @nogc nothrow pure {
    if (needle.length > input.length)
        return -1;
    foreach (i; 0 .. input.length - needle.length + 1)
        if (input[i .. i + needle.length] == needle)
            return cast(ptrdiff_t)i;
    return -1;
}

int main() nothrow {
    alarm(45);

    // 1. Fixture "ab" / "ac"
    auto r1 = prefixDiscriminationReport("DisjointChoice: Root <- 'ab' / 'ac'");
    assert(r1.status == Status.ok);
    assert(r1.choices.length == 1);
    assert(r1.choices[0].hasOverlap);
    assert(r1.choices[0].pairs.length == 1);
    assert(r1.choices[0].pairs[0].kind == DiscriminationKind.disjointTails);
    assert(r1.choices[0].pairs[0].commonPrefix == "a");
    assert(r1.choices[0].pairs[0].commonPrefixLength == 1);
    assert(r1.choices[0].pairs[0].discriminatingDepth == 2);

    // 2. Fixture "a" / "ab" (ordered choice shadowing)
    auto r2 = prefixDiscriminationReport("ShadowedChoice: Root <- 'a' / 'ab'");
    assert(r2.status == Status.ok);
    assert(r2.choices.length == 1);
    assert(r2.choices[0].hasOverlap);
    assert(r2.choices[0].pairs.length == 1);
    assert(r2.choices[0].pairs[0].kind == DiscriminationKind.shadowed);
    assert(r2.choices[0].pairs[0].commonPrefix == "a");
    assert(r2.choices[0].pairs[0].commonPrefixLength == 1);
    assert(r2.choices[0].pairs[0].discriminatingDepth == 1);

    // 3. Fixture "a" eoi / "ab" (EOF guard)
    auto r3 = prefixDiscriminationReport("GuardedEoi: Root <- 'a' eoi / 'ab'");
    assert(r3.status == Status.ok);
    assert(r3.choices.length == 1);
    assert(r3.choices[0].hasOverlap);
    assert(r3.choices[0].pairs.length == 1);
    assert(r3.choices[0].pairs[0].kind == DiscriminationKind.guarded);
    assert(r3.choices[0].pairs[0].commonPrefix == "a");
    assert(r3.choices[0].pairs[0].commonPrefixLength == 1);

    // 4. Fixture predicates
    auto r4 = prefixDiscriminationReport("GuardedPred: Root <- &'ax' 'a' / 'ab'");
    assert(r4.status == Status.ok);
    assert(r4.choices.length == 1);
    assert(r4.choices[0].hasOverlap);
    assert(r4.choices[0].pairs.length == 1);
    assert(r4.choices[0].pairs[0].kind == DiscriminationKind.guarded);

    auto r5 = prefixDiscriminationReport("GuardedNegPred: Root <- !'b' 'a' / 'ab'");
    assert(r5.status == Status.ok);
    assert(r5.choices.length == 1);
    assert(r5.choices[0].hasOverlap);
    assert(r5.choices[0].pairs.length == 1);
    assert(r5.choices[0].pairs[0].kind == DiscriminationKind.guarded);

    // 5. Fixture "a" / "b" (disjoint FIRST)
    auto r6 = prefixDiscriminationReport("DisjointFirst: Root <- 'a' / 'b'");
    assert(r6.status == Status.ok);
    assert(r6.choices.length == 1);
    assert(!r6.choices[0].hasOverlap);
    assert(r6.choices[0].pairs.length == 1);
    assert(r6.choices[0].pairs[0].kind == DiscriminationKind.disjointFirst);

    // 6. Multi-branch choice: "ab" / "ac" / "ad"
    auto r7 = prefixDiscriminationReport("MultiChoice: Root <- 'ab' / 'ac' / 'ad'");
    assert(r7.status == Status.ok);
    assert(r7.choices.length == 1);
    assert(r7.choices[0].hasOverlap);
    assert(r7.choices[0].pairs.length == 3);
    assert(r7.choices[0].pairs[0].kind == DiscriminationKind.disjointTails);
    assert(r7.choices[0].pairs[1].kind == DiscriminationKind.disjointTails);
    assert(r7.choices[0].pairs[2].kind == DiscriminationKind.disjointTails);

    // 7. Text and JSON reports
    auto textReport = prefixDiscriminationReport("MultiChoice: Root <- 'ab' / 'ac' / 'ad'", EligibilityFormat
            .text);
    assert(textReport.status == Status.ok);
    assert(textReport.report.length > 0);

    // Deterministic reporting check
    auto repeated = prefixDiscriminationReport("DisjointChoice: Root <- 'ab' / 'ac'");
    assert(r1.report == repeated.report);

    // Invalid input error handling
    auto invalid = prefixDiscriminationReport("Invalid: Root <-");
    assert(invalid.status == Status.invalidInput);

    // F3: FIRST/FIRST and FIRST/FOLLOW diagnostics.
    assert(r1.choices[0].pairs[0].firstFirstConflict && !r1.choices[0].pairs[0].definite);
    assert(r1.choices[0].pairs[0].overlapBytes == 1);
    assert(r2.choices[0].pairs[0].firstFirstConflict && r2.choices[0].pairs[0].definite);
    assert(!r6.choices[0].pairs[0].firstFirstConflict && r6.choices[0].pairs[0].overlapBytes == 0);
    assert(r3.choices[0].pairs[0].firstFirstConflict && !r3.choices[0].pairs[0].definite);
    assert(r6.choices[0].followKnown && !r6.choices[0].firstFollowConflict);
    assert(r6.choices[0].ruleName == "Root");
    auto longer = prefixDiscriminationReport("Rev: Root <- 'ab' / 'a'");
    assert(longer.choices[0].pairs[0].kind != DiscriminationKind.shadowed);
    assert(longer.choices[0].pairs[0].firstFirstConflict && !longer.choices[0].pairs[0].definite);
    auto conflict = prefixDiscriminationReport("FF: Root <- Opt 'a' Opt <- 'a' / eps");
    assert(conflict.status == Status.ok);
    bool sawConflict;
    foreach (choice; conflict.choices)
        if (choice.ruleName == "Opt")
            sawConflict = choice.followKnown && choice.firstFollowConflict;
    assert(sawConflict);
    auto clear = prefixDiscriminationReport("FC: Root <- Opt 'b' Opt <- 'a' / eps");
    foreach (choice; clear.choices)
        if (choice.ruleName == "Opt")
            assert(choice.followKnown && !choice.firstFollowConflict);
    auto predicateRule = prefixDiscriminationReport("FP: Root <- Opt !'x' 'a' Opt <- 'a' / eps");
    foreach (choice; predicateRule.choices)
        if (choice.ruleName == "Opt")
            assert(!choice.followKnown && !choice.firstFollowConflict);
    auto text2 = prefixDiscriminationReport("FF: Root <- Opt 'a' Opt <- 'a' / eps", EligibilityFormat
            .text);
    assert(text2.report.length && text2.report != conflict.report);

    // B4: BITES disjointness on top of the FIRST/FOLLOW diagnostics.
    assert(r6.choices[0].pairs[0].bites == "proven-disjoint" && !r6.choices[0].pairs[0]
            .bitesImprovesFirst);
    assert(r6.choices[0].pairs[0].noHidingProven && r6.choices[0].bitesAllDisjoint && r6.choices[0]
            .noHidingProven);
    auto guardedBites = prefixDiscriminationReport("GB: Root <- !'abc' [a-z]+ / 'abc' [a-z]*");
    assert(guardedBites.status == Status.ok && guardedBites.choices.length == 1);
    assert(guardedBites.choices[0].pairs[0].firstFirstConflict); // FIRST overlaps...
    assert(guardedBites.choices[0].pairs[0].bites == "proven-disjoint"); // ...BITES does not
    assert(guardedBites.choices[0].pairs[0].bitesImprovesFirst && guardedBites.choices[0].pairs[0]
            .noHidingProven);
    auto capture = prefixDiscriminationReport("PC: Root <- ('a' / 'aa') 'b'");
    assert(capture.choices.length == 1 && capture.choices[0].pairs[0].bites == "possible-overlap");
    assert(capture.choices[0].pairs[0].bitesWitness == "aa" && !capture.choices[0].pairs[0]
            .noHidingProven);
    assert(!capture.choices[0].bitesAllDisjoint && !capture.choices[0].noHidingProven);
    assert(r2.choices[0].pairs[0].bites == "possible-overlap" && r2.choices[0].pairs[0].definite);
    auto nullableArm = prefixDiscriminationReport("NA: Root <- 'a' / eps");
    assert(nullableArm.choices[0].pairs[0].bites == "proven-disjoint");
    assert(!nullableArm.choices[0].pairs[0].noHidingProven && !nullableArm.choices[0].noHidingProven);
    auto opaque = prefixDiscriminationReport("UK: Root <- 'a' / Opaque Opaque <- external");
    assert(opaque.status == Status.ok && opaque.choices[0].pairs[0].bites == "unknown");
    assert(!opaque.choices[0].pairs[0].noHidingProven);
    auto recursive = prefixDiscriminationReport("RC: Root <- Root 'a' / 'a'");
    assert(recursive.choices[0].pairs[0].bites == "unknown" || recursive.choices[0].pairs[0].bites == "possible-overlap");
    auto bitesText = prefixDiscriminationReport("GB: Root <- !'abc' [a-z]+ / 'abc' [a-z]*", EligibilityFormat
            .text);
    assert(indexOf(bitesText.report, "improves on FIRST") >= 0 && indexOf(bitesText.report, "Prop. 5") >= 0);

    // B7 (opt-in regular SUCC): a guarded alternative becomes provably disjoint from the sequence it excludes.
    auto narrow = prefixDiscriminationReport("RS: Root <- !('a' 'b') 'a' / 'ab'");
    assert(narrow.choices[0].pairs[0].bites == "possible-overlap");
    auto regular = prefixDiscriminationReport("RS: Root <- !('a' 'b') 'a' / 'ab'", EligibilityFormat
            .json, true);
    assert(regular.choices[0].pairs[0].bites == "proven-disjoint" && regular.choices[0].pairs[0]
            .bitesImprovesFirst);
    auto regularUnchanged = prefixDiscriminationReport("PC: Root <- ('a' / 'aa') 'b'", EligibilityFormat
            .json, true);
    assert(regularUnchanged.choices[0].pairs[0].bites == "possible-overlap");

    // Print JSON reports for script verification
    printf("%.*s\n", cast(int)r1.report.length, r1.report.ptr);
    printf("%.*s\n", cast(int)r2.report.length, r2.report.ptr);
    printf("%.*s\n", cast(int)r3.report.length, r3.report.ptr);
    printf("%.*s\n", cast(int)r4.report.length, r4.report.ptr);
    printf("%.*s\n", cast(int)r5.report.length, r5.report.ptr);
    printf("%.*s\n", cast(int)r6.report.length, r6.report.ptr);
    printf("%.*s\n", cast(int)r7.report.length, r7.report.ptr);

    printf("prefix discrimination oracle passed\n");
    return 0;
}
