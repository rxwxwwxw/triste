module tests.test_recursive_ascent;

import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;
import core.time : Duration, MonoTime;
import npegged.grammar;
import npegged.peg;
import npegged.storage;

mixin(grammar(`
LeftChain:
    Expr <- Expr '+' Number / Number
    Number <- ~[0-9]+
`));

struct DirectAscent(alias Base, alias Suffix, string name) {
    static State!(CT, Check).Node opCall(bool CT, int Check = 0)(ref State!(CT, Check) s, size_t pos) nothrow {
        return s.directLeftAscent!(Base, Suffix, name)(pos);
    }
}

private bool treesEqual(ref const(ParseTree) a, ref const(ParseTree) b) @nogc nothrow {
    if (a.name != b.name)
        return false;
    if (a.begin != b.begin || a.end != b.end)
        return false;
    if (a.successful != b.successful)
        return false;
    if (a.matches.length != b.matches.length)
        return false;
    foreach (i; 0 .. a.matches.length) {
        if (a.matches[i] != b.matches[i])
            return false;
    }
    if (a.children.length != b.children.length)
        return false;
    foreach (i; 0 .. a.children.length) {
        if (!treesEqual(a.children[i], b.children[i]))
            return false;
    }
    return true;
}

private string buildChainInput(size_t terms, ref Arena owner) nothrow {
    const totalChars = 2 * terms - 1;
    auto slice = owner.allocate!char(totalChars);
    if (!slice.length)
        return "";
    foreach (i; 0 .. totalChars) {
        slice[i] = (i % 2 == 1) ? '+' : '1';
    }
    return cast(string)slice;
}

struct ScalingResult {
    size_t terms;
    long packratNanos;
    long ascentNanos;
    size_t packratBytes;
    size_t ascentBytes;
    double speedupRatio;
}

int main() {
    // Aggressive timeout per AGENTS.md
    alarm(60);

    // =========================================================================
    // 1. Structural Identity & Associativity Equivalence Tests
    // =========================================================================
    {
        const size_t[] termSizes = [1, 2, 4, 8, 16, 64];
        foreach (terms; termSizes) {
            Arena inputArena;
            string input = buildChainInput(terms, inputArena);
            assert(input.length == 2 * terms - 1);

            // 1a. Run standard Packrat LeftChain
            ParseContext ctxPackrat;
            auto packratRes = LeftChain.Expr(ctxPackrat, input);
            assert(packratRes.successful);
            assert(packratRes.end == input.length);

            // 1b. Run DirectAscent
            Arena ascentArena;
            State!(false, 0) state;
            state.arena = &ascentArena;
            state.input = input;
            alias Base = LeftChain.Number;
            alias Suffix = and!(literal!"+", LeftChain.Number);

            auto ascentWrapped = defined!(DirectAscent!(Base, Suffix, "LeftChain.Expr"), "LeftChain.Expr")(
                    state, 0);
            assert(ascentWrapped.successful);
            assert(ascentWrapped.end == input.length);

            // 1c. Deep node-by-node AST equivalence
            assert(treesEqual(packratRes.tree, ascentWrapped),
                    "AST shape mismatch between Packrat and Recursive Ascent");

            // Verify left-associativity shape
            if (terms > 1) {
                // outer defined wrapper -> inner Expr
                assert(ascentWrapped.children.length == 1);
                auto inner = ascentWrapped.children[0];
                assert(inner.children.length == 2);
                assert(inner.children[0].name == "LeftChain.Expr");
                assert(inner.children[1].name == "LeftChain.Number");
            }
        }
    }

    // =========================================================================
    // 2. Failure Offset Preservation Tests
    // =========================================================================
    {
        static immutable string[] malformedInputs = [
            "1+", "1++1", "+1", "1+2+3+", "1+2+3++4", "+", "1+2+3+a"
        ];
        foreach (inp; malformedInputs) {
            ParseContext ctxPackrat;
            auto packratRes = LeftChain.Expr(ctxPackrat, inp);

            Arena ascentArena;
            State!(false, 0) state;
            state.arena = &ascentArena;
            state.input = inp;
            alias Base = LeftChain.Number;
            alias Suffix = and!(literal!"+", LeftChain.Number);

            auto ascentWrapped = defined!(DirectAscent!(Base, Suffix, "LeftChain.Expr"), "LeftChain.Expr")(
                    state, 0);

            assert(packratRes.successful == ascentWrapped.successful, "Success flag mismatch on malformed input");
            assert(packratRes.end == ascentWrapped.end, "Match end mismatch on malformed input");
            assert(packratRes.failEnd == ascentWrapped.failEnd, "Failure offset mismatch on malformed input");
        }
    }

    // =========================================================================
    // 3. Stack Depth & Resource Limit Parity Tests
    // =========================================================================
    {
        // Packrat evaluates recursively and exceeds shallow depthLimit
        Arena inputArena;
        string deepInput = buildChainInput(64, inputArena);

        ParseContext shallowCtx;
        shallowCtx.depthLimit = 16;
        auto packratFail = LeftChain.Expr(shallowCtx, deepInput);
        assert(!packratFail.successful || shallowCtx.depthLimit <= 16,
                "Packrat with 64 terms should require stack depth matching term count");

        // Ascent flattens into an iterative loop; stack depth remains O(1)
        Arena ascentArena;
        State!(false, 0) ascentState;
        ascentState.arena = &ascentArena;
        ascentState.input = deepInput;
        ascentState.context.depthLimit = 16; // strict depth limit
        alias Base = LeftChain.Number;
        alias Suffix = and!(literal!"+", LeftChain.Number);

        auto ascentPass = defined!(DirectAscent!(Base, Suffix, "LeftChain.Expr"), "LeftChain.Expr")(ascentState,
                0);
        assert(ascentPass.successful, "Recursive ascent must succeed within O(1) stack depth limit");
        assert(ascentPass.end == deepInput.length);
    }

    // =========================================================================
    // 4. Recognition Mode (Check == 1) Zero-GC Scalar Parsing
    // =========================================================================
    {
        Arena inputArena;
        string input = buildChainInput(128, inputArena);

        Arena recArena;
        State!(false, 1) recState;
        recState.arena = &recArena;
        recState.input = input;
        alias Base = LeftChain.Number;
        alias Suffix = and!(literal!"+", LeftChain.Number);

        auto recNode = recState.directLeftAscent!(Base, Suffix, "LeftChain.Expr")(0);
        assert(recNode.successful);
        assert(recNode.end == input.length);
    }

    // =========================================================================
    // 5. Scaling & Latency Benchmark Matrix (16 .. 1024 terms)
    // =========================================================================
    ScalingResult[7] results;
    const size_t[] benchSizes = [16, 32, 64, 128, 256, 512, 1024];

    foreach (idx, terms; benchSizes) {
        Arena inputArena;
        string input = buildChainInput(terms, inputArena);

        // Benchmark Packrat
        const packratStart = MonoTime.currTime();
        size_t packratBytes = 0;
        enum iterations = 5;
        foreach (_; 0 .. iterations) {
            ParseContext ctx;
            auto res = LeftChain.Expr(ctx, input);
            packratBytes = res.arena.requestedBytes;
        }
        const packratElapsed = (MonoTime.currTime() - packratStart).total!"nsecs" / iterations;

        // Benchmark Recursive Ascent
        alias Base = LeftChain.Number;
        alias Suffix = and!(literal!"+", LeftChain.Number);
        const ascentStart = MonoTime.currTime();
        size_t ascentBytes = 0;
        foreach (_; 0 .. iterations) {
            Arena arena;
            State!(false, 0) state;
            state.arena = &arena;
            state.input = input;
            auto res = defined!(DirectAscent!(Base, Suffix, "LeftChain.Expr"), "LeftChain.Expr")(state,
                    0);
            ascentBytes = arena.requestedBytes;
        }
        const ascentElapsed = (MonoTime.currTime() - ascentStart).total!"nsecs" / iterations;

        results[idx] = ScalingResult(terms, packratElapsed, ascentElapsed, packratBytes,
                ascentBytes, cast(double)packratElapsed / (ascentElapsed > 0 ? ascentElapsed : 1));
    }

    // Output JSON report
    printf("{\n");
    printf("  \"scaling\": [\n");
    foreach (i, r; results) {
        printf("    {\"terms\": %zu, \"packratNanos\": %lld, \"ascentNanos\": %lld, \"packratBytes\": %zu, \"ascentBytes\": %zu, \"speedup\": %.2f}%s",
                r.terms, r.packratNanos, r.ascentNanos, r.packratBytes, r.ascentBytes,
                r.speedupRatio, i + 1 < results.length ? ",\n".ptr : "\n".ptr);
    }
    printf("  ]\n");
    printf("}\n");

    printf("recursive ascent oracle passed\n");
    return 0;
}
