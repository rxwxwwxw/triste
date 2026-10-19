/** X07: exact contract audit of the manual X03 prototype, not a speed gate. */
module tests.test_recursive_ascent;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;
import npegged.grammar;

mixin(grammar(`
LeftChain:
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));
mixin(grammar(`
BranchChain:
    Expr <- Expr '+' Atom / Atom
    Atom <- '(' Expr ')' / Number
    Number <- ~[0-9]+
`));

private __gshared size_t ascentCalls;
private struct ManualAscent(alias Base, string name) {
    static ParseTree opCall(ref State!(false, 0) state, size_t position) @nogc nothrow {
        ++ascentCalls;
        alias Suffix = and!(literal!"+", Base);
        // The generated reference uses defined() at its public boundary too.
        return defined!(directAscent!(Base, Suffix, name), name)(state, position);
    }
}

private string difference(scope const ref ParseTree a, scope const ref ParseTree b) @nogc nothrow {
    static foreach (field; ["name", "input", "successful", "begin", "end", "failEnd", "matches"])
        if (__traits(getMember, a, field) != __traits(getMember, b, field))
            return "tree." ~ field;
    if (a.children.length != b.children.length)
        return "tree.children.length";
    if (a.failedChild.length != b.failedChild.length)
        return "tree.failedChild.length";
    foreach (i; 0 .. a.children.length) {
        auto found = difference(a.children[i], b.children[i]);
        if (found.length)
            return found;
    }
    foreach (i; 0 .. a.failedChild.length) {
        auto found = difference(a.failedChild[i], b.failedChild[i]);
        if (found.length)
            return found;
    }
    return "";
}

@nogc nothrow unittest {
    ParseTree a, b;
    assert(!difference(a, b).length);
    b.failEnd = 1;
    assert(difference(a, b) == "tree.failEnd");
    b = a;
    b.input = "x";
    assert(difference(a, b) == "tree.input");
    ParseTree[1] left, right;
    a.failedChild = left[];
    b = a;
    b.failedChild = right[];
    right[0].end = 1;
    assert(difference(a, b) == "tree.end");
}

private ParseContext unlimited() @nogc nothrow {
    ParseContext context;
    context.stepLimit = context.depthLimit = context.memoryLimit = size_t.max;
    return context;
}

private size_t cases, mismatches;
private void compare(alias Reference, alias Candidate)(uint repeat, string family, string input, ParseContext context) @nogc nothrow {
    auto reference = parse!Reference(context, input);
    auto candidate = parse!Candidate(context, input);
    auto field = difference(reference.tree, candidate.tree);
    const equal = reference.status == candidate.status && !field.length;
    ++cases;
    if (!equal)
        ++mismatches;
    if (context.stepLimit == 0 || context.depthLimit == 0 || context.memoryLimit == 0) {
        assert(reference.status == Status.resourceLimit && !reference.successful);
        assert(candidate.status == Status.resourceLimit && !candidate.successful);
    }
    if (family == "flat" && input == "1" && context.stepLimit == size_t.max
            && context.depthLimit == size_t.max && context.memoryLimit == size_t.max)
        assert(equal);
    if (family == "flat" && input == "1+1" && context.stepLimit == size_t.max
            && context.depthLimit == size_t.max && context.memoryLimit == size_t.max) {
        // Known limitation: the prior comparator omitted this field.
        assert(reference.status == Status.ok && candidate.status == Status.ok);
        assert(field == "tree.failEnd");
        assert(!equal);
    }
    printf("%s{\"repeat\":%u,\"family\":\"%.*s\",\"inputHex\":\"", cases == 1 ? "".ptr : ",\n".ptr,
            repeat, cast(int)family.length, family.ptr);
    foreach (b; input)
        printf("%02x", cast(uint)cast(ubyte)b);
    printf("\",\"limits\":[%llu,%llu,%llu],\"reference\":[%u,%u,%llu,%llu],\"candidate\":[%u,%u,%llu,%llu],\"completeEqual\":%s,\"difference\":\"%.*s\",\"innerFailEnd\":[%llu,%llu]}",
            cast(ulong)context.stepLimit, cast(ulong)context.depthLimit,
            cast(ulong)context.memoryLimit, cast(uint)reference.status,
            cast(uint)reference.successful, cast(ulong)reference.end, cast(ulong)reference.failEnd,
            cast(uint)candidate.status, cast(uint)candidate.successful, cast(ulong)candidate.end,
            cast(ulong)candidate.failEnd, equal ? "true".ptr : "false".ptr, cast(int)field.length,
            field.ptr, cast(ulong)(reference.tree.children.length
                ? reference.tree.children[0].failEnd : size_t.max), cast(ulong)(
                candidate.tree.children.length ? candidate.tree.children[0].failEnd : size_t.max));
}

int main() @nogc nothrow {
    alarm(45);
    alias Flat = ManualAscent!(LeftChain.Number, "LeftChain.Expr").opCall;
    alias Branch = ManualAscent!(BranchChain.Atom, "BranchChain.Expr").opCall;
    printf("{\"schemaVersion\":2,\"repetitions\":7,\"generalEquivalent\":false,\"cases\":[\n");
    foreach (repeat; 1 .. 8) {
        foreach (input; ["1", "12", "1+1", "1+2+3+4", "", "x", "1+", "1++1", "1+2+x"])
            compare!(LeftChain.Expr, Flat)(repeat, "flat", input, unlimited());
        foreach (input; ["(1)", "(1+2)+3", "1+(2+3)", "((1)+2)+(3+4)", "(1+", "1+()"])
            compare!(BranchChain.Expr, Branch)(repeat, "branch", input, unlimited());
        foreach (limit; [0, 1, 2, 3, 4, 8, 16, 64]) {
            auto context = unlimited();
            context.stepLimit = limit;
            compare!(LeftChain.Expr, Flat)(repeat, "step", "1+2+3", context);
            context = unlimited();
            context.depthLimit = limit;
            compare!(LeftChain.Expr, Flat)(repeat, "depth", "1+2+3", context);
        }
        foreach (limit; [0, 1, 16, 4095, 4096, 4097, 65536]) {
            auto context = unlimited();
            context.memoryLimit = limit;
            compare!(LeftChain.Expr, Flat)(repeat, "memory", "1+2+3", context);
        }
        char[127] chain;
        foreach (i, ref c; chain)
            c = i % 2 ? '+' : '1';
        auto shallow = unlimited();
        shallow.depthLimit = 16;
        auto reference = parse!(LeftChain.Expr)(shallow, cast(string)chain[]);
        auto candidate = parse!Flat(shallow, cast(string)chain[]);
        // Seed growth is iterative; term count does not equal call depth.
        assert(reference.status == Status.ok && reference.successful);
        assert(candidate.status == Status.ok && candidate.successful);
        compare!(LeftChain.Expr, Flat)(repeat, "depth64terms", cast(string)chain[], shallow);
    }
    assert(mismatches > 0 && ascentCalls > 0);
    printf("\n],\"comparisonCount\":%llu,\"completeParityFailures\":%llu,\"ascentCalls\":%llu,\"disposition\":\"SPECIALIZED_MANUAL_ONLY\"}\n",
            cast(ulong)cases, cast(ulong)mismatches, cast(ulong)ascentCalls);
    printf("recursive ascent oracle passed\n");
    return 0;
}
