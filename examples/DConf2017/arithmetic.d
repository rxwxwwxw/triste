// Derived from Pegged (Boost 1.0).
import npegged.grammar;

mixin(grammar(`
Arithmetic:
    Term     < Factor (Add / Sub)*
    Add      < "+" Factor
    Sub      < "-" Factor
    Factor   < Primary (Mul / Div)*
    Mul      < "*" Primary
    Div      < "/" Primary
    Primary  < Parens / Neg / Number / Variable
    Parens   < :"(" Term :")"
    Neg      < "-" Primary
    Number   < ~([0-9]+)
    Variable <- identifier
`));

int main() @nogc nothrow {
    enum parseTree = Arithmetic("1 + 2 - (3 * 2 - 5) * 6");

    float value(const ParseTree p) @nogc nothrow {
        switch (p.name) {
        case "Arithmetic", "Arithmetic.Primary", "Arithmetic.Parens", "Arithmetic.Add",
                "Arithmetic.Mul":
                return value(p.children[0]);
        case "Arithmetic.Sub", "Arithmetic.Neg":
            return -value(p.children[0]);
        case "Arithmetic.Term":
            float v = 0.0;
            foreach (child; p.children)
                v += value(child);
            return v;
        case "Arithmetic.Factor":
            float v = 1.0;
            foreach (child; p.children)
                v *= value(child);
            return v;
        case "Arithmetic.Div":
            return 1.0 / value(p.children[0]);
        case "Arithmetic.Number":
            import npegged.conversion : parseNumber;

            return parseNumber!float(p.matches[0]).value;
        default:
            return float.nan;
        }
    }

    import core.stdc.stdio : printf, fflush, stdout;

    enum answer = value(parseTree);
    static immutable stored = parseTree;
    assert(value(stored) == answer);
    ParseContext context;
    auto divided = Arithmetic(context, "1/2 + -1");
    assert(value(divided.tree) == -0.5f);
    ParseTree unknown;
    auto missing = value(unknown);
    assert(missing != missing);
    auto printed = printf("%g\n", cast(double)answer);
    auto flushed = fflush(stdout);
    return ((printed >= 0) & (flushed == 0)) ? 0 : 2;
}

// rdmd -I../../.. arithmetic.d 
