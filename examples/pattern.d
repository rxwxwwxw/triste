// Converted from Pegged (Boost Software License 1.0).
/**
This module is an attempt at introducing pattern-matching in D.

Pattern matching is a type- or value-matching present in functional languages like ML or Haskell.

The goal here is to obtain code like:

----
Pattern!"[ a, b, ... ]" p1; // match any range with at least two elements
                            // the rest being discarded.

auto m1 = p1([0,1,2,3,4]); // match and associate 'a' and 'b' with O and 1.
assert(m1.a == 0 && m1.b == 1);
auto m2 = p1("abc");
assert(m2.a = 'a' && m2.b == 'b');
auto m3 = p1(tuple("abc",0)); // not a range, the pattern fails
assert(m3 == matchFailure; // predefined constant

Pattern!"Tuple!(.,.) t" p2; // match any std.typecons.Tuple with two elements, of any type
auto m4 = p2(tuple("abc",0));
assert(m4.t = tuple("abc",0); // only the global pattern is named, and hence captured
assert(p2(tuple("abc")) == matchFailure); // only one member -> failure
assert(p2(tuple("abc",0,1)) == matchFailure); // three members -> failure (the pattern has no trailing ...

Pattern!" . { int, double, double }" p3; // match any aggregate (struct, class)
                                         // with three members being int,double and double, in that order.
----

Don't salivate, it's not implemented yet.
*/
module npegged.examples.pattern;

import npegged.grammar;
import npegged.meta;

mixin(grammar(`
Pattern:
    Global     <  Choice :eoi
    Choice     <  Sequence (:'/' Sequence)*
    Sequence   <  Primary (:',' Primary)*
    Primary    <  (Aggregate / Range / Identifier / Literal / REST / ANY) Name?

    Name       <  identifier
    Aggregate  <  (Identifier / ANY) (Tuple / Record)
    Tuple      <  '{' (Choice (:',' Choice)*)? '}'
    Record     <  '{' Field (','Field)* '}'
    Field      <  Identifier :'=' Choice
    Range      <  '[' (Choice (:',' Choice)*)? ']'
    Identifier <  identifier
    Literal    <  Number / Char / String/ Bool
    Number     <~ Digit+ ('.' Digit*)?
    Digit      <  [0-9]
    Char       <~ quote . quote # TODO: adding escape chars and Unicode chars
    String     <~ doublequote (!doublequote .)* doublequote
    Bool       <  "true" / "false"

    REST       <  "..."
    ANY        <  "."
    Spacing    <: spacing
`));

template TypeFailure(T...) {
    enum successful = false;
    alias TypeTuple!() Types;
    enum begin = 0;
    enum end = 0;
    alias T Rest;
}

struct TypeAny {
    template Match(T...) {
        static if (T.length == 0)
            mixin TypeFailure!(T);
        else {
            enum successful = true;
            alias T[0 .. 1] Types;
            enum begin = 0;
            enum end = 1;
            alias T[1 .. $] Rest;
        }
    }
}

struct TypeEnd {
    template Match(T...) {
        static if (T.length == 0) {
            enum successful = true;
            alias TypeTuple!() Types;
            enum begin = 0;
            enum end = 0;
            alias T Rest;
        } else
            mixin TypeFailure!(T);
    }
}

struct TypeEps {
    template Match(T...) {
        enum successful = true;
        alias TypeTuple!() Types;
        enum begin = 0;
        enum end = 0;
        alias T Rest;
    }
}

struct TypeLiteral(U...) {
    template Match(T...) {
        static if (T.length < U.length || !is(T[0 .. U.length] == U))
            mixin TypeFailure!(T);
        else {
            enum successful = true;
            alias T[0 .. U.length] Types;
            enum begin = 0;
            enum end = U.length;
            alias T[U.length .. $] Rest;
        }
    }
}

template isSubtype(T...) {
    static if (T.length == 0)
        enum isSubtype = true;
    else static if (is(T[0] : T[$ / 2]))
        enum isSubtype = isSubtype!(T[1 .. $ / 2], T[$ / 2 + 1 .. $]);
    else
        enum isSubtype = false;
}

struct TypeSubType(U...) {
    template Match(T...) {
        static if (T.length < U.length || !isSubtype!(T[0 .. U.length], U))
            mixin TypeFailure!(T);
        else {
            enum successful = true;
            alias T[0 .. U.length] Types;
            enum begin = 0;
            enum end = U.length;
            alias T[U.length .. $] Rest;
        }
    }
}

struct TypeOr(alias Pattern1, alias Pattern2) {
    template Match(T...) {
        alias Pattern1.Match!(T) P1;
        static if (P1.successful)
            alias P1 Match;
        else
            alias Pattern2.Match!(T) Match;
    }
}

template TypeOr(Patterns...) if (Patterns.length > 2) {
    alias TypeOr!(Patterns[0], TypeOr!(Patterns[1 .. $])) TypeOr;
}

template TypeOr(Patterns...) if (Patterns.length == 1) {
    alias Patterns[0] TypeOr;
}

struct TypeAnd(alias Pattern1, alias Pattern2) {
    template Match(T...) {
        alias Pattern1.Match!(T) P1;
        alias Pattern2.Match!(Pattern1.Match!(T).Rest) P2;
        static if (P1.successful && P2.successful) {
            enum successful = true;
            alias TypeTuple!(P1.Types, P2.Types) Types;
            enum begin = P1.begin;
            enum end = P2.end;
            alias P2.Rest Rest;
        } else
            mixin TypeFailure!(T);
    }
}

template TypeAnd(Patterns...) if (Patterns.length > 2) {
    alias TypeAnd!(Patterns[0], TypeAnd!(Patterns[1 .. $])) TypeAnd;
}

template TypeAnd(Patterns...) if (Patterns.length == 1) {
    alias Patterns[0] TypeAnd;
}

struct TypeOption(alias Pattern) {
    template Match(T...) {
        alias Pattern.Match!(T) P;
        static if (P.successful)
            alias P Match;
        else {
            enum successful = true;
            alias TypeTuple!() Types;
            enum begin = 0;
            enum end = 0;
            alias T Rest;
        }
    }
}

struct TypeZeroOrMore(alias Pattern) {
    template Match(T...) {
        alias Pattern.Match!(T) P;
        static if (P.successful && P.end > P.begin) {
            enum successful = true;
            alias TypeTuple!(P.Types, TypeZeroOrMore!(Pattern).Match!(P.Rest).Types) Types;
            enum begin = P.begin;
            alias TypeZeroOrMore!(Pattern).Match!(P.Rest) More;
            enum end = P.end + More.end;
            alias TypeZeroOrMore!(Pattern).Match!(P.Rest).Rest Rest;
        } else {
            enum successful = true;
            alias TypeTuple!() Types;
            enum begin = 0;
            enum end = 0;
            alias T Rest;
        }
    }
}

struct TypeOneOrMore(alias Pattern) {
    template Match(T...) {
        alias Pattern.Match!(T) P;
        static if (P.successful && P.end > P.begin) {
            enum successful = true;
            alias TypeTuple!(P.Types, TypeZeroOrMore!(Pattern).Match!(P.Rest).Types) Types;
            enum begin = P.begin;
            alias TypeZeroOrMore!(Pattern).Match!(P.Rest) More;
            enum end = P.end + More.end;
            alias TypeZeroOrMore!(Pattern).Match!(P.Rest).Rest Rest;
        } else
            mixin TypeFailure!(T);
    }
}

/**
Discards the matched types, but propagate the indices.
*/
struct TypeDiscardMatch(alias Pattern) {
    template Match(T...) {
        alias Pattern.Match!(T) P;
        static if (P.successful) {
            enum successful = true;
            alias TypeTuple!() Types; // Forget the match,
            enum begin = P.begin; // but propagate indices
            enum end = P.end; //
            alias P.Rest Rest; // and the input
        } else
            mixin TypeFailure!(T);
    }
}

struct TypePosLookAhead(alias Pattern) {
    template Match(T...) {
        alias Pattern.Match!(T) P;
        static if (P.successful) {
            enum successful = true;
            alias TypeTuple!() Types;
            enum begin = 0;
            enum end = 0;
            alias T Rest;
        } else
            mixin TypeFailure!(T);
    }
}

struct TypeNegLookAhead(alias Pattern) {
    template Match(T...) {
        alias Pattern.Match!(T) P;
        static if (P.successful)
            mixin TypeFailure!(T);
        else {
            enum successful = true;
            alias TypeTuple!() Types;
            enum begin = 0;
            enum end = 0;
            alias T Rest;
        }
    }
}

struct isRange {
    template Match(T...) {
        static if (T.length && isInputRange!(T[0])) {
            enum successful = true;
            alias T[0] Types;
            enum begin = 0;
            enum end = 1;
            alias T[1 .. $] Rest;
        } else
            mixin TypeFailure!(T);
    }
}

struct TypeSatisfy(alias test) {
    template Match(T...) {
        static if (T.length && test!(T[0])) {
            enum successful = true;
            alias T[0] Types;
            enum begin = 0;
            enum end = 1;
            alias T[1 .. $] Rest;
        } else
            mixin TypeFailure!(T);
    }
}

struct MatchResult(size_t junction, T...) {
    bool successful;
    T[0 .. junction] match;
    size_t begin;
    size_t end;
    T[junction .. $] rest;
}

struct Success(M...) {
    M match;
    size_t begin;
    size_t end;

    auto rest(R...)(R rest) @nogc nothrow {
        return MatchResult!(M.length, M, R)(true, match, begin, end, rest);
    }
}

Success!(M) success(M...)(M match, size_t begin, size_t end) @nogc nothrow {
    return Success!(M)(match, begin, end);
}

auto failure(R...)(R rest) @nogc nothrow {
    return MatchResult!(0, R)(false, 0, 0, rest);
}

auto anyValue(Args...)(Args args) @nogc nothrow {
    static if (Args.length > 0)
        return success(args[0], 0, 1).rest(args[1 .. $]);
    else
        return failure(args);
}

auto endValue(Args...)(Args args) @nogc nothrow {
    static if (Args.length == 0)
        return success(0, 0).rest(args);
    else
        return failure(args);
}

/+
template literalValue(values...)
{
    auto literalValue(Args...)(Args args)
    {
        if (
            return success(0,values.length).rest(args[values.length..$]);
        else
            return failure(args);
    }
}
+/

/// Slice range matching reports an empty input instead of throwing.
struct RangeResult(T, R) {
    Status status;
    T value;
    R rest;
}

auto rangeAny(R)(R input) @nogc nothrow if (isInputRange!R) {
    alias E = ElementType!R;
    if (!input.length)
        return RangeResult!(E, R)(Status.mismatch, E.init, input);
    return RangeResult!(E, R)(Status.ok, input[0], input[1 .. $]);
}

@nogc nothrow unittest {
    int[3] values = [1, 2, 3];
    auto first = rangeAny(values[]);
    assert(first.status == Status.ok && first.value == 1 && first.rest == values[1 .. $]);
    assert(rangeAny(values[0 .. 0]).status == Status.mismatch);
}

auto rangeRest(R)(R input) @nogc nothrow if (isInputRange!R) {
    return RangeResult!(R, R)(input.length ? Status.ok : Status.mismatch, input, input);
}

@nogc nothrow unittest {
    int[1] value = [1];
    assert(rangeRest(value[]).value == value[]);
    assert(rangeRest(value[0 .. 0]).status == Status.mismatch);
}

template onRange(alias first, alias second, alias third) {
    auto onRange(R)(R input) @nogc nothrow if (isInputRange!R) {
        alias A = typeof(first(input));
        alias B = typeof(second(input));
        alias C = typeof(third(input));
        struct Result {
            Status status;
            typeof(A.init.value) a;
            typeof(B.init.value) b;
            typeof(C.init.value) c;
        }

        auto a = first(input);
        if (a.status != Status.ok)
            return Result(a.status);
        auto b = second(a.rest);
        if (b.status != Status.ok)
            return Result(b.status);
        auto c = third(b.rest);
        return Result(c.status, a.value, b.value, c.value);
    }
}

@nogc nothrow unittest {
    int[3] values = [1, 2, 3];
    auto result = onRange!(rangeAny, rangeAny, rangeAny)(values[]);
    assert(result.status == Status.ok && result.a == 1 && result.b == 2 && result.c == 3);
    assert(onRange!(rangeAny, rangeAny, rangeAny)(values[0 .. 1]).status == Status.mismatch);
}

@nogc nothrow unittest {
    static assert(TypeAny.Match!(int, double).successful);
    static assert(!TypeAny.Match!().successful);
    static assert(TypeEnd.Match!().successful);
    static assert(!TypeEnd.Match!int.successful);
    static assert(TypeEps.Match!int.successful);
    static assert(TypeLiteral!int.Match!(int, double).successful);
    static assert(!TypeLiteral!int.Match!double.successful);
    static assert(TypeAnd!(TypeAny, TypeAny, TypeAny).Match!(int, double, char).successful);
    static assert(TypeOr!(TypeLiteral!int, TypeLiteral!double).Match!double.successful);
    static assert(TypeOption!(TypeLiteral!int).Match!double.successful);
    static assert(TypeZeroOrMore!TypeEps.Match!int.successful);
    static assert(TypeZeroOrMore!TypeAny.Match!(int, double).end == 2);
    static assert(TypeOneOrMore!TypeAny.Match!int.successful);
    static assert(!TypeOneOrMore!TypeAny.Match!().successful);
    assert(anyValue(42).successful);
    assert(!anyValue().successful);
    assert(endValue().successful);
    assert(!endValue(42).successful);
    int[3] values = [1, 2, 3];
    assert(onRange!(rangeAny, rangeAny, rangeAny)(values[0 .. 0]).status == Status.mismatch);
    assert(onRange!(rangeAny, rangeAny, rangeAny)(values[0 .. 2]).status == Status.mismatch);
}
