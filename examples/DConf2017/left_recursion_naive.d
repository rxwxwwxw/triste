// Derived from Pegged's DConf2017 demonstration (Boost 1.0).
// The naive algorithm is bounded explicitly rather than overflowing the process stack.
module left_recursion_naive;
import npegged.grammar;

ParseTree naive(ref State!false state, size_t pos) @nogc nothrow {
    if (state.depth >= state.context.depthLimit) {
        state.status = Status.resourceLimit;
        return state.node(pos, pos, false);
    }
    ++state.depth;
    scope (exit)
        --state.depth;
    return or!(and!(naive, literal!"+n"), literal!"n")(state, pos);
}

int main() @nogc nothrow {
    ParseContext context;
    context.depthLimit = 16;
    auto result = parse!naive(context, "n+n");
    assert(result.status == Status.resourceLimit);
    return 0;
}
