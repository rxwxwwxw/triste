module benchmark.json_grammar;
import benchmark.json_output : NodeKind;

// One grammar definition for both tree engines. Explicit JSON whitespace only.
enum jsonGrammar = `
JSON:
    Document <- Spacing Value Spacing eoi
    Value <- Object / Array / String / Number / True / False / Null
    True <- 'true'
    False <- 'false'
    Null <- 'null'
    Object <- '{' Spacing (Pair (Spacing ',' Spacing Pair)*)? Spacing '}'
    Pair <- String Spacing ':' Spacing Value
    Array <- '[' Spacing (Value (Spacing ',' Spacing Value)*)? Spacing ']'
    String <- doublequote (backslash (doublequote / backslash / '/' / [bfnrt]
              / 'u' [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]) / Unescaped)* doublequote
    Unescaped <~ (!(doublequote / backslash / [\u0000-\u001f]) .)+
    Number <- '-'? ('0' / [1-9] [0-9]*) ('.' [0-9]+)? ([eE] ('+' / '-')? [0-9]+)?
    Spacing <: [ \t\r\n]*
`;

uint treeTag(string name) @nogc nothrow pure {
    switch (name) {
    case "JSON.Object":
        return cast(uint)NodeKind.object;
    case "JSON.Array":
        return cast(uint)NodeKind.array;
    case "JSON.String":
    case "Ambiguous.Start":
        return cast(uint)NodeKind.string_;
    case "JSON.Number":
        return cast(uint)NodeKind.number;
    case "JSON.True":
        return cast(uint)NodeKind.true_;
    case "JSON.False":
        return cast(uint)NodeKind.false_;
    case "JSON.Null":
        return cast(uint)NodeKind.null_;
    default:
        return uint.max;
    }
}

@nogc nothrow pure unittest {
    assert(treeTag("JSON.Object") == cast(uint)NodeKind.object);
    assert(treeTag("JSON.Array") == cast(uint)NodeKind.array);
    assert(treeTag("JSON.String") == treeTag("Ambiguous.Start"));
    assert(treeTag("JSON.Number") == cast(uint)NodeKind.number);
    assert(treeTag("JSON.True") == cast(uint)NodeKind.true_);
    assert(treeTag("JSON.False") == cast(uint)NodeKind.false_);
    assert(treeTag("JSON.Null") == cast(uint)NodeKind.null_);
    assert(treeTag("JSON.Value") == uint.max);
}

uint spanTag(string name) @nogc nothrow pure {
    auto tag = treeTag(name);
    return tag == cast(uint)NodeKind.object || tag == cast(uint)NodeKind.array ? uint.max : tag;
}

@nogc nothrow pure unittest {
    assert(spanTag("JSON.Object") == uint.max && spanTag("JSON.Array") == uint.max);
    assert(spanTag("JSON.String") == cast(uint)NodeKind.string_);
}
