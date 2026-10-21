// W1 report: static work bound per rule of the benchmark grammars and its tightness (measured units / bound) on the
// benchmark inputs. Build with the library sources, benchmark/workload_grammars.d and benchmark/json_grammar.d.
import npegged.grammar;
import benchmark.workload_grammars : arithmeticGrammar, csvGrammar, numbersGrammar, pegGrammar;
import benchmark.json_grammar : jsonGrammar;
import core.stdc.stdio : printf;

private size_t unitsCharged(alias parser)(string input) @nogc nothrow {
    size_t low, high = 1;
    ParseContext context;
    context.stepLimit = high;
    while (check!parser(context, input).status == Status.resourceLimit) {
        low = high;
        high *= 2;
        context.stepLimit = high;
    }
    while (low + 1 < high) {
        const middle = low + (high - low) / 2;
        context.stepLimit = middle;
        if (check!parser(context, input).status == Status.resourceLimit)
            low = middle;
        else
            high = middle;
    }
    return high;
}

private struct Grammars {
    struct Arithmetic {
        mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(arithmeticGrammar));
    }

    struct Csv {
        mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(csvGrammar));
    }

    struct Numbers {
        mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(numbersGrammar));
    }

    struct Json {
        mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(jsonGrammar));
    }
}

private void rules(string label, string text) {
    auto report = eligibilityReport!(Memoization.selective, void, ParserBackend.direct)(text);
    foreach (row; report.rules)
        printf("%s %s bound=%s\n", (label ~ "\0").ptr, (row.name ~ "\0").ptr, (row.workBound ~ "\0")
                .ptr);
}

private void tight(string label, size_t bound, size_t units, size_t length) {
    printf("  %s n=%zu units=%zu bound=%zu tightness=%.3f\n", (label ~ "\0").ptr, length, units,
            bound * (length + 1), cast(double)units / (bound * (length + 1)));
}

int main() {
    rules("arithmetic", arithmeticGrammar);
    rules("csv", csvGrammar);
    rules("numbers", numbersGrammar);
    rules("peg", pegGrammar);
    rules("json", jsonGrammar);
    string flat = "x";
    foreach (i; 0 .. 512)
        flat ~= "+x";
    string nested = "x";
    foreach (i; 0 .. 64)
        nested = "(" ~ nested ~ ")";
    string csv = "a";
    foreach (i; 0 .. 512)
        csv ~= ",a";
    foreach (input; ["1 + 2 * (3 - 4)", flat, nested])
        printf("arithmetic units=%zu n=%zu\n",
                unitsCharged!(Grammars.Arithmetic.BenchArithmetic.opCall)(input), input.length);
    printf("csv units=%zu n=%zu\n", unitsCharged!(Grammars.Csv.BenchCSV.opCall)(csv), csv.length);
    printf("numbers scientific units=%zu\n", unitsCharged!(Grammars.Numbers.BenchNumbers.Scientific)(
            "123.456e+00"));
    return 0;
}
