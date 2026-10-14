// Converted from Pegged examples; Boost Software License 1.0.
/**
This module contains a simple example of a arithmetic expression grammar and
how use the ParseTree to calculate a expression.
*/
module npegged.examples.simple_arithmetic;

import npegged.grammar;
import npegged.examples.arithmetic : Evaluation, parseArithmetic;

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

/// Example interpreter
Evaluation!float interpreter(string expr) @nogc nothrow {
    ParseContext context;
    auto parsed = Arithmetic(context, expr);
    if (parsed.status != Status.ok)
        return Evaluation!float(parsed.status);
    if (parsed.end != expr.length)
        return Evaluation!float(Status.mismatch);
    return parseArithmetic!(float, "Arithmetic")(parsed.tree);
}

@nogc nothrow unittest {
    ParseContext context;
    assert(interpreter("1") == 1.0);
    assert(interpreter("-1") == -1.0);
    assert(interpreter("1+1") == 2.0);
    assert(interpreter("1-1") == 0.0);

    assert(interpreter("1+1+1") == 3.0);
    assert(interpreter("1-1-1") == -1.0);
    assert(interpreter("1+1-1") == 1.0);
    assert(interpreter("1-1+1") == 1.0);
    assert(interpreter("-1+1+1") == 1.0);

    assert(interpreter("(-1+1)+1") == 1.0);
    assert(interpreter("-1+(1+1)") == 1.0);
    assert(interpreter("(-1+1+1)") == 1.0);
    assert(interpreter("1-(1-1)") == 1.0);

    assert(interpreter("1*1") == 1.0);
    assert(interpreter("1/1") == 1.0);
    assert(interpreter("-1*1") == -1.0);
    assert(interpreter("-1/1") == -1.0);

    assert(interpreter("1+2*3") == 7.0);
    assert(interpreter("1-2*3") == -5.0);
    assert(interpreter("-1-2*-3") == 5.0);
    assert(interpreter("-1+2*-3") == -7.0);

    assert(interpreter("1/2/(1/2)") == 1.0);
    assert(interpreter("1/2/1/2") == .25);
    assert(interpreter("1 - 2*3 - 2*3") == -11.0);

    assert(interpreter("2*3*3 - 3*3+3*4") == 21.0);
    assert(interpreter("2 * 3 * 3 - 3 * (3 + 3 * 4)") == -27.0);
}

@nogc nothrow unittest {
    assert(interpreter("1/0").status == Status.invalidInput);
    assert(interpreter("unknown").status == Status.invalidInput);
    assert(interpreter("1 garbage").status == Status.mismatch);
    assert(interpreter("").status == Status.mismatch);
}
