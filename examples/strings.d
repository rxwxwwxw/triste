// Converted from Pegged examples; Boost Software License 1.0.
module npegged.examples.strings;

import npegged.grammar;

mixin(grammar(`
String:
# Example of a rule for double-quoted strings

    String <~ doublequote (!doublequote Char)* doublequote

    Char   <~ backslash ( doublequote  # '\' Escapes
                        / quote
                        / backslash
                        / [bfnrt]
                        / [0-2][0-7][0-7]
                        / [0-7][0-7]?
                        / 'x' Hex Hex
                        / 'u' Hex Hex Hex Hex
                        / 'U' Hex Hex Hex Hex Hex Hex Hex Hex
                        )
             / . # Or any char, really

    Hex     <- [0-9a-fA-F]
`));

@nogc nothrow unittest {
    ParseContext context;
    assert(String(context, `"Hello, World!"`).successful);
    assert(String(context, `"Hello,

                        World!"`).successful);
    assert(String(context, `""`).successful);
    assert(String(context, `"\'\""`).successful);
    assert(String(context, `"\\"`).successful);
    assert(String(context, `"\n\t\r"`).successful);
    assert(String(context, `"\60\61\7\111"`).successful);
    assert(String(context, `"\x40\x41"`).successful);
    assert(String(context, `"\u00A0\u00FF"`).successful);
    assert(String(context, `"\U000000A0\U000000B2"`).successful);

    // Failures
    assert(!String(context, `"Hello, World!`).successful);
    assert(!String(context, `Hello, World!"`).successful);
    assert(!String(context, `Hello, World!`).successful);
}
