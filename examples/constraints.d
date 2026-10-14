/** Constraint syntax example derived from Pegged (Boost Software License 1.0).
    The upstream prototype referenced undefined reflection helpers. This executable
    example parses boolean template constraints and exposes their constituent nodes. */
module npegged.examples.constraints;
import npegged.grammar;

mixin(grammar(`
Constraint:
    ConstraintExp < AndExp (:'||' AndExp)* :eoi
    AndExp < Primary (:'&&' Primary)*
    Primary < NotExp / Parens / Ident
    NotExp < :'!' Primary
    Parens < :'(' AndExp (:'||' AndExp)* :')'
    Ident <~ identifier
`));

@nogc nothrow unittest {
    ParseContext context;
    auto tree = Constraint(context, "isRange && (!isEmpty || accepts)");
    assert(tree.successful && tree.matches == ["isRange", "isEmpty", "accepts"]);
    auto invalid = Constraint(context, "x &&");
    assert(!invalid.successful);
}
