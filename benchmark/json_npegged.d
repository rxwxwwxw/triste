module benchmark.json_npegged;
import npegged.grammar;
import benchmark.json_grammar : jsonGrammar;

mixin(grammar(jsonGrammar));
