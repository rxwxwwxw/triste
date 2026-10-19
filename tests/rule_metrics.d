module tests.rule_metrics;
import npegged.grammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

struct Suite(Memoization memo) {
    mixin(grammar!(memo, void, ParserBackend.combinators)(`
RM:
    Root <- (Pair / Single) eoi
    Pair <- Leaf ',' Leaf
    Single <- Leaf
    Leaf <- [a-z]+
`));
}

int main() nothrow {
    alarm(30);
    version (NPeggedRuleMetrics) {
        // Choice rollback: Pair fails after its first Leaf, then Single succeeds.
        RuleStats[8] rows;
        RuleReport report;
        report.rows = rows[];
        ParseContext context;
        context.ruleReport = &report;
        auto result = check!(Suite!(Memoization.yes).RM)(context, "abc");
        assert(result.successful);
        ulong calls(string name) nothrow {
            foreach (i; 0 .. report.length)
                if (report.rows[i].rule == name)
                    return report.rows[i].calls;
            return 0;
        }

        ulong failures(string name) nothrow {
            foreach (i; 0 .. report.length)
                if (report.rows[i].rule == name)
                    return report.rows[i].failures;
            return 0;
        }

        assert(calls("RM.Pair") == 1 && failures("RM.Pair") == 1);
        assert(calls("RM.Single") == 1 && failures("RM.Single") == 0);
        assert(calls("RM.Leaf") >= 1 && calls("RM.Root") == 1);
        ulong sum;
        foreach (i; 0 .. report.length)
            sum += report.rows[i].calls;
        assert(sum == report.total.calls && !report.truncated);
        // Failed lookahead-free input: nothing matches.
        RuleReport failing;
        failing.rows = rows[];
        context.ruleReport = &failing;
        context.stepLimit = 10_000_000;
        auto bad = check!(Suite!(Memoization.yes).RM)(context, "1");
        assert(!bad.successful && failing.total.successes == 0);
        // Without a sink nothing is recorded and behavior is unchanged.
        context.ruleReport = null;
        assert(check!(Suite!(Memoization.no).RM)(context, "a,b").successful);
        auto json = report.json();
        assert(json.length > 40 && json == report.json());
        printf("rule metrics passed\n");
    } else
        printf("rule metrics skipped (build with -version=NPeggedRuleMetrics)\n");
    return 0;
}
