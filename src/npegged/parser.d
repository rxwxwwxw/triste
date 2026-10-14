// Generated from Pegged-derived npegged grammar. Boost 1.0.
module npegged.parser;
public import npegged.peg;

struct Pegged {
    private static ParseTree _Grammar(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(Spacing, GrammarName, oneOrMore!(Definition), discard!(eoi)), "Pegged.Grammar")(
                s, p);
    }

    static ParseTree Grammar(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Grammar!false, "Pegged.Grammar", true)(p);
    }

    static ParseTree Grammar(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Grammar!true, "Pegged.Grammar", true)(p);
    }

    static ParseResult Grammar(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Grammar)(ctx, input);
    }

    static ParseTree Grammar(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Grammar)(input);
    }

    private static ParseTree _Definition(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(LhsName, Arrow, Expression), "Pegged.Definition")(s, p);
    }

    static ParseTree Definition(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Definition!false, "Pegged.Definition", true)(p);
    }

    static ParseTree Definition(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Definition!true, "Pegged.Definition", true)(p);
    }

    static ParseResult Definition(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Definition)(ctx, input);
    }

    static ParseTree Definition(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Definition)(input);
    }

    private static ParseTree _Expression(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(FirstExpression, LongestExpression), "Pegged.Expression")(s, p);
    }

    static ParseTree Expression(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Expression!false, "Pegged.Expression", true)(p);
    }

    static ParseTree Expression(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Expression!true, "Pegged.Expression", true)(p);
    }

    static ParseResult Expression(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Expression)(ctx, input);
    }

    static ParseTree Expression(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Expression)(input);
    }

    private static ParseTree _FirstExpression(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(discard!(option!(OR)), Sequence, oneOrMore!(and!(discard!(OR), Sequence))),
                "Pegged.FirstExpression")(s, p);
    }

    static ParseTree FirstExpression(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_FirstExpression!false, "Pegged.FirstExpression", true)(p);
    }

    static ParseTree FirstExpression(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_FirstExpression!true, "Pegged.FirstExpression", true)(p);
    }

    static ParseResult FirstExpression(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(FirstExpression)(ctx, input);
    }

    static ParseTree FirstExpression(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(FirstExpression)(input);
    }

    private static ParseTree _LongestExpression(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(discard!(option!(or!(OR, LONGEST_OR))), Sequence,
                zeroOrMore!(and!(discard!(LONGEST_OR), Sequence))), "Pegged.LongestExpression")(s, p);
    }

    static ParseTree LongestExpression(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_LongestExpression!false, "Pegged.LongestExpression", true)(p);
    }

    static ParseTree LongestExpression(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_LongestExpression!true, "Pegged.LongestExpression", true)(p);
    }

    static ParseResult LongestExpression(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(LongestExpression)(ctx, input);
    }

    static ParseTree LongestExpression(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(LongestExpression)(input);
    }

    private static ParseTree _Sequence(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(oneOrMore!(Prefix), "Pegged.Sequence")(s, p);
    }

    static ParseTree Sequence(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Sequence!false, "Pegged.Sequence", true)(p);
    }

    static ParseTree Sequence(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Sequence!true, "Pegged.Sequence", true)(p);
    }

    static ParseResult Sequence(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Sequence)(ctx, input);
    }

    static ParseTree Sequence(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Sequence)(input);
    }

    private static ParseTree _Prefix(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(zeroOrMore!(or!(POS, NEG, FUSE, DISCARD, KEEP, DROP, PROPAGATE)),
                Suffix), "Pegged.Prefix")(s, p);
    }

    static ParseTree Prefix(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Prefix!false, "Pegged.Prefix", true)(p);
    }

    static ParseTree Prefix(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Prefix!true, "Pegged.Prefix", true)(p);
    }

    static ParseResult Prefix(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Prefix)(ctx, input);
    }

    static ParseTree Prefix(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Prefix)(input);
    }

    private static ParseTree _Suffix(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(Primary, zeroOrMore!(or!(OPTION, ZEROORMORE, ONEORMORE, Action))), "Pegged.Suffix")(
                s, p);
    }

    static ParseTree Suffix(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Suffix!false, "Pegged.Suffix", true)(p);
    }

    static ParseTree Suffix(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Suffix!true, "Pegged.Suffix", true)(p);
    }

    static ParseResult Suffix(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Suffix)(ctx, input);
    }

    static ParseTree Suffix(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Suffix)(input);
    }

    private static ParseTree _Primary(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(negLookahead!(and!(LhsName, Arrow)), or!(RhsName,
                and!(discard!(OPEN), Expression, discard!(CLOSE)), Literal, CILiteral, CharClass, ANY)),
                "Pegged.Primary")(s, p);
    }

    static ParseTree Primary(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Primary!false, "Pegged.Primary", true)(p);
    }

    static ParseTree Primary(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Primary!true, "Pegged.Primary", true)(p);
    }

    static ParseResult Primary(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Primary)(ctx, input);
    }

    static ParseTree Primary(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Primary)(input);
    }

    private static ParseTree _Identifier(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(identifier, "Pegged.Identifier")(s, p);
    }

    static ParseTree Identifier(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Identifier!false, "Pegged.Identifier", true)(p);
    }

    static ParseTree Identifier(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Identifier!true, "Pegged.Identifier", true)(p);
    }

    static ParseResult Identifier(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Identifier)(ctx, input);
    }

    static ParseTree Identifier(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Identifier)(input);
    }

    private static ParseTree _GrammarName(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(Identifier, option!(ParamList), Spacing, discard!(literal!(":")),
                Spacing), "Pegged.GrammarName")(s, p);
    }

    static ParseTree GrammarName(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_GrammarName!false, "Pegged.GrammarName", true)(p);
    }

    static ParseTree GrammarName(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_GrammarName!true, "Pegged.GrammarName", true)(p);
    }

    static ParseResult GrammarName(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(GrammarName)(ctx, input);
    }

    static ParseTree GrammarName(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(GrammarName)(input);
    }

    private static ParseTree _LhsName(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(Identifier, option!(ParamList), Spacing), "Pegged.LhsName")(s, p);
    }

    static ParseTree LhsName(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_LhsName!false, "Pegged.LhsName", true)(p);
    }

    static ParseTree LhsName(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_LhsName!true, "Pegged.LhsName", true)(p);
    }

    static ParseResult LhsName(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(LhsName)(ctx, input);
    }

    static ParseTree LhsName(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(LhsName)(input);
    }

    private static ParseTree _RhsName(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(Identifier, option!(ArgList), zeroOrMore!(and!(NAMESEP,
                Identifier, option!(ArgList))), Spacing), "Pegged.RhsName")(s, p);
    }

    static ParseTree RhsName(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_RhsName!false, "Pegged.RhsName", true)(p);
    }

    static ParseTree RhsName(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_RhsName!true, "Pegged.RhsName", true)(p);
    }

    static ParseResult RhsName(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(RhsName)(ctx, input);
    }

    static ParseTree RhsName(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(RhsName)(input);
    }

    private static ParseTree _ParamList(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(discard!(OPEN), Param, zeroOrMore!(and!(discard!(SEPARATOR),
                Param)), discard!(CLOSE)), "Pegged.ParamList")(s, p);
    }

    static ParseTree ParamList(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_ParamList!false, "Pegged.ParamList", true)(p);
    }

    static ParseTree ParamList(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_ParamList!true, "Pegged.ParamList", true)(p);
    }

    static ParseResult ParamList(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(ParamList)(ctx, input);
    }

    static ParseTree ParamList(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(ParamList)(input);
    }

    private static ParseTree _Param(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(DefaultParam, SingleParam), "Pegged.Param")(s, p);
    }

    static ParseTree Param(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Param!false, "Pegged.Param", true)(p);
    }

    static ParseTree Param(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Param!true, "Pegged.Param", true)(p);
    }

    static ParseResult Param(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Param)(ctx, input);
    }

    static ParseTree Param(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Param)(input);
    }

    private static ParseTree _DefaultParam(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(Identifier, Spacing, discard!(ASSIGN), Expression), "Pegged.DefaultParam")(
                s, p);
    }

    static ParseTree DefaultParam(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DefaultParam!false, "Pegged.DefaultParam", true)(p);
    }

    static ParseTree DefaultParam(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DefaultParam!true, "Pegged.DefaultParam", true)(p);
    }

    static ParseResult DefaultParam(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DefaultParam)(ctx, input);
    }

    static ParseTree DefaultParam(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DefaultParam)(input);
    }

    private static ParseTree _SingleParam(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(Identifier, Spacing), "Pegged.SingleParam")(s, p);
    }

    static ParseTree SingleParam(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_SingleParam!false, "Pegged.SingleParam", true)(p);
    }

    static ParseTree SingleParam(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_SingleParam!true, "Pegged.SingleParam", true)(p);
    }

    static ParseResult SingleParam(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(SingleParam)(ctx, input);
    }

    static ParseTree SingleParam(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(SingleParam)(input);
    }

    private static ParseTree _ArgList(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(discard!(OPEN), Expression, zeroOrMore!(and!(discard!(SEPARATOR),
                Expression)), discard!(CLOSE)), "Pegged.ArgList")(s, p);
    }

    static ParseTree ArgList(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_ArgList!false, "Pegged.ArgList", true)(p);
    }

    static ParseTree ArgList(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_ArgList!true, "Pegged.ArgList", true)(p);
    }

    static ParseResult ArgList(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(ArgList)(ctx, input);
    }

    static ParseTree ArgList(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(ArgList)(input);
    }

    private static ParseTree _Literal(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(and!(quote, fuse!(zeroOrMore!(and!(negLookahead!(quote), Char))),
                quote, negLookahead!(literal!("i")), Spacing), and!(doublequote,
                fuse!(zeroOrMore!(and!(negLookahead!(doublequote),
                Char))), doublequote, negLookahead!(literal!("i")), Spacing)), "Pegged.Literal")(s, p);
    }

    static ParseTree Literal(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Literal!false, "Pegged.Literal", true)(p);
    }

    static ParseTree Literal(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Literal!true, "Pegged.Literal", true)(p);
    }

    static ParseResult Literal(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Literal)(ctx, input);
    }

    static ParseTree Literal(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Literal)(input);
    }

    private static ParseTree _CILiteral(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(and!(quote, fuse!(zeroOrMore!(and!(negLookahead!(quote), Char))),
                quote, discard!(literal!("i")), Spacing), and!(doublequote,
                fuse!(zeroOrMore!(and!(negLookahead!(doublequote),
                Char))), doublequote, discard!(literal!("i")), Spacing)), "Pegged.CILiteral")(s, p);
    }

    static ParseTree CILiteral(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_CILiteral!false, "Pegged.CILiteral", true)(p);
    }

    static ParseTree CILiteral(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_CILiteral!true, "Pegged.CILiteral", true)(p);
    }

    static ParseResult CILiteral(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(CILiteral)(ctx, input);
    }

    static ParseTree CILiteral(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(CILiteral)(input);
    }

    private static ParseTree _CharClass(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(discard!(literal!("[")),
                zeroOrMore!(and!(negLookahead!(literal!("]")), CharRange)), discard!(literal!("]")), Spacing),
                "Pegged.CharClass")(s, p);
    }

    static ParseTree CharClass(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_CharClass!false, "Pegged.CharClass", true)(p);
    }

    static ParseTree CharClass(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_CharClass!true, "Pegged.CharClass", true)(p);
    }

    static ParseResult CharClass(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(CharClass)(ctx, input);
    }

    static ParseTree CharClass(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(CharClass)(input);
    }

    private static ParseTree _CharRange(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(and!(Char, literal!("-"), Char), Char), "Pegged.CharRange")(s, p);
    }

    static ParseTree CharRange(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_CharRange!false, "Pegged.CharRange", true)(p);
    }

    static ParseTree CharRange(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_CharRange!true, "Pegged.CharRange", true)(p);
    }

    static ParseResult CharRange(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(CharRange)(ctx, input);
    }

    static ParseTree CharRange(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(CharRange)(input);
    }

    private static ParseTree _Char(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(fuse!(or!(and!(backslash, or!(quote, doublequote, backquote, backslash,
                literal!("-"), literal!("["), literal!("]"), or!(charRange!(110, 110),
                charRange!(114, 114), charRange!(116, 116)), and!(or!(charRange!(48, 50)),
                or!(charRange!(48, 55)), or!(charRange!(48, 55))), and!(or!(charRange!(48, 55)),
                option!(or!(charRange!(48, 55)))), and!(literal!("x"), hexDigit, hexDigit),
                and!(literal!("u"), hexDigit, hexDigit, hexDigit, hexDigit), and!(literal!("U"),
                hexDigit, hexDigit, hexDigit, hexDigit, hexDigit, hexDigit, hexDigit, hexDigit))), any)),
                "Pegged.Char")(s, p);
    }

    static ParseTree Char(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Char!false, "Pegged.Char", true)(p);
    }

    static ParseTree Char(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Char!true, "Pegged.Char", true)(p);
    }

    static ParseResult Char(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Char)(ctx, input);
    }

    static ParseTree Char(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Char)(input);
    }

    private static ParseTree _Arrow(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(LEFTARROW, FUSEARROW, DISCARDARROW, KEEPARROW, DROPARROW,
                PROPAGATEARROW, ACTIONARROW, SPACEARROW), "Pegged.Arrow")(s, p);
    }

    static ParseTree Arrow(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Arrow!false, "Pegged.Arrow", true)(p);
    }

    static ParseTree Arrow(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Arrow!true, "Pegged.Arrow", true)(p);
    }

    static ParseResult Arrow(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Arrow)(ctx, input);
    }

    static ParseTree Arrow(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Arrow)(input);
    }

    private static ParseTree _LEFTARROW(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("<-"), Spacing), "Pegged.LEFTARROW")(s, p);
    }

    static ParseTree LEFTARROW(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_LEFTARROW!false, "Pegged.LEFTARROW", true)(p);
    }

    static ParseTree LEFTARROW(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_LEFTARROW!true, "Pegged.LEFTARROW", true)(p);
    }

    static ParseResult LEFTARROW(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(LEFTARROW)(ctx, input);
    }

    static ParseTree LEFTARROW(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(LEFTARROW)(input);
    }

    private static ParseTree _FUSEARROW(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("<~"), Spacing), "Pegged.FUSEARROW")(s, p);
    }

    static ParseTree FUSEARROW(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_FUSEARROW!false, "Pegged.FUSEARROW", true)(p);
    }

    static ParseTree FUSEARROW(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_FUSEARROW!true, "Pegged.FUSEARROW", true)(p);
    }

    static ParseResult FUSEARROW(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(FUSEARROW)(ctx, input);
    }

    static ParseTree FUSEARROW(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(FUSEARROW)(input);
    }

    private static ParseTree _DISCARDARROW(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("<:"), Spacing), "Pegged.DISCARDARROW")(s, p);
    }

    static ParseTree DISCARDARROW(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DISCARDARROW!false, "Pegged.DISCARDARROW", true)(p);
    }

    static ParseTree DISCARDARROW(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DISCARDARROW!true, "Pegged.DISCARDARROW", true)(p);
    }

    static ParseResult DISCARDARROW(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DISCARDARROW)(ctx, input);
    }

    static ParseTree DISCARDARROW(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DISCARDARROW)(input);
    }

    private static ParseTree _KEEPARROW(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("<^"), Spacing), "Pegged.KEEPARROW")(s, p);
    }

    static ParseTree KEEPARROW(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_KEEPARROW!false, "Pegged.KEEPARROW", true)(p);
    }

    static ParseTree KEEPARROW(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_KEEPARROW!true, "Pegged.KEEPARROW", true)(p);
    }

    static ParseResult KEEPARROW(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(KEEPARROW)(ctx, input);
    }

    static ParseTree KEEPARROW(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(KEEPARROW)(input);
    }

    private static ParseTree _DROPARROW(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("<;"), Spacing), "Pegged.DROPARROW")(s, p);
    }

    static ParseTree DROPARROW(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DROPARROW!false, "Pegged.DROPARROW", true)(p);
    }

    static ParseTree DROPARROW(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DROPARROW!true, "Pegged.DROPARROW", true)(p);
    }

    static ParseResult DROPARROW(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DROPARROW)(ctx, input);
    }

    static ParseTree DROPARROW(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DROPARROW)(input);
    }

    private static ParseTree _PROPAGATEARROW(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("<%"), Spacing), "Pegged.PROPAGATEARROW")(s, p);
    }

    static ParseTree PROPAGATEARROW(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_PROPAGATEARROW!false, "Pegged.PROPAGATEARROW", true)(p);
    }

    static ParseTree PROPAGATEARROW(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_PROPAGATEARROW!true, "Pegged.PROPAGATEARROW", true)(p);
    }

    static ParseResult PROPAGATEARROW(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(PROPAGATEARROW)(ctx, input);
    }

    static ParseTree PROPAGATEARROW(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(PROPAGATEARROW)(input);
    }

    private static ParseTree _SPACEARROW(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("<"), Spacing), "Pegged.SPACEARROW")(s, p);
    }

    static ParseTree SPACEARROW(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_SPACEARROW!false, "Pegged.SPACEARROW", true)(p);
    }

    static ParseTree SPACEARROW(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_SPACEARROW!true, "Pegged.SPACEARROW", true)(p);
    }

    static ParseResult SPACEARROW(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(SPACEARROW)(ctx, input);
    }

    static ParseTree SPACEARROW(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(SPACEARROW)(input);
    }

    private static ParseTree _ACTIONARROW(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("<"), Action, Spacing), "Pegged.ACTIONARROW")(s, p);
    }

    static ParseTree ACTIONARROW(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_ACTIONARROW!false, "Pegged.ACTIONARROW", true)(p);
    }

    static ParseTree ACTIONARROW(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_ACTIONARROW!true, "Pegged.ACTIONARROW", true)(p);
    }

    static ParseResult ACTIONARROW(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(ACTIONARROW)(ctx, input);
    }

    static ParseTree ACTIONARROW(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(ACTIONARROW)(input);
    }

    private static ParseTree _OR(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("/"), Spacing), "Pegged.OR")(s, p);
    }

    static ParseTree OR(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_OR!false, "Pegged.OR", true)(p);
    }

    static ParseTree OR(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_OR!true, "Pegged.OR", true)(p);
    }

    static ParseResult OR(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(OR)(ctx, input);
    }

    static ParseTree OR(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(OR)(input);
    }

    private static ParseTree _LONGEST_OR(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("|"), Spacing), "Pegged.LONGEST_OR")(s, p);
    }

    static ParseTree LONGEST_OR(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_LONGEST_OR!false, "Pegged.LONGEST_OR", true)(p);
    }

    static ParseTree LONGEST_OR(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_LONGEST_OR!true, "Pegged.LONGEST_OR", true)(p);
    }

    static ParseResult LONGEST_OR(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(LONGEST_OR)(ctx, input);
    }

    static ParseTree LONGEST_OR(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(LONGEST_OR)(input);
    }

    private static ParseTree _POS(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("&"), Spacing), "Pegged.POS")(s, p);
    }

    static ParseTree POS(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_POS!false, "Pegged.POS", true)(p);
    }

    static ParseTree POS(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_POS!true, "Pegged.POS", true)(p);
    }

    static ParseResult POS(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(POS)(ctx, input);
    }

    static ParseTree POS(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(POS)(input);
    }

    private static ParseTree _NEG(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("!"), Spacing), "Pegged.NEG")(s, p);
    }

    static ParseTree NEG(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_NEG!false, "Pegged.NEG", true)(p);
    }

    static ParseTree NEG(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_NEG!true, "Pegged.NEG", true)(p);
    }

    static ParseResult NEG(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(NEG)(ctx, input);
    }

    static ParseTree NEG(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(NEG)(input);
    }

    private static ParseTree _FUSE(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("~"), Spacing), "Pegged.FUSE")(s, p);
    }

    static ParseTree FUSE(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_FUSE!false, "Pegged.FUSE", true)(p);
    }

    static ParseTree FUSE(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_FUSE!true, "Pegged.FUSE", true)(p);
    }

    static ParseResult FUSE(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(FUSE)(ctx, input);
    }

    static ParseTree FUSE(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(FUSE)(input);
    }

    private static ParseTree _DISCARD(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!(":"), Spacing), "Pegged.DISCARD")(s, p);
    }

    static ParseTree DISCARD(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DISCARD!false, "Pegged.DISCARD", true)(p);
    }

    static ParseTree DISCARD(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DISCARD!true, "Pegged.DISCARD", true)(p);
    }

    static ParseResult DISCARD(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DISCARD)(ctx, input);
    }

    static ParseTree DISCARD(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DISCARD)(input);
    }

    private static ParseTree _KEEP(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("^"), Spacing), "Pegged.KEEP")(s, p);
    }

    static ParseTree KEEP(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_KEEP!false, "Pegged.KEEP", true)(p);
    }

    static ParseTree KEEP(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_KEEP!true, "Pegged.KEEP", true)(p);
    }

    static ParseResult KEEP(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(KEEP)(ctx, input);
    }

    static ParseTree KEEP(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(KEEP)(input);
    }

    private static ParseTree _DROP(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!(";"), Spacing), "Pegged.DROP")(s, p);
    }

    static ParseTree DROP(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DROP!false, "Pegged.DROP", true)(p);
    }

    static ParseTree DROP(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DROP!true, "Pegged.DROP", true)(p);
    }

    static ParseResult DROP(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DROP)(ctx, input);
    }

    static ParseTree DROP(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DROP)(input);
    }

    private static ParseTree _PROPAGATE(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("%"), Spacing), "Pegged.PROPAGATE")(s, p);
    }

    static ParseTree PROPAGATE(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_PROPAGATE!false, "Pegged.PROPAGATE", true)(p);
    }

    static ParseTree PROPAGATE(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_PROPAGATE!true, "Pegged.PROPAGATE", true)(p);
    }

    static ParseResult PROPAGATE(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(PROPAGATE)(ctx, input);
    }

    static ParseTree PROPAGATE(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(PROPAGATE)(input);
    }

    private static ParseTree _OPTION(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("?"), Spacing), "Pegged.OPTION")(s, p);
    }

    static ParseTree OPTION(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_OPTION!false, "Pegged.OPTION", true)(p);
    }

    static ParseTree OPTION(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_OPTION!true, "Pegged.OPTION", true)(p);
    }

    static ParseResult OPTION(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(OPTION)(ctx, input);
    }

    static ParseTree OPTION(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(OPTION)(input);
    }

    private static ParseTree _ZEROORMORE(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("*"), Spacing), "Pegged.ZEROORMORE")(s, p);
    }

    static ParseTree ZEROORMORE(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_ZEROORMORE!false, "Pegged.ZEROORMORE", true)(p);
    }

    static ParseTree ZEROORMORE(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_ZEROORMORE!true, "Pegged.ZEROORMORE", true)(p);
    }

    static ParseResult ZEROORMORE(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(ZEROORMORE)(ctx, input);
    }

    static ParseTree ZEROORMORE(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(ZEROORMORE)(input);
    }

    private static ParseTree _ONEORMORE(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("+"), Spacing), "Pegged.ONEORMORE")(s, p);
    }

    static ParseTree ONEORMORE(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_ONEORMORE!false, "Pegged.ONEORMORE", true)(p);
    }

    static ParseTree ONEORMORE(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_ONEORMORE!true, "Pegged.ONEORMORE", true)(p);
    }

    static ParseResult ONEORMORE(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(ONEORMORE)(ctx, input);
    }

    static ParseTree ONEORMORE(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(ONEORMORE)(input);
    }

    private static ParseTree _ACTIONOPEN(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("{"), Spacing), "Pegged.ACTIONOPEN")(s, p);
    }

    static ParseTree ACTIONOPEN(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_ACTIONOPEN!false, "Pegged.ACTIONOPEN", true)(p);
    }

    static ParseTree ACTIONOPEN(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_ACTIONOPEN!true, "Pegged.ACTIONOPEN", true)(p);
    }

    static ParseResult ACTIONOPEN(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(ACTIONOPEN)(ctx, input);
    }

    static ParseTree ACTIONOPEN(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(ACTIONOPEN)(input);
    }

    private static ParseTree _ACTIONCLOSE(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("}"), Spacing), "Pegged.ACTIONCLOSE")(s, p);
    }

    static ParseTree ACTIONCLOSE(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_ACTIONCLOSE!false, "Pegged.ACTIONCLOSE", true)(p);
    }

    static ParseTree ACTIONCLOSE(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_ACTIONCLOSE!true, "Pegged.ACTIONCLOSE", true)(p);
    }

    static ParseResult ACTIONCLOSE(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(ACTIONCLOSE)(ctx, input);
    }

    static ParseTree ACTIONCLOSE(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(ACTIONCLOSE)(input);
    }

    private static ParseTree _SEPARATOR(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!(","), Spacing), "Pegged.SEPARATOR")(s, p);
    }

    static ParseTree SEPARATOR(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_SEPARATOR!false, "Pegged.SEPARATOR", true)(p);
    }

    static ParseTree SEPARATOR(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_SEPARATOR!true, "Pegged.SEPARATOR", true)(p);
    }

    static ParseResult SEPARATOR(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(SEPARATOR)(ctx, input);
    }

    static ParseTree SEPARATOR(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(SEPARATOR)(input);
    }

    private static ParseTree _ASSIGN(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("="), Spacing), "Pegged.ASSIGN")(s, p);
    }

    static ParseTree ASSIGN(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_ASSIGN!false, "Pegged.ASSIGN", true)(p);
    }

    static ParseTree ASSIGN(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_ASSIGN!true, "Pegged.ASSIGN", true)(p);
    }

    static ParseResult ASSIGN(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(ASSIGN)(ctx, input);
    }

    static ParseTree ASSIGN(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(ASSIGN)(input);
    }

    private static ParseTree _NAMESEP(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(literal!("."), "Pegged.NAMESEP")(s, p);
    }

    static ParseTree NAMESEP(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_NAMESEP!false, "Pegged.NAMESEP", true)(p);
    }

    static ParseTree NAMESEP(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_NAMESEP!true, "Pegged.NAMESEP", true)(p);
    }

    static ParseResult NAMESEP(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(NAMESEP)(ctx, input);
    }

    static ParseTree NAMESEP(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(NAMESEP)(input);
    }

    private static ParseTree _OPEN(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("("), Spacing), "Pegged.OPEN")(s, p);
    }

    static ParseTree OPEN(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_OPEN!false, "Pegged.OPEN", true)(p);
    }

    static ParseTree OPEN(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_OPEN!true, "Pegged.OPEN", true)(p);
    }

    static ParseResult OPEN(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(OPEN)(ctx, input);
    }

    static ParseTree OPEN(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(OPEN)(input);
    }

    private static ParseTree _CLOSE(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!(")"), Spacing), "Pegged.CLOSE")(s, p);
    }

    static ParseTree CLOSE(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_CLOSE!false, "Pegged.CLOSE", true)(p);
    }

    static ParseTree CLOSE(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_CLOSE!true, "Pegged.CLOSE", true)(p);
    }

    static ParseResult CLOSE(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(CLOSE)(ctx, input);
    }

    static ParseTree CLOSE(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(CLOSE)(input);
    }

    private static ParseTree _ANY(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("."), Spacing), "Pegged.ANY")(s, p);
    }

    static ParseTree ANY(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_ANY!false, "Pegged.ANY", true)(p);
    }

    static ParseTree ANY(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_ANY!true, "Pegged.ANY", true)(p);
    }

    static ParseResult ANY(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(ANY)(ctx, input);
    }

    static ParseTree ANY(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(ANY)(input);
    }

    private static ParseTree _Spacing(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(discard!(zeroOrMore!(or!(blank, Comment))), "Pegged.Spacing")(s, p);
    }

    static ParseTree Spacing(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Spacing!false, "Pegged.Spacing", true)(p);
    }

    static ParseTree Spacing(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Spacing!true, "Pegged.Spacing", true)(p);
    }

    static ParseResult Spacing(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Spacing)(ctx, input);
    }

    static ParseTree Spacing(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Spacing)(input);
    }

    private static ParseTree _Comment(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("#"), zeroOrMore!(and!(negLookahead!(eol), any)), discard!(eol)),
                "Pegged.Comment")(s, p);
    }

    static ParseTree Comment(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Comment!false, "Pegged.Comment", true)(p);
    }

    static ParseTree Comment(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Comment!true, "Pegged.Comment", true)(p);
    }

    static ParseResult Comment(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Comment)(ctx, input);
    }

    static ParseTree Comment(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Comment)(input);
    }

    private static ParseTree _Space(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(spacing, literal!("\\t"), literal!("\\n"), literal!("\\r")), "Pegged.Space")(
                s, p);
    }

    static ParseTree Space(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Space!false, "Pegged.Space", true)(p);
    }

    static ParseTree Space(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Space!true, "Pegged.Space", true)(p);
    }

    static ParseResult Space(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Space)(ctx, input);
    }

    static ParseTree Space(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Space)(input);
    }

    private static ParseTree _Action(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(discard!(ACTIONOPEN), Spacing, and!(or!(Lambda,
                qualifiedIdentifier), zeroOrMore!(and!(discard!(SEPARATOR), or!(Lambda, qualifiedIdentifier)))),
                Spacing, discard!(ACTIONCLOSE)), "Pegged.Action")(s, p);
    }

    static ParseTree Action(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Action!false, "Pegged.Action", true)(p);
    }

    static ParseTree Action(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Action!true, "Pegged.Action", true)(p);
    }

    static ParseResult Action(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Action)(ctx, input);
    }

    static ParseTree Action(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Action)(input);
    }

    private static ParseTree _Lambda(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(fuse!(zeroOrMore!(and!(negLookahead!(or!(ACTIONCLOSE, SEPARATOR)),
                or!(LambdaItems, NestedList!(literal!("{"), LambdaItems, literal!("}")), any)))), "Pegged.Lambda")(
                s, p);
    }

    static ParseTree Lambda(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_Lambda!false, "Pegged.Lambda", true)(p);
    }

    static ParseTree Lambda(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_Lambda!true, "Pegged.Lambda", true)(p);
    }

    static ParseResult Lambda(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(Lambda)(ctx, input);
    }

    static ParseTree Lambda(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(Lambda)(input);
    }

    private static ParseTree _LambdaItems(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(fuse!(DComment), fuse!(DString), fuse!(DParamList)), "Pegged.LambdaItems")(
                s, p);
    }

    static ParseTree LambdaItems(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_LambdaItems!false, "Pegged.LambdaItems", true)(p);
    }

    static ParseTree LambdaItems(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_LambdaItems!true, "Pegged.LambdaItems", true)(p);
    }

    static ParseResult LambdaItems(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(LambdaItems)(ctx, input);
    }

    static ParseTree LambdaItems(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(LambdaItems)(input);
    }

    private static ParseTree _DString(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(WYSString, DBQString, TKNString, DLMString), "Pegged.DString")(s, p);
    }

    static ParseTree DString(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DString!false, "Pegged.DString", true)(p);
    }

    static ParseTree DString(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DString!true, "Pegged.DString", true)(p);
    }

    static ParseResult DString(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DString)(ctx, input);
    }

    static ParseTree DString(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DString)(input);
    }

    private static ParseTree _WYSString(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(and!(literal!("r"), doublequote,
                zeroOrMore!(and!(negLookahead!(doublequote), any)), doublequote), and!(backquote,
                zeroOrMore!(and!(negLookahead!(backquote), any)), backquote)), "Pegged.WYSString")(s, p);
    }

    static ParseTree WYSString(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_WYSString!false, "Pegged.WYSString", true)(p);
    }

    static ParseTree WYSString(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_WYSString!true, "Pegged.WYSString", true)(p);
    }

    static ParseResult WYSString(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(WYSString)(ctx, input);
    }

    static ParseTree WYSString(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(WYSString)(input);
    }

    private static ParseTree _DBQString(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(doublequote, zeroOrMore!(and!(negLookahead!(doublequote), Char)),
                doublequote), "Pegged.DBQString")(s, p);
    }

    static ParseTree DBQString(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DBQString!false, "Pegged.DBQString", true)(p);
    }

    static ParseTree DBQString(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DBQString!true, "Pegged.DBQString", true)(p);
    }

    static ParseResult DBQString(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DBQString)(ctx, input);
    }

    static ParseTree DBQString(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DBQString)(input);
    }

    private static ParseTree _TKNString(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(posLookahead!(literal!("q{")), and!(literal!("q"),
                NestedList!(literal!("{"), DString, literal!("}")))), "Pegged.TKNString")(s, p);
    }

    static ParseTree TKNString(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_TKNString!false, "Pegged.TKNString", true)(p);
    }

    static ParseTree TKNString(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_TKNString!true, "Pegged.TKNString", true)(p);
    }

    static ParseResult TKNString(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(TKNString)(ctx, input);
    }

    static ParseTree TKNString(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(TKNString)(input);
    }

    private static ParseTree _DLMString(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(and!(literal!("q"), doublequote),
                or!(and!(posLookahead!(literal!("{")), NestedList!(literal!("{"), DString, literal!("}"))),
                and!(posLookahead!(literal!("[")), NestedList!(literal!("["), DString, literal!("]"))),
                and!(posLookahead!(literal!("(")), NestedList!(literal!("("), DString, literal!(")"))),
                and!(posLookahead!(literal!("<")), NestedList!(literal!("<"), DString, literal!(">")))),
                doublequote), "Pegged.DLMString")(s, p);
    }

    static ParseTree DLMString(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DLMString!false, "Pegged.DLMString", true)(p);
    }

    static ParseTree DLMString(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DLMString!true, "Pegged.DLMString", true)(p);
    }

    static ParseResult DLMString(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DLMString)(ctx, input);
    }

    static ParseTree DLMString(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DLMString)(input);
    }

    private static ParseTree _DComment(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(or!(DLineComment, DBlockComment, DNestingBlockComment), "Pegged.DComment")(s, p);
    }

    static ParseTree DComment(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DComment!false, "Pegged.DComment", true)(p);
    }

    static ParseTree DComment(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DComment!true, "Pegged.DComment", true)(p);
    }

    static ParseResult DComment(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DComment)(ctx, input);
    }

    static ParseTree DComment(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DComment)(input);
    }

    private static ParseTree _DLineComment(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("//"), zeroOrMore!(and!(negLookahead!(endOfLine), any)),
                endOfLine), "Pegged.DLineComment")(s, p);
    }

    static ParseTree DLineComment(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DLineComment!false, "Pegged.DLineComment", true)(p);
    }

    static ParseTree DLineComment(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DLineComment!true, "Pegged.DLineComment", true)(p);
    }

    static ParseResult DLineComment(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DLineComment)(ctx, input);
    }

    static ParseTree DLineComment(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DLineComment)(input);
    }

    private static ParseTree _DBlockComment(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(and!(literal!("/*"), zeroOrMore!(and!(negLookahead!(literal!("*/")),
                any)), literal!("*/")), "Pegged.DBlockComment")(s, p);
    }

    static ParseTree DBlockComment(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DBlockComment!false, "Pegged.DBlockComment", true)(p);
    }

    static ParseTree DBlockComment(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DBlockComment!true, "Pegged.DBlockComment", true)(p);
    }

    static ParseResult DBlockComment(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DBlockComment)(ctx, input);
    }

    static ParseTree DBlockComment(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DBlockComment)(input);
    }

    private static ParseTree _DNestingBlockComment(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(NestedList!(literal!("/+"), literal!("+/")), "Pegged.DNestingBlockComment")(s,
                p);
    }

    static ParseTree DNestingBlockComment(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DNestingBlockComment!false, "Pegged.DNestingBlockComment", true)(p);
    }

    static ParseTree DNestingBlockComment(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DNestingBlockComment!true, "Pegged.DNestingBlockComment", true)(p);
    }

    static ParseResult DNestingBlockComment(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DNestingBlockComment)(ctx, input);
    }

    static ParseTree DNestingBlockComment(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DNestingBlockComment)(input);
    }

    private static ParseTree _DParamList(bool CT)(ref State!CT s, size_t p) nothrow {
        return defined!(NestedList!(literal!("("), literal!(")")), "Pegged.DParamList")(s, p);
    }

    static ParseTree DParamList(ref State!false s, size_t p) @nogc nothrow {
        return s.rule!(_DParamList!false, "Pegged.DParamList", true)(p);
    }

    static ParseTree DParamList(CompileTime = void)(ref State!true s, size_t p) nothrow {
        return s.rule!(_DParamList!true, "Pegged.DParamList", true)(p);
    }

    static ParseResult DParamList(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(DParamList)(ctx, input);
    }

    static ParseTree DParamList(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(DParamList)(input);
    }

    template NestedList(alias L, alias Items, alias R) {
        private static ParseTree _NestedList(bool CT)(ref State!CT s, size_t p) nothrow {
            return defined!(and!(keep!(L), zeroOrMore!(and!(negLookahead!(or!(L, R, Items)),
                    any)), zeroOrMore!(or!(Items, NestedList!(L, Items, R),
                    zeroOrMore!(and!(negLookahead!(or!(L, R, Items)), any)))),
                    zeroOrMore!(and!(negLookahead!(or!(L, R, Items)), any)), keep!(R)), "Pegged.NestedList")(
                    s, p);
        }

        static ParseTree _entry(ref State!false s, size_t p) @nogc nothrow {
            return s.rule!(_NestedList!false, "Pegged.NestedList", true)(p);
        }

        static ParseTree _entry(CompileTime = void)(ref State!true s, size_t p) nothrow {
            return s.rule!(_NestedList!true, "Pegged.NestedList", true)(p);
        }

        static ParseResult _entry(Context)(ref Context ctx, string input) @nogc nothrow 
                if (is(Context == ParseContext)) {
            return parse!(_entry)(ctx, input);
        }

        static ParseTree _entry(Input)(Input input) nothrow if (is(Input == string)) {
            return parseCT!(_entry)(input);
        }

        alias NestedList = _entry;
    }

    template NestedList(alias L, alias R) {
        private static ParseTree _NestedList(bool CT)(ref State!CT s, size_t p) nothrow {
            return defined!(and!(keep!(L), zeroOrMore!(and!(negLookahead!(or!(L, R)), any)),
                    zeroOrMore!(or!(NestedList!(L, R), zeroOrMore!(and!(negLookahead!(or!(L, R)), any)))),
                    zeroOrMore!(and!(negLookahead!(or!(L, R)), any)), keep!(R)), "Pegged.NestedList")(
                    s, p);
        }

        static ParseTree _entry(ref State!false s, size_t p) @nogc nothrow {
            return s.rule!(_NestedList!false, "Pegged.NestedList", true)(p);
        }

        static ParseTree _entry(CompileTime = void)(ref State!true s, size_t p) nothrow {
            return s.rule!(_NestedList!true, "Pegged.NestedList", true)(p);
        }

        static ParseResult _entry(Context)(ref Context ctx, string input) @nogc nothrow 
                if (is(Context == ParseContext)) {
            return parse!(_entry)(ctx, input);
        }

        static ParseTree _entry(Input)(Input input) nothrow if (is(Input == string)) {
            return parseCT!(_entry)(input);
        }

        alias NestedList = _entry;
    }

    static ParseTree opCall(ref State!false s, size_t p) @nogc nothrow {
        auto t = Grammar(s, p);
        t.name = "Pegged";
        return t;
    }

    static ParseTree opCall(CompileTime = void)(ref State!true s, size_t p) nothrow {
        auto t = Grammar(s, p);
        t.name = "Pegged";
        return t;
    }

    static ParseResult opCall(Context)(ref Context ctx, string input) @nogc nothrow 
            if (is(Context == ParseContext)) {
        return parse!(opCall)(ctx, input);
    }

    static ParseTree opCall(Input)(Input input) nothrow if (is(Input == string)) {
        return parseCT!(opCall)(input);
    }
}

@nogc nothrow unittest {
    ParseContext context;
    enum definition = "Tiny: A <- 'a' eoi";
    auto valid = Pegged(context, definition);
    assert(valid.successful && valid.end == definition.length);
    auto invalid = Pegged(context, "Tiny: A <- (");
    assert(!invalid.successful);
    auto space = Pegged.Space(context, "\t\n");
    assert(space.successful && space.end == 2);
}
