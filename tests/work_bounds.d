/** W1 empirical check: the static work bounds dominate the work units actually charged.
    The bound is a proof obligation of npegged.work; enumeration over short inputs is additional evidence, not proof.
    Run through scripts/work-bounds-check.sh, which applies a process timeout. */
module tests.work_bounds;
import npegged.grammar;
import core.stdc.stdio : printf, fprintf, stderr;
import core.stdc.stdlib : abort;
import core.sys.posix.unistd : alarm;

private struct Case(string text) {
    struct Reference {
        mixin(grammar!(Memoization.selective)(text));
    }

    struct Direct {
        mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(text));
    }
}

/// Smallest step limit under which `parser` does not run out of work units: exactly the units it charges.
private size_t unitsCharged(alias parser)(string input) @nogc nothrow {
    size_t low, high = 1;
    ParseContext context;
    context.stepLimit = high;
    while (check!parser(context, input).status == Status.resourceLimit) {
        low = high;
        high *= 2;
        context.stepLimit = high;
        if (high > (size_t(1) << 30))
            abort();
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

private size_t boundOf(string text, string rule) nothrow {
    auto report = eligibilityReport!(Memoization.selective, void, ParserBackend.direct)(text);
    foreach (row; report.rules)
        if (row.name.length >= rule.length && row.name[$ - rule.length .. $] == rule) {
            size_t value;
            if (!row.workBound.length || row.workBound[0] < '0' || row.workBound[0] > '9')
                return size_t.max;
            foreach (c; row.workBound) {
                if (c < '0' || c > '9')
                    break;
                value = value * 10 + (c - '0');
            }
            return value;
        }
    return size_t.max;
}

private enum arithmetic = `W: Arith <- Term (('+' / '-') Term)* Term <- Fac (('*' / '/') Fac)* Fac <- '(' Arith ')' / [0-9]+`;
private enum expression = `W: Num <- [0-9]+ Expr <- Num ('+' Num)* Root <- Expr eoi`;
private enum nested = `W: Root <- Item* eoi Item <- 'a' / 'b' 'c'`;

private void check1(alias Reference, alias Direct)(string label, size_t bound, string input,
        ref size_t worstReference, ref size_t worstDirect) {
    const slack = bound * (input.length + 1);
    const reference = unitsCharged!Reference(input);
    const direct = unitsCharged!Direct(input);
    if (reference > slack || direct > slack) {
        fprintf(stderr,
                "work bound violated: %s bound=%zu*(n+1) n=%zu reference=%zu direct=%zu input=%.*s\n",
                (label ~ "\0").ptr, bound, input.length, reference, direct, cast(int)input.length, input
                    .ptr);
        abort();
    }
    if (reference * 1000 / slack > worstReference)
        worstReference = reference * 1000 / slack;
    if (direct * 1000 / slack > worstDirect)
        worstDirect = direct * 1000 / slack;
}

int main() {
    alarm(120);
    static foreach (index, text; [arithmetic, expression, nested]) {
        {
            alias C = Case!text;
            enum rule = index == 0 ? "Arith" : index == 1 ? "Root" : "Root";
            const bound = boundOf(text, rule);
            if (bound == size_t.max) {
                fprintf(stderr, "no bound for %s\n", (rule ~ "\0").ptr);
                return 1;
            }
            enum alphabet = index == 0 ? "1+*(" : index == 1 ? "1+2" : "abc";
            char[8] buffer;
            size_t worstReference, worstDirect, checked;
            foreach (length; 0 .. 8) {
                size_t combinations = 1;
                foreach (_; 0 .. length)
                    combinations *= alphabet.length;
                foreach (code; 0 .. combinations) {
                    size_t digits = code;
                    foreach (at; 0 .. length) {
                        buffer[at] = alphabet[digits % alphabet.length];
                        digits /= alphabet.length;
                    }
                    const input = cast(string)buffer[0 .. length];
                    static if (index == 0)
                        check1!(C.Reference.W.Arith, C.Direct.W.Arith)("arith", bound, input,
                                worstReference, worstDirect);
                    else static if (index == 1)
                        check1!(C.Reference.W.Root, C.Direct.W.Root)("expr", bound, input,
                                worstReference, worstDirect);
                    else
                        check1!(C.Reference.W.Root, C.Direct.W.Root)("nested", bound, input,
                                worstReference, worstDirect);
                    ++checked;
                }
            }
            printf("%s bound=%zu*(n+1) inputs=%zu worst units/bound: reference %zu/1000, direct %zu/1000\n",
                    (rule ~ "\0").ptr, bound, checked, worstReference, worstDirect);
        }
    }
    return 0;
}
