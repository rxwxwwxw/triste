module tests.eligibility_report;
import npegged.grammar;
import core.memory : GC;
import npegged.io : File;
import core.stdc.stdio : printf, snprintf;
import core.stdc.stdlib : getenv;
import core.stdc.string : strlen;
import core.sys.posix.unistd : alarm;

private enum definitions = [
    `Eligibility: Root <- Pure eoi Pure <- 'a' 'b'? Rec <- Rec 'n' / 'n' Effect <- 'x'{effect} Opaque <- external`,
    `Pure: Root <- Leaf+ eoi Leaf <- [a-z] Ignored <: ' '?`,
    `Rec: Root <- Expr eoi Expr <- Expr '+' Leaf / Leaf Leaf <- [0-9]+`,
    `Params(T=identifier): Root <- T`, `Unicode: Root <- 'é' / '"' / '\n'`, `Empty: Root <- eps`
];
private uint selected(string name) @nogc nothrow pure {
    return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : name.length >= 5
        && name[$ - 5 .. $] == ".Leaf" ? 1 : uint.max;
}

private void inspect(Memoization memo, ParserBackend backend, bool records)(string directory) nothrow {
    static if (records)
        alias selector = selected;
    else
        alias selector = void;
    foreach (index, definition; definitions) {
        auto generated = generate!(memo, selector, backend)(definition);
        assert(generated.status == Status.ok);
        char[80] filename;
        const count = snprintf(filename.ptr, filename.length, "/case-%u-%u-%u-%u.d",
                cast(uint)index, cast(uint)backend, cast(uint)memo, cast(uint)records);
        assert(count > 0 && count < filename.length);
        auto output = File.open(directory ~ filename[0 .. count].idup, true);
        assert(output.write(generated.source) == Status.ok);
        version (EligibilityBaseline) {
        } else {
            auto report = eligibilityReport!(memo, selector, backend)(definition);
            auto repeated = eligibilityReport!(memo, selector, backend)(definition);
            auto text = eligibilityReport!(memo, selector, backend)(definition, EligibilityFormat
                    .text);
            version (EligibilityGCStress)
                GC.collect(); // Returned rows and strings survive a subsequent collection.
            assert(report.status == Status.ok && text.status == Status.ok);
            assert(report.rules == text.rules);
            assert(text.report == eligibilityReport!(memo, selector, backend)(definition,
                    EligibilityFormat.text).report);
            assert(report.report == repeated.report && report.rules == repeated.rules);
            assert(report.rules.length && report.rules[0].selectorConfigured == records);
            assert(report.backend == backend && report.memoPolicy == memo);
            foreach (row; report.rules) {
                const hasDirect = generated.source.indexOf("return defined!(_direct_"
                        ~ row.name[row.name.indexOf(".") + 1 .. $] ~ "!(CT, Check),") >= 0;
                assert(hasDirect == (row.directRecognition || row.directRecords));
            }
            if (index == 0) {
                assert(report.conservative && report.unknownEvidence.length);
                assert(report.actionRules == ["Eligibility.Effect"]);
                assert(report.rules[2].leftRecursive && report.rules[2].memoized == (memo != Memoization
                        .no));
                assert(!report.rules[1].scalarEligible && !report.rules[1].directRecognition);
            }
            if (index == 1 && backend == ParserBackend.direct && memo != Memoization.yes)
                assert(report.rules[1].scalarEligible);
            printf("%.*s\n", cast(int)report.report.length, report.report.ptr);
        }
    }
}

// Cold fixture helper; source diagnostics do not depend on Phobos.
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
    auto folder = getenv("H01_OUTPUT_DIR");
    assert(folder !is null);
    auto directory = cast(string)folder[0 .. strlen(folder)];
    static foreach (memo; [Memoization.no, Memoization.yes, Memoization.selective])
        static foreach (backend; [ParserBackend.combinators, ParserBackend.direct])
            static foreach (records; [false, true])
                inspect!(memo, backend, records)(directory);
    version (EligibilityBaseline) {
    } else {
        auto invalid = eligibilityReport("Broken:");
        assert(invalid.status == Status.invalidInput && !invalid.report.length && !invalid.rules
                .length);
        assert(invalid.diagnostic.message.length);
    }
    return 0;
}
