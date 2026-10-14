// Derived from Pegged's DConf2017 demonstration (Boost 1.0).
module recursion;
import npegged.grammar;
import core.stdc.stdio : fwrite, fflush, stdout;

mixin(grammar("Right: R <- 'n+' R / 'n'"));
int main() @nogc nothrow {
    ParseContext context;
    auto result = Right(context, "n+n");
    auto text = result.toString;
    assert(result.status == Status.ok && result.end == 3);
    auto written = fwrite(text.data.ptr, 1, text.data.length, stdout);
    auto flushed = fflush(stdout);
    return ((written == text.data.length) & (flushed == 0)) ? 0 : 2;
}
