// Grammar self-hosting example derived from Pegged (Boost 1.0).
module npegged.examples.peggedgrammar;
public import npegged.definition;
import npegged.grammar;

mixin(grammar(PEGGEDgrammar));
