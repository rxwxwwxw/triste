// Compile with GC diagnostics; this entry point and all runtime parsers are @nogc.
module tests.hotpath;
import npegged.grammar;

mixin(grammar("Hot: Start <- (~[0-9]+ (':' ~[a-z]+)?) :eoi"));
mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(`
DirectHot:
    Root <- Item+ eoi
    Item <- '(' (!')' Item)* ')' / 'a' 'b'?
`));
void main() @nogc nothrow {
    ParseContext context;
    auto result = Hot(context, "42:hello");
    assert(result.status == Status.ok);
    auto checked = check!(DirectHot.opCall)(context, "(ab(a))");
    assert(checked.status == Status.ok);
}
