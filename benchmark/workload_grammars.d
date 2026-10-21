module benchmark.workload_grammars;

import npegged.grammar;

version (NPeggedLL1)
    private enum backend = ParserBackend.ll1;
else version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
import benchmark.handwritten.arithmetic : ArithmeticParser;
import benchmark.handwritten.csv : CsvParser;
import benchmark.handwritten.numbers : NumbersParser;

// These validation grammars follow the handwritten interfaces, rather than the
// example grammars' capture shapes. Every entry requires complete consumption.
enum arithmeticGrammar = `
BenchArithmetic:
    Root <- Space Term eoi
    Term <- Factor (('+' / '-') Space Factor)*
    Factor <- Primary (('*' / '/') Space Primary)*
    Primary <- ('(' Space Term ')' / ('+' / '-') Space Primary / Number / Identifier) Space
    Number <- [0-9]+ ('.' [0-9]+)?
    Identifier <- [a-zA-Z_] [a-zA-Z_0-9]*
    Space <: [ \t\r\n]*
`;
mixin(grammar!(Memoization.selective, void, backend)(arithmeticGrammar));

@nogc nothrow unittest {
    static immutable inputs = [
        "1", "1 + 2 * (3 - 4)", "a_1 + -+2.3", "\t(1)\n", "", "1 +", "1.", "1 2", "1 + 2)", "@", "(1",
        "1e2"
    ];
    foreach (input; inputs) {
        ParseContext context;
        auto result = check!(BenchArithmetic.opCall)(context, input);
        assert(result.successful == ArithmeticParser.parse(input));
        if (result.successful)
            assert(result.end == input.length);
    }
}

enum csvGrammar = `
BenchCSV:
    Root <- Field (Sep Field)* eoi
    Sep <- ',' / '\r' '\n'? / '\n'
    Field <- [ \t]* (('"' ('""' / !'"' .)* '"' / (![," \t\r\n] .)+) [ \t]*)?
`;
mixin(grammar!(Memoization.selective, void, backend)(csvGrammar));

@nogc nothrow unittest {
    static immutable inputs = [
        "", "a,b,c", "1,2\r\n3,4\n", " , , ", `"","a""b","line
break"`, "a b", `"unterminated`, `"closed"x`, "a\"b", "\r\n"
    ];
    static assert(BenchCSV._dfa_Root.valid);
    static assert(BenchCSV._dfa_Root.requireEnd);
    foreach (input; inputs) {
        ParseContext context;
        auto result = check!(BenchCSV.opCall)(context, input);
        assert(result.successful == CsvParser.parse(input));
        if (result.successful)
            assert(result.end == input.length);
    }
    char[6] bytes;
    enum alphabet = "a,\" \r\n";
    size_t combinations = 1;
    foreach (length; 0 .. bytes.length + 1) {
        foreach (encoded; 0 .. combinations) {
            size_t value = encoded;
            foreach (ref c; bytes[0 .. length]) {
                c = alphabet[value % alphabet.length];
                value /= alphabet.length;
            }
            ParseContext context;
            const input = cast(string)bytes[0 .. length];
            assert(check!(BenchCSV.opCall)(context, input).successful == CsvParser.parse(input));
        }
        combinations *= alphabet.length;
    }
}

enum numbersGrammar = `
BenchNumbers:
    Scientific <- [+-]? [0-9]+ ('.' [0-9]+)? ([eE] [+-]? [0-9]+)? eoi
    Hexa <- [0-9a-fA-F]+ eoi
    Binary <- '0b' [01] [01_]* eoi
`;
mixin(grammar!(Memoization.selective, void, backend)(numbersGrammar));

@nogc nothrow unittest {
    static immutable inputs = [
        "", "0", "-123.45E+6", "1e", "1.", ".1", "+", " 1", "deadbeef", "0x12", "0b0", "0b1_",
        "0b_1", "0b2", "0123", "123Z"
    ];
    foreach (input; inputs) {
        ParseContext context;
        assert(check!(BenchNumbers.Scientific)(context, input).successful == NumbersParser
                .parseScientific(input));
        assert(check!(BenchNumbers.Hexa)(context, input).successful == NumbersParser.parseHexa(input));
        assert(check!(BenchNumbers.Binary)(context, input).successful == NumbersParser.parseBinary(input));
    }
}

// Exhaust short inputs to catch differences in commitment, optional suffixes,
// empty fields, and whitespace before these adapters enter timed comparisons.
@nogc nothrow unittest {
    char[4] bytes;
    static immutable alphabets = ["1.+-() a", "a,\" \n", "01be+._"];
    foreach (which, alphabet; alphabets) {
        size_t combinations = 1;
        foreach (length; 0 .. bytes.length + 1) {
            foreach (encoded; 0 .. combinations) {
                size_t digits = encoded;
                foreach (ref value; bytes[0 .. length]) {
                    value = alphabet[digits % alphabet.length];
                    digits /= alphabet.length;
                }
                const input = cast(string)bytes[0 .. length];
                ParseContext context;
                if (which == 0)
                    assert(check!(BenchArithmetic.opCall)(context, input).successful == ArithmeticParser
                            .parse(input));
                else if (which == 1)
                    assert(check!(BenchCSV.opCall)(context, input).successful == CsvParser.parse(input));
                else {
                    assert(check!(BenchNumbers.Scientific)(context, input)
                            .successful == NumbersParser.parseScientific(input));
                    assert(check!(BenchNumbers.Hexa)(context, input).successful == NumbersParser
                            .parseHexa(input));
                    assert(check!(BenchNumbers.Binary)(context, input).successful == NumbersParser
                            .parseBinary(input));
                }
            }
            combinations *= alphabet.length;
        }
    }
}

import benchmark.handwritten.ops : OpsParser;
import benchmark.handwritten.leftexpr : LeftExprParser;

// Directly left-recursive expression grammar (family `nested_expr`): recognition by seed growth versus loops.
enum leftExprGrammar = `
BenchLeftExpr:
    Root <- Space Expr eoi
    Expr <- Expr ('+' / '-') Space Term / Term
    Term <- Term ('*' / '/') Space Primary / Primary
    Primary <- '(' Space Expr ')' Space / [0-9]+ Space
    Space <: [ \t\n]*
`;
mixin(grammar!(Memoization.selective, void, backend)(leftExprGrammar));

@nogc nothrow unittest {
    static immutable inputs = [
        "", "1", "1+2", "1+2*3", "(1+2)*3-4/5", "1+", "1 *", "(1", "1)", "+1", "1 + 2 * (3 - 4)",
        "((((7))))", "((((((((((((1+2))))))))))))*3", "1 2", "1+2+", "2*(3+", "7 - - 1"
    ];
    foreach (input; inputs) {
        ParseContext context;
        const result = check!(BenchLeftExpr.opCall)(context, input);
        assert((result.successful && result.end == input.length) == LeftExprParser.parse(input), input);
    }
}

// Operator lexing with overlapping FIRST bytes (family `choices`): the ordered choice of 1-2 byte literals that the
// opt-in FIRST-2 dispatch (F4/P3) targets.
enum opsGrammar = `
BenchOps:
    Root <- Space (Op Space)* eoi
    Op <- '<<=' / '<<' / '<=' / '<' / '>>=' / '>>' / '>=' / '>' / '==' / '=' / '!=' / '!' / '&&' / '&' / '||' / '|' / '+=' / '++' / '+' / '-=' / '--' / '-' / '*=' / '*' / '/=' / '/'
    Space <: [ \t\n]*
`;
mixin(grammar!(Memoization.selective, void, backend)(opsGrammar));

@nogc nothrow unittest {
    static immutable inputs = [
        "", " ", "<", "<<=", "<= == != ++ --", "a", "< a", "&&|||", "=== !", "+=-=*=/=", "x<", "<~",
        "\t>>\n>=",
    ];
    foreach (input; inputs) {
        ParseContext context;
        const result = check!(BenchOps.opCall)(context, input);
        assert((result.successful && result.end == input.length) == OpsParser.parse(input), input);
    }
}

import benchmark.handwritten.peg : PegParser;

// The handwritten PEG parser is a syntax recognizer, not the NPegged bootstrap
// language. In particular it accepts repeated suffixes, arbitrary balanced
// parameter text, empty character classes, and a bare '<' rule arrow.
enum pegGrammar = `
BenchPEG:
    Root <- (SimpleGrammarHeader / &GrammarHeaderGuard FullGrammarHeader) Definition+ eoi
    GrammarHeaderGuard <- [ \t\r\n]* ('#' / [a-zA-Z_] [a-zA-Z0-9_]* [ \t\r\n]* [(#])
    SimpleGrammarHeader <- [ \t\r\n]* [a-zA-Z_] [a-zA-Z0-9_]* [ \t\r\n]* ':' Sp
    FullGrammarHeader <- Sp Ident Sp (&'(' Params Sp)? ':' Sp

    Definition <- !eoi DefHeader TopExpression
    DefHeader <- SimpleHeader / &DefHeaderGuard FullHeader
    DefHeaderGuard <- [ \t\r\n]* [a-zA-Z_] [a-zA-Z0-9_]* [ \t\r\n]* [({#]
    SimpleHeader <- [ \t\r\n]* [a-zA-Z_] [a-zA-Z0-9_]* [ \t\r\n]* '<' ('-'+ / [~:^;%])? Sp
    FullHeader <- Sp Ident Sp (&'(' Params Sp)? '<' ('-'+ / [~:^;%] / Action)? Sp

    TopExpression <- ([\/|] Sp)? TopSequence ([\/|] Sp TopSequence)*
    TopSequence <- Prefix Sp (!TopBoundary Prefix Sp)*
    TopBoundary <- eoi / [)/|] / &[a-zA-Z_] ([a-zA-Z_] [a-zA-Z0-9_]* [ \t\r\n]* '<' / (&ParamGuard ParamAhead))
    ParamGuard <- [a-zA-Z_] [a-zA-Z0-9_]* [ \t\r\n]* '('
    ParamAhead <- Ident Sp '(' ((![()] .)+ / ParamAhead)* ')' Sp '<'

    Expression <- ([\/|] Sp)? Sequence ([\/|] Sp Sequence)*
    Sequence <- Prefix Sp (!SequenceBoundary Prefix Sp)*
    SequenceBoundary <- [)/|] / eoi

    Prefix <- ([&!~:^;%] Sp)* Primary ([*+?] / &'{' Action)*
    Primary <- (Class / '(' Sp Expression ')' / Literal / Ident (&([.(]) (Params / ('.' &[a-zA-Z_] Ident)+))?) / '.'
    Ident <- [a-zA-Z_] [a-zA-Z0-9_]*
    Params <- '(' (Quoted / Params / (![()'\"] .)+)* ')'
    Action <- '{' (Quoted / Action / (![{}'\"] .)+)* '}'
    Quoted <- '\'' ('\\' . / (!'\'' .))* '\'' / '"' ('\\' . / (!'"' .))* '"'
    Literal <- Quoted 'i'?
    Class <- '[' '^'? ('\\' . / (!']' .))* ']'
    Sp <: [ \t\r\n]* ('#' (!'\n' .)* [ \t\r\n]*)*
`;
mixin(grammar!(Memoization.selective, void, backend)(pegGrammar));

@nogc nothrow unittest {
    static immutable inputs = [
        "Calc:\n Expr <- Term ('+' Term)*\n Term <- [0-9]+\n", "G: A < 'x'", "G: A <-- / []**",
        "G(x=(\"()\")): A(p) <{foo{bar}} !'x'i {x}", "G: A <- B.x B(a=(1))\nB <- .",
        "# comment\nG: A <- '.' # end", "", "G:", "G A <- 'x'", "G: A <-", "G: A <- ()",
        "G: A <- 'x", "G: A <- [x", "G: A <- x {a",
        "G: A <- x /", "G: A <- x )", "G: A <- x\nB <- 'b'", "G: A <- x\nB(\"(\") <- 'b'"
    ];
    foreach (input; inputs) {
        ParseContext context;
        auto result = check!(BenchPEG.opCall)(context, input);
        assert(result.successful == PegParser.parse(input), input);
        if (result.successful)
            assert(result.end == input.length);
    }
}

@nogc nothrow unittest {
    // Exercise token boundaries and the handwritten definition-ahead probe,
    // whose raw parenthesis balancing deliberately differs from Params.
    static immutable parts = [
        "x", "'a'", "[]", "(", ")", "/", "|", "!", "*", "{a}", "B <-", "B(p) <-", "B(\"(\") <-",
        "x.y", "x(a)", "# c\n", " "
    ];
    char[128] storage;
    foreach (a; parts) {
        foreach (b; parts) {
            foreach (c; parts) {
                size_t length;
                foreach (part; ["G: A <- ", a, " ", b, " ", c]) {
                    storage[length .. length + part.length] = part[];
                    length += part.length;
                }
                const input = cast(string)storage[0 .. length];
                ParseContext context;
                assert(check!(BenchPEG.opCall)(context, input).successful == PegParser.parse(input), input);
            }
        }
    }
}

import benchmark.measurement : Observation;

pragma(inline, true) private Observation recognize(alias parser)(string input) @nogc nothrow {
    ParseContext context;
    auto result = check!parser(context, input);
    return Observation(result.successful && result.end == input.length, 0, 0,
            result.arena.allocationCalls, result.arena.requestedBytes, result.arena.used, true,
            result.status == Status.mismatch ? Status.ok : result.status);
}

pragma(inline, true) private Observation acceptAll(alias parser)(string input) @nogc nothrow {
    ParseContext context;
    const result = accept!parser(context, input);
    return Observation(result.accepted, 0, 0, 0, 0, 0, true, result.status == Status.mismatch
            ? Status.ok : result.status);
}

/// `accept` obligation (decision D3): whole-input yes/no with the handwritten boolean twins; the NPegged side calls
/// `accept!` instead of `check!`.
Observation observeWorkloadAccept(string name, string input, bool handwritten) @nogc nothrow {
    if (handwritten)
        return observeWorkload(name, input, true);
    if (name.length >= 11 && name[0 .. 11] == "Arithmetic.")
        return acceptAll!(BenchArithmetic.opCall)(input);
    if (name.length >= 4 && name[0 .. 4] == "Ops.")
        return acceptAll!(BenchOps.opCall)(input);
    if (name.length >= 9 && name[0 .. 9] == "LeftExpr.")
        return acceptAll!(BenchLeftExpr.opCall)(input);
    if (name.length >= 4 && name[0 .. 4] == "CSV.")
        return acceptAll!(BenchCSV.opCall)(input);
    if (name.length >= 11 && name[0 .. 11] == "PEGGrammar.")
        return acceptAll!(BenchPEG.opCall)(input);
    if (name.length >= 12 && name[0 .. 12] == "Numbers.Hexa")
        return acceptAll!(BenchNumbers.Hexa)(input);
    if (name.length >= 14 && name[0 .. 14] == "Numbers.Binary")
        return acceptAll!(BenchNumbers.Binary)(input);
    if (name.length >= 18 && name[0 .. 18] == "Numbers.Scientific")
        return acceptAll!(BenchNumbers.Scientific)(input);
    Observation invalid;
    invalid.status = Status.invalidInput;
    return invalid;
}

/// Matching boolean obligations; both engines include result destruction.
Observation observeWorkload(string name, string input, bool handwritten) @nogc nothrow {
    if (name.length >= 11 && name[0 .. 11] == "Arithmetic.")
        return handwritten ? Observation(ArithmeticParser.parse(input), 0, 0, 0, 0, 0, true)
            : recognize!(BenchArithmetic.opCall)(input);
    if (name.length >= 4 && name[0 .. 4] == "CSV.")
        return handwritten ? Observation(CsvParser.parse(input), 0, 0, 0, 0, 0, true) : recognize!(
                BenchCSV.opCall)(input);
    if (name.length >= 11 && name[0 .. 11] == "PEGGrammar.")
        return handwritten ? Observation(PegParser.parse(input), 0, 0, 0, 0, 0, true) : recognize!(
                BenchPEG.opCall)(input);
    if (name.length >= 4 && name[0 .. 4] == "Ops.")
        return handwritten ? Observation(OpsParser.parse(input), 0, 0, 0, 0, 0, true) : recognize!(
                BenchOps.opCall)(input);
    if (name.length >= 9 && name[0 .. 9] == "LeftExpr.")
        return handwritten ? Observation(LeftExprParser.parse(input), 0, 0, 0, 0, 0, true)
            : recognize!(BenchLeftExpr.opCall)(input);
    if (name.length >= 12 && name[0 .. 12] == "Numbers.Hexa")
        return handwritten ? Observation(NumbersParser.parseHexa(input), 0, 0, 0, 0, 0, true)
            : recognize!(BenchNumbers.Hexa)(input);
    if (name.length >= 14 && name[0 .. 14] == "Numbers.Binary")
        return handwritten ? Observation(NumbersParser.parseBinary(input), 0, 0, 0, 0, 0, true)
            : recognize!(BenchNumbers.Binary)(input);
    if (name.length >= 18 && name[0 .. 18] == "Numbers.Scientific")
        return handwritten ? Observation(NumbersParser.parseScientific(input), 0, 0, 0, 0, 0, true) : recognize!(
                BenchNumbers.Scientific)(input);
    Observation invalid;
    invalid.status = Status.invalidInput;
    return invalid;
}

@nogc nothrow unittest {
    foreach (handwritten; [false, true]) {
        foreach (name; [
            "Arithmetic.Test", "CSV.Test", "PEGGrammar.Test", "Numbers.HexaTest",
            "Numbers.BinaryTest", "Numbers.ScientificTest", "Ops.Test", "LeftExpr.Test"
        ]) {
            {
                const probe = name[0] == 'L' ? "1+2" : name[0] == 'O' ? "<= ==" : name[0] == 'A'
                    ? "1" : name[0] == 'C' ? "a,b" : name[0] == 'P' ? "G: A <- 'a'" : name[8] == 'B' ? "0b1" : "12";
                auto viaAccept = observeWorkloadAccept(name, probe, handwritten);
                assert(viaAccept.accepted && viaAccept.status == Status.ok);
                auto rejected = observeWorkloadAccept(name, "\x01\x02", handwritten);
                assert(!rejected.accepted && rejected.status == Status.ok);
            }
            const input = name[0] == 'L' ? "1+2" : name[0] == 'O' ? "<= ==" : name[0] == 'A'
                ? "1" : name[0] == 'C' ? "a,b" : name[0] == 'P' ? "G: A <- 'a'" : name[8] == 'B' ? "0b1" : "12";
            auto observation = observeWorkload(name, input, handwritten);
            assert(observation.accepted && observation.status == Status.ok && observation
                    .allocatorMeasured);
        }
        assert(observeWorkload("Unknown", "", handwritten).status == Status.invalidInput);
    }
}
