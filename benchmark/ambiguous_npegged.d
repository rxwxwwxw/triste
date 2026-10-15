module benchmark.ambiguous_npegged;
import npegged.grammar;

mixin(grammar(`Ambiguous:
    Start <- ('a'* 'b' / 'a'* 'c') eoi
`));
