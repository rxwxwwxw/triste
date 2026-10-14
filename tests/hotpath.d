// Compile with GC diagnostics; this entry point and all runtime parsers are @nogc.
module tests.hotpath;
import npegged.grammar;

mixin(grammar("Hot: Start <- (~[0-9]+ (':' ~[a-z]+)?) :eoi"));
void main() @nogc nothrow {
    ParseContext context;
    auto result = Hot(context, "42:hello");
    assert(result.status == Status.ok);
}
