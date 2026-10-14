// Derived from Pegged's DConf2017 demonstration (Boost 1.0).
module left_recursion_proper;
import npegged.grammar;
import core.stdc.stdio : fwrite, fflush, stdout;

mixin(grammar("Left: R <- R '+n' / 'n'"));
int main() @nogc nothrow {
    ParseContext context;
    auto result = Left(context, "n+n+n");
    auto text = result.toString;
    assert(result.status == Status.ok && result.end == 5);
    auto written = fwrite(text.data.ptr, 1, text.data.length, stdout);
    auto flushed = fflush(stdout);
    return ((written == text.data.length) & (flushed == 0)) ? 0 : 2;
}
