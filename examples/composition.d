// Converted from Pegged examples; Boost Software License 1.0.
/**
 * Example of grammar composition in Pegged
 */
module npegged.examples.composition;

import npegged.grammar;
import npegged.examples.strings, npegged.examples.numbers;

mixin(grammar(`
LOG:
    LogFile <- LogLine+ eoi
    LogLine <  String ':' Numbers (',' Numbers)* eol?
`));

@nogc nothrow unittest {
    ParseContext context;
    auto log = `
"File1": 0.00, 0.01, 0.00, 0.00
"File2": 1.0, 2.0, 3.14
"File3": 0.00, 10
`;
    assert(LOG(context, log).successful);
}

enum g = grammar(`
LOG2:
    LogFile <- LogLine+ eoi
    LogLine < String Numbers.Hexa ':' Numbers (',' Numbers)*
`);
mixin(g);

@nogc nothrow unittest {
    ParseContext context;
    enum log = `
"File1" 123AC7AF   : 123, 78.265, 0.00
"File2" 31F039DC9BE : 49.45, 42.220, 0.02, -22.3
"File3" D0043869930 : 0
    `;
    assert(LOG2(context, log).successful);
}
