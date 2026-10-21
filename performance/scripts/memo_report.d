// P7: explain memoization per rule and compare the three policies on representative inputs.
// Build with -d-version=NPeggedRuleMetrics (combinator backend, so every rule call is counted):
//   ldc2 -d-version=NPeggedRuleMetrics -Isrc -I. <src/npegged/*.d> benchmark/workload_grammars.d benchmark/json_grammar.d \
//        benchmark/handwritten/*.d performance/scripts/memo_report.d
import npegged.grammar;
import benchmark.workload_grammars : arithmeticGrammar, csvGrammar, numbersGrammar, leftExprGrammar;
import benchmark.json_grammar : jsonGrammar;
import core.stdc.stdio : printf;

template Policies(string text) {
    struct No {
        mixin(grammar!(Memoization.no)(text));
    }

    struct Selective {
        mixin(grammar!(Memoization.selective)(text));
    }

    struct Yes {
        mixin(grammar!(Memoization.yes)(text));
    }
}

private size_t unitsCharged(alias parser)(string input) @nogc nothrow {
    size_t low, high = 1;
    ParseContext context;
    context.stepLimit = high;
    while (check!parser(context, input).status == Status.resourceLimit) {
        low = high;
        high *= 2;
        context.stepLimit = high;
        if (high > (size_t(1) << 28))
            return size_t.max;
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

private void explain(alias Yes, alias No, alias Selective, string label)(string text, string input) {
    version (NPeggedRuleMetrics) {
        auto policy = eligibilityReport!(Memoization.selective)(text);
        RuleStats[64] rows;
        RuleReport report;
        report.rows = rows[];
        ParseContext context;
        context.ruleReport = &report;
        const full = check!Yes(context, input);
        printf("### %s (n=%zu, accepted=%d)\n\n| rule | calls | memo hits | hit rate | left-recursive | selective memoizes | recommendation |\n|---|---|---|---|---|---|---|\n",
                (label ~ "\0").ptr, input.length, full.successful && full.end == input.length);
        foreach (i; 0 .. report.length) {
            const row = report.rows[i];
            bool leftRecursive, memoized;
            foreach (rule; policy.rules)
                if (rule.name == row.rule) {
                    leftRecursive = rule.leftRecursive;
                    memoized = rule.memoized;
                }
            const rate = row.calls ? 100.0 * row.memoHits / row.calls : 0.0;
            const advice = leftRecursive ? "memoize (required by seed growth)" : row.memoHits ? "memoize: repeated (rule, position) calls" : memoized
                ? "selective already memoizes; no repeats seen on this input" : "leave unmemoized";
            printf("| %s | %llu | %llu | %.1f%% | %s | %s | %s |\n", (row.rule ~ "\0").ptr, row.calls, row.memoHits,
                    rate, leftRecursive ? "yes".ptr : "no".ptr, memoized ? "yes".ptr : "no".ptr, (advice ~ "\0").ptr);
        }
        ParseContext plain;
        const no = check!No(plain, input);
        const selective = check!Selective(plain, input);
        printf("\n| policy | verdict | arena bytes | work units |\n|---|---|---|---|\n");
        printf("| no | %d | %zu | %zu |\n", no.successful, no.arena.used, unitsCharged!No(input));
        printf("| selective | %d | %zu | %zu |\n", selective.successful, selective.arena.used, unitsCharged!Selective(input));
        printf("| yes | %d | %zu | %zu |\n\n", full.successful, full.arena.used, unitsCharged!Yes(input));
    }
}

int main() {
    version (NPeggedRuleMetrics) {
        string flat = "1";
        foreach (i; 0 .. 128)
            flat ~= " + 2 * (3 - 4)";
        alias A = Policies!arithmeticGrammar;
        explain!(A.Yes.BenchArithmetic, A.No.BenchArithmetic, A.Selective.BenchArithmetic, "Arithmetic")(arithmeticGrammar, flat);
        alias L = Policies!leftExprGrammar;
        explain!(L.Yes.BenchLeftExpr, L.No.BenchLeftExpr, L.Selective.BenchLeftExpr, "LeftExpr")(leftExprGrammar, "1 + 2 * (3 - 4) + (5 - 6) * 7 - 8");
        alias C = Policies!csvGrammar;
        explain!(C.Yes.BenchCSV, C.No.BenchCSV, C.Selective.BenchCSV, "CSV")(csvGrammar, "a,b,\"c\"\"d\"\n1,2,3\n");
        alias J = Policies!jsonGrammar;
        explain!(J.Yes.JSON, J.No.JSON, J.Selective.JSON, "JSON")(jsonGrammar, `{"a": [1, 2, {"b": null}], "c": "d", "e": true}`);
    } else
        printf("build with -d-version=NPeggedRuleMetrics\n");
    return 0;
}
