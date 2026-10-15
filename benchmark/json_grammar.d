module benchmark.json_grammar;

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
    String <- doublequote Char* doublequote
    Char <- backslash (doublequote / backslash / '/' / [bfnrt] / 'u' Hex Hex Hex Hex)
          / !(doublequote / backslash / [\u0000-\u001f]) .
    Number <- '-'? ('0' / [1-9] [0-9]*) ('.' [0-9]+)? ([eE] ('+' / '-')? [0-9]+)?
    Hex <- [0-9a-fA-F]
    Spacing <: [ \t\r\n]*
`;
