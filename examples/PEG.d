// Converted from Pegged examples; Boost Software License 1.0.
module npegged.examples.PEG;

import npegged.grammar;

enum string PEGGgrammar = `
PEG:

Grammar     <- S Definition+ EOI
Definition  <- Name Arrow Expression S
Expression  <- Sequence (OR Sequence)*
Sequence    <- Prefix+
Prefix      <- (LOOKAHEAD / NOT)? Suffix
Suffix      <- Primary ( OPTION
                       / ONEORMORE
                       / ZEROORMORE )? S
Primary     <- Name !Arrow
             / GroupExpr
             / Literal
             / Class
             / ANY
Name        <- identifier S
GroupExpr   <- OPEN Expression :CLOSE S
Literal     <- quote (!quote Char)* quote S
             / doublequote (!doublequote Char)* doublequote S
Class       <- '[' (!']' CharRange)* ']' S
CharRange   <- Char '-' Char / Char
Char        <- backslash ( quote
                         / doublequote
                         / backquote
                         / backslash
                         / [nrt]
                         / [0-2][0-7][0-7]
                         / [0-7][0-7]?)
             / !backslash .
# Terminals
Arrow       <- "<-" S
OR          <- '/' S
LOOKAHEAD   <- '&' S
NOT         <- '!' S
OPTION      <- '?' S
ZEROORMORE  <- '*' S
ONEORMORE   <- '+' S
OPEN        <- '(' S
CLOSE       <- ')' S
ANY         <- '.' S
# Blanks
EOL         <- '\r\n' / '\n' / '\r'
Comment     <- "#" (!EOL .)* (EOL/EOI)
S           <- (' ' / '\t' / EOL / Comment)*
EOI         <- !.
`;

// TODO: add unit tests on simple grammars

mixin(grammar(PEGGgrammar));
