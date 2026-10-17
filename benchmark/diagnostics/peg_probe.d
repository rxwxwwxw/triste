/** Diagnostic stage timing is deliberately separate from end-to-end timing. */
module benchmark.diagnostics.peg_probe;
import npegged.grammar;

// Read the existing grammar verbatim without instantiating the unrelated benchmark
// grammars and a second PEG parser in this focused diagnostic binary.
private enum workloadSource = import("benchmark/workload_grammars.d");
private size_t find(string text, string needle, size_t start = 0) @nogc nothrow pure {
    foreach (i; start .. text.length)
        if (text.length - i >= needle.length && text[i .. i + needle.length] == needle)
            return i;
    assert(0, "Missing benchmark PEG grammar delimiter");
}

private enum pegStart = find(workloadSource, "enum pegGrammar = `") + "enum pegGrammar = `".length;
private enum pegEnd = find(workloadSource, "`;", pegStart);
private enum pegGrammar = workloadSource[pegStart .. pegEnd];
import benchmark.measurement : consume, opaqueInput;
import core.stdc.stdio : printf, fprintf, stderr;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;

version (NPeggedDirect)
    enum backend = ParserBackend.direct;
else
    enum backend = ParserBackend.combinators;
version (NPeggedFullMemo)
    enum memoization = Memoization.yes;
else
    enum memoization = Memoization.selective;
mixin(grammar!(memoization, void, backend)(pegGrammar));

private ulong now() @nogc nothrow {
    timespec value;
    return clock_gettime(CLOCK_MONOTONIC, &value) ? 0 : cast(ulong)value.tv_sec * 1_000_000_000 + value
        .tv_nsec;
}

private immutable string[6] observedRules = [
    "BenchPEG.TopBoundary", "BenchPEG.SequenceBoundary", "BenchPEG.Sp", "BenchPEG.Prefix",
    "BenchPEG.Primary", "BenchPEG.Definition"
];
private void countRule(string name, size_t position, bool accepted, void* user) @nogc nothrow {
    auto counts = cast(ulong*)user;
    foreach (i, rule; observedRules)
        if (name == rule)
            ++counts[i];
}

int main() @nogc nothrow {
    char[139] deep;
    deep[0 .. 8] = "G: R <- ";
    deep[8 .. 72] = '(';
    deep[72 .. 75] = "'x'";
    deep[75 .. $] = ')';
    string[4] inputs = ["G: A <-- / []**", "G: A <- ('a'", "G: A <- 'a' )", cast(string)deep[]];
    static immutable string[4] names = ["Permissive", "Truncated", "Trailing", "Deep"];
    printf("case,cohort,sample,iterations,total_ns,setup_ns,body_ns,teardown_ns\n");
    foreach (i, raw; inputs) {
        const input = opaqueInput(raw);
        foreach (sample; 0 .. 7) {
            enum iterations = 2000;
            ulong setup, body, teardown;
            auto start = now();
            foreach (_; 0 .. iterations) {
                ParseContext context;
                auto result = check!(BenchPEG.opCall)(context, input);
                consume(result.successful, result.end, 0, result.status);
                if (result.status != (i == 0 || i == 3 ? Status.ok : Status.mismatch))
                    return 2;
            }
            auto stop = now();
            printf("%.*s,end-to-end,%u,%u,%llu,0,0,0\n", cast(int)names[i].length, names[i].ptr,
                    cast(uint)sample, iterations, stop - start);
            start = now();
            foreach (_; 0 .. iterations) {
                auto before = now();
                ulong prepared, parsed;
                {
                    Arena arena;
                    State!(false, 1) state;
                    state.arena = &arena;
                    state.input = input;
                    prepared = now();
                    auto result = state.finish(BenchPEG.opCall(state, 0));
                    parsed = now();
                    consume(result.successful, result.end, 0, state.status);
                }
                auto disposed = now();
                setup += prepared - before;
                body += parsed - prepared;
                teardown += disposed - parsed;
            }
            stop = now();
            printf("%.*s,stages,%u,%u,%llu,%llu,%llu,%llu\n", cast(int)names[i].length,
                    names[i].ptr, cast(uint)sample, iterations, stop - start, setup, body, teardown);
        }
        ulong[observedRules.length] counts;
        ParseContext diagnostic;
        diagnostic.trace = &countRule;
        diagnostic.userData = counts.ptr;
        auto traced = check!(BenchPEG.opCall)(diagnostic, input);
        consume(traced.successful, traced.end, 0, traced.status);
        foreach (j, rule; observedRules)
            fprintf(stderr, "trace,%.*s,%.*s,%llu\n", cast(int)names[i].length, names[i].ptr,
                    cast(int)rule.length, rule.ptr, counts[j]);
    }
    return 0;
}
