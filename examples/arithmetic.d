// Converted from Pegged examples; Boost Software License 1.0.
/**
This module contains a example of a reusable arithmetic expression grammar and
a recursive ParseTree parser that returns the evaluation of the arithmetic expression
*/
module npegged.examples.arithmetic;

import npegged.grammar;
import npegged.conversion;

struct Variable(T) {
    string name;
    T value;
}

mixin(grammar(`
# Arithmetic grammar with variable terminal
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

mixin(grammar(`
# Arithmetic grammar without variable terminal
ArithmeticNoVar:
    Term     < Factor (Add / Sub)*
    Add      < "+" Factor
    Sub      < "-" Factor
    Factor   < Primary (Mul / Div)*
    Mul      < "*" Primary
    Div      < "/" Primary
    Primary  < Parens / Neg / Number
    Parens   < :"(" Term :")"
    Neg      < "-" Primary
    Number   < ~([0-9]+)
`));

struct Evaluation(T) {
    Status status = Status.invalidInput;
    T value;
    bool opEquals(R)(R expected) const @nogc nothrow if (is(R : real)) {
        return status == Status.ok && value == expected;
    }

    bool opEquals(const Evaluation other) const @nogc nothrow {
        return status == other.status && value == other.value;
    }
}

@nogc nothrow unittest {
    assert(Evaluation!int(Status.ok, 42) == 42);
    assert(!(Evaluation!int.init == 0));
    assert(Evaluation!int.init == Evaluation!int.init);
}

/// Evaluate a recognized arithmetic tree. Invalid trees, missing variables, and division
/// by zero return an explicit error status; numeric values do not borrow tree storage.
Evaluation!T parseArithmetic(T = float, string grammarName = "ArithmeticNoVar")(const ParseTree tree,
        const Variable!T[] variables = null) @nogc nothrow {
    alias Result = Evaluation!T;
    if (!tree.successful)
        return Result(Status.invalidInput);
    switch (tree.name) {
    case grammarName:
    case grammarName ~ ".Primary":
    case grammarName ~ ".Parens":
    case grammarName
            ~ ".Add":
    case grammarName ~ ".Mul":
    case grammarName ~ ".Div":
        if (tree.children.length != 1)
            return Result(Status.invalidInput);
        return parseArithmetic!(T, grammarName)(tree.children[0], variables);
    case grammarName ~ ".Neg":
    case grammarName ~ ".Sub":
        if (tree.children.length != 1)
            return Result(Status.invalidInput);
        auto operand = parseArithmetic!(T, grammarName)(tree.children[0], variables);
        if (operand.status != Status.ok)
            return operand;
        return Result(Status.ok, -operand.value);
    case grammarName ~ ".Term":
        if (!tree.children.length)
            return Result(Status.invalidInput);
        T total = 0;
        foreach (child; tree.children) {
            auto value = parseArithmetic!(T, grammarName)(child, variables);
            if (value.status != Status.ok)
                return value;
            total += value.value;
        }
        return Result(Status.ok, total);
    case grammarName ~ ".Factor":
        if (!tree.children.length)
            return Result(Status.invalidInput);
        T product = 1;
        foreach (child; tree.children) {
            auto value = parseArithmetic!(T, grammarName)(child, variables);
            if (value.status != Status.ok)
                return value;
            if (child.name == grammarName ~ ".Div") {
                if (value.value == 0)
                    return Result(Status.invalidInput);
                product /= value.value;
            } else
                product *= value.value;
        }
        return Result(Status.ok, product);
    case grammarName ~ ".Number":
        if (tree.matches.length != 1)
            return Result(Status.invalidInput);
        auto numeric = parseNumber!T(tree.matches[0]);
        return Result(numeric.status, numeric.value);
    case grammarName ~ ".Variable":
        if (tree.matches.length != 1)
            return Result(Status.invalidInput);
        foreach (variable; variables)
            if (variable.name == tree.matches[0])
                return Result(Status.ok, variable.value);
        return Result(Status.invalidInput);
    default:
        return Result(Status.invalidInput);
    }
}

@nogc nothrow unittest {
    ParseTree tree;
    tree.successful = true;
    assert(parseArithmetic!int(tree).status == Status.invalidInput);
    tree.successful = true;
    tree.name = "Arithmetic.Variable";
    string[1] matches = ["missing"];
    tree.matches = matches[];
    assert(parseArithmetic!(int, "Arithmetic")(tree).status == Status.invalidInput);
    Variable!int[2] variables = [Variable!int("other", 1), Variable!int("missing", 42)];
    assert(parseArithmetic!(int, "Arithmetic")(tree, variables[]) == 42);
    ParseTree[1] children;
    children[0].name = "Unknown";
    tree.name = "ArithmeticNoVar.Factor";
    tree.children = children[];
    assert(parseArithmetic!int(tree).status == Status.invalidInput);
}

@nogc nothrow unittest {
    ParseContext context; // Testing parsing arithmetic expression without variables
    string testExpression = "1 + 2 * (3 + 10 / 4)";
    const pNoVar = ArithmeticNoVar(context, testExpression);

    assert(pNoVar.successful);
    assert(pNoVar.toString == q"EOS
ArithmeticNoVar[0, 20]["1", "+", "2", "*", "3", "+", "10", "/", "4"]
 +-ArithmeticNoVar.Term[0, 20]["1", "+", "2", "*", "3", "+", "10", "/", "4"]
    +-ArithmeticNoVar.Factor[0, 2]["1"]
    |  +-ArithmeticNoVar.Primary[0, 2]["1"]
    |     +-ArithmeticNoVar.Number[0, 2]["1"]
    +-ArithmeticNoVar.Add[2, 20]["+", "2", "*", "3", "+", "10", "/", "4"]
       +-ArithmeticNoVar.Factor[4, 20]["2", "*", "3", "+", "10", "/", "4"]
          +-ArithmeticNoVar.Primary[4, 6]["2"]
          |  +-ArithmeticNoVar.Number[4, 6]["2"]
          +-ArithmeticNoVar.Mul[6, 20]["*", "3", "+", "10", "/", "4"]
             +-ArithmeticNoVar.Primary[8, 20]["3", "+", "10", "/", "4"]
                +-ArithmeticNoVar.Parens[8, 20]["3", "+", "10", "/", "4"]
                   +-ArithmeticNoVar.Term[9, 19]["3", "+", "10", "/", "4"]
                      +-ArithmeticNoVar.Factor[9, 11]["3"]
                      |  +-ArithmeticNoVar.Primary[9, 11]["3"]
                      |     +-ArithmeticNoVar.Number[9, 11]["3"]
                      +-ArithmeticNoVar.Add[11, 19]["+", "10", "/", "4"]
                         +-ArithmeticNoVar.Factor[13, 19]["10", "/", "4"]
                            +-ArithmeticNoVar.Primary[13, 16]["10"]
                            |  +-ArithmeticNoVar.Number[13, 16]["10"]
                            +-ArithmeticNoVar.Div[16, 19]["/", "4"]
                               +-ArithmeticNoVar.Primary[18, 19]["4"]
                                  +-ArithmeticNoVar.Number[18, 19]["4"]
EOS");

    // Parsing as a float
    const f = parseArithmetic(pNoVar);
    assert(f == 12.0f);

    // Parsing as integer
    const i = parseArithmetic!int(pNoVar);
    assert(i == 11);
}

@nogc nothrow unittest {
    ParseContext context;
    // Testing parsing arithmetic expression witht variables

    string testExpressionWithVar = "1 + 2 * (3 + 10 / 4) + fooBar";
    const p = Arithmetic(context, testExpressionWithVar);

    assert(p.successful);
    assert(p.toString == q"EOS
Arithmetic[0, 29]["1", "+", "2", "*", "3", "+", "10", "/", "4", "+", "fooBar"]
 +-Arithmetic.Term[0, 29]["1", "+", "2", "*", "3", "+", "10", "/", "4", "+", "fooBar"]
    +-Arithmetic.Factor[0, 2]["1"]
    |  +-Arithmetic.Primary[0, 2]["1"]
    |     +-Arithmetic.Number[0, 2]["1"]
    +-Arithmetic.Add[2, 21]["+", "2", "*", "3", "+", "10", "/", "4"]
    |  +-Arithmetic.Factor[4, 21]["2", "*", "3", "+", "10", "/", "4"]
    |     +-Arithmetic.Primary[4, 6]["2"]
    |     |  +-Arithmetic.Number[4, 6]["2"]
    |     +-Arithmetic.Mul[6, 21]["*", "3", "+", "10", "/", "4"]
    |        +-Arithmetic.Primary[8, 21]["3", "+", "10", "/", "4"]
    |           +-Arithmetic.Parens[8, 21]["3", "+", "10", "/", "4"]
    |              +-Arithmetic.Term[9, 19]["3", "+", "10", "/", "4"]
    |                 +-Arithmetic.Factor[9, 11]["3"]
    |                 |  +-Arithmetic.Primary[9, 11]["3"]
    |                 |     +-Arithmetic.Number[9, 11]["3"]
    |                 +-Arithmetic.Add[11, 19]["+", "10", "/", "4"]
    |                    +-Arithmetic.Factor[13, 19]["10", "/", "4"]
    |                       +-Arithmetic.Primary[13, 16]["10"]
    |                       |  +-Arithmetic.Number[13, 16]["10"]
    |                       +-Arithmetic.Div[16, 19]["/", "4"]
    |                          +-Arithmetic.Primary[18, 19]["4"]
    |                             +-Arithmetic.Number[18, 19]["4"]
    +-Arithmetic.Add[21, 29]["+", "fooBar"]
       +-Arithmetic.Factor[23, 29]["fooBar"]
          +-Arithmetic.Primary[23, 29]["fooBar"]
             +-Arithmetic.Variable[23, 29]["fooBar"]
EOS");

    // Parsing as a float
    const Variable!float[1] fVars = [Variable!float("fooBar", 10.25f)];
    const fWithVar = parseArithmetic!(float, "Arithmetic")(p, fVars);

    assert(fWithVar == 22.25f);

    // Parsing as integer
    const Variable!int[1] iVars = [Variable!int("fooBar", 10)];
    const iWithVar = parseArithmetic!(int, "Arithmetic")(p, iVars);

    assert(iWithVar == 21);
}

@nogc nothrow unittest {
    ParseContext context;
    // Some additional test borrowed from simple_arithmetic
    Evaluation!float interpreter(string expr) @nogc nothrow {
        auto result = ArithmeticNoVar(context, expr);
        return parseArithmetic(result.tree);
    }

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

    assert(interpreter("2*3*3 - 3*3 + 3*4") == 21.0);
    assert(interpreter("2 * 3 * 3 - 3 * (3 + 3 * 4)") == -27.0);
}

@nogc nothrow unittest {
    static immutable names = [
        "ArithmeticNoVar", "ArithmeticNoVar.Primary", "ArithmeticNoVar.Parens",
        "ArithmeticNoVar.Add", "ArithmeticNoVar.Mul", "ArithmeticNoVar.Div",
        "ArithmeticNoVar.Neg",
        "ArithmeticNoVar.Sub", "ArithmeticNoVar.Term",
        "ArithmeticNoVar.Factor", "ArithmeticNoVar.Number", "ArithmeticNoVar.Variable"
    ];
    foreach (name; names) {
        ParseTree malformed;
        malformed.successful = true;
        malformed.name = name;
        assert(parseArithmetic!int(malformed).status == Status.invalidInput);
    }
    ParseContext context;
    auto zero = ArithmeticNoVar(context, "1/0");
    assert(parseArithmetic!int(zero.tree).status == Status.invalidInput);
    auto badNumber = ArithmeticNoVar(context, "2147483648");
    assert(parseArithmetic!int(badNumber.tree).status == Status.invalidInput);
}
