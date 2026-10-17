/** R06 parser oracle. Run with scripts/shared-output-check.sh bounds. */
module tests.shared_output;
import npegged.grammar;
import npegged.records : CompactNode;
import core.sys.posix.unistd : alarm;
import core.stdc.stdio : printf;

version (NPeggedDirect)
    private enum backend = ParserBackend.direct;
else
    private enum backend = ParserBackend.combinators;
version (NPeggedFullMemo)
    private enum memo = Memoization.yes;
else
    private enum memo = Memoization.selective;
private uint selected(string name) @nogc nothrow pure {
    return name.length >= 5 && name[$ - 5 .. $] == ".Root" ? 0 : 1;
}

mixin(grammar!(memo, selected, backend)(`
SharedDirect:
    Root <- Expr eoi
    Expr <- Expr '+' Atom / Atom
    Atom <- '(' Expr ')' / 'n'
`));
mixin(grammar!(memo, selected, backend)(`
SharedIndirect:
    Root <- Expr eoi
    Expr <- Sum / Atom
    Sum <- Expr '+' Atom
    Atom <- '(' Expr ')' / 'n'
`));
mixin(grammar!(memo, selected, backend)(`
SharedMutual:
    Root <- A eoi
    A <- B 'a' / 'n'
    B <- A 'b' / 'n'
`));
mixin(grammar!(memo, selected, backend)(`
SharedNullable:
    Root <- A eoi
    A <- A 'n' / eps
`));
mixin(grammar!(memo, selected, backend)(`
SharedProbe:
    Root <- &Expr Expr eoi
    Expr <- Expr '+' Atom / Atom
    Atom <- '(' Expr ')' / 'n'
`));
mixin(grammar!(memo, selected, backend)(`
SharedReplace:
    Root <- Expr eoi
    Expr <- Expr 'n' / 'n' 'n' / 'n'
`));
private template Types(T...) {
    alias Types = T;
}

private void compare(alias Parser, bool owned)(string input, size_t steps = size_t.max,
        size_t depth = size_t.max, size_t memory = size_t.max, size_t output = size_t.max) @nogc nothrow {
    ParseContext before, after;
    before.stepLimit = after.stepLimit = steps;
    before.depthLimit = after.depthLimit = depth;
    before.memoryLimit = after.memoryLimit = memory;
    after.sharedOutput = true;
    auto reference = parseRecords!(Parser, selected, owned)(before, input, output);
    auto candidate = parseRecords!(Parser, selected, owned)(after, input, output);
    assert(reference.status == candidate.status);
    assert(reference.successful == candidate.successful);
    assert(reference.end == candidate.end && reference.failEnd == candidate.failEnd);
    assert(reference.nodes == candidate.nodes);
    static if (owned)
        assert(reference.input == candidate.input);
}

int main() @nogc nothrow {
    alarm(45);
    static foreach (Parser; Types!(SharedDirect, SharedIndirect, SharedMutual, SharedNullable,
            SharedProbe, SharedReplace)) {
        foreach (input; [
            "", "n", "nn", "nnn", "n+n", "n+n+n", "(n+n)+n", "((n)+n)", "n+", "n+n+", "(n",
            "nab", "nbaba", "\0", "é"
        ]) {
            compare!(Parser.opCall, true)(input);
            compare!(Parser.opCall, false)(input);
            foreach (limit; [0, 1, 4, 16, 64, 1024]) {
                compare!(Parser.opCall, true)(input, cast(size_t)limit);
                compare!(Parser.opCall, true)(input, size_t.max, cast(size_t)limit);
                compare!(Parser.opCall, true)(input, size_t.max, size_t.max, cast(size_t)limit);
                compare!(Parser.opCall, true)(input, size_t.max, size_t.max, size_t.max, cast(size_t)limit);
            }
        }
    }
    char[256] input;
    foreach (i, ref c; input)
        c = i % 2 ? '+' : 'n';
    compare!(SharedDirect.opCall, true)(cast(string)input[0 .. 255]);
    compare!(SharedIndirect.opCall, false)(cast(string)input[0 .. 255]);
    printf("shared output oracle passed\n");
    return 0;
}
