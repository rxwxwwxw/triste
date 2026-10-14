// Converted from Pegged examples; Boost Software License 1.0.
/**
This module contains a example grammar rules to parse different kind of numbers literals.
*/
module npegged.examples.numbers;

import npegged.grammar;

/// Numbers
mixin(grammar(`
Numbers:
    Scientific <~ Floating ( ('e' / 'E' ) Integer )?
    Floating   <~ Integer ('.' Unsigned )?
    Unsigned   <~ [0-9]+
    Integer    <~ Sign? Unsigned
    Hexa       <~ [0-9a-fA-F]+
    Binary     <~ "0b" [01] [01_]*
    Sign       <- '-' / '+'
`));

@nogc nothrow unittest {
    ParseContext context;
    static immutable string[] cases1 = [
        "0", "0.0", "0.01", "-0", "+0", "-0.0", "+0.0", "0", "1", "2", "3", "4", "5", "6", "7",
        "8", "9", "0123456789", "123", "123.0", "123.01", "-123", "-123.0", "-123.01", "-123e+12",
        "-123e-12", "+123e+12", "+123e-12", "-123E+12", "-123E-12", "+123E+12", "+123E-12",
        "123.456e+00", "123.456E+00", "123.456e-00", "123.456E-00", "-123.456e+00",
        "-123.456E+00", "-123.456e-00",
        "-123.456E-00", "+123.456e+00", "+123.456E+00", "+123.456e-00", "+123.456E-00"
    ];
    immutable(string)[] testNumbers = cases1;

    foreach (number; testNumbers) {
        const parseTree = Numbers(context, number);
        auto match = parseTree.matches;
        assert(parseTree.successful);
        assert(match == [number]); // Shall parse
    }

    // Failures
    static immutable string[] cases2 = [
        ".", ".0", "0.", "123..456", "", "abc", "+", "-", "+.", "-.", "--1", "++1", "+-1", "-+1",
        "1e", "1e+", "1e-", "1ee"
    ];
    testNumbers = cases2;

    foreach (number; testNumbers) {
        assert(Numbers(context, number).matches != [number]); // None shall parse
    }

    // Hexadecimal numbers
    static immutable string[] cases3 = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "a", "b",
        "c", "d", "e", "f", "0123456789ABCDEF", "0123456789abcdef", "DEADBEEF", "0123BEEF",
        "DEAD0123", "deadbeef", "0123beef", "dead0123", "123E", "123e"
    ];
    testNumbers = cases3;

    foreach (number; testNumbers) {
        const parseTree = Numbers.Hexa(context, number);
        auto match = parseTree.matches;
        assert(parseTree.successful);
        assert(match == [number]); // Shall parse
    }

    // Hexadecimal failures
    static immutable string[] cases4 = ["", "G", "g", "-1", "123.456", "123e+100"];
    testNumbers = cases4;

    foreach (number; testNumbers) {
        assert(Numbers.Hexa(context, number).matches != [number]); // None shall parse
    }

    // Binary numbers
    static immutable string[] cases5 = [
        "0b0", "0b1", "0b0000", "0b0001", "0b11110000", "0b0000_1111", "0b1010_00_11"
    ];
    testNumbers = cases5;

    foreach (number; testNumbers) {
        const parseTree = Numbers.Binary(context, number);
        auto match = parseTree.matches;
        assert(parseTree.successful);
        assert(match == [number]); // Shall parse
    }

    // Hexadecimal failures
    static immutable string[] cases6 = [
        "", "G", "g", "-1", "123.456", "123e+100", "0b", "01010", "0b3456"
    ];
    testNumbers = cases6;

    foreach (number; testNumbers) {
        assert(Numbers.Binary(context, number).matches != [number]); // None shall parse
    }
}
