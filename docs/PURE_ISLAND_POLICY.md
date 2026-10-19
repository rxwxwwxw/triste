# Pure-island mode: explicit unlimited opt-in

`NPeggedPureIslands` remains an opt-in specialization for proved pure public entries in a direct-backend grammar that also contains semantic actions. It is not a default accelerator for action-bearing parsing. Keep ordinary finite limits for ordinary callers; they use the reference fallback.

The D01 matrix measured nonzero entries in 132 eligible configurations and zero entries in 234 finite-default controls and 486 traced controls. Default-limit eligibility is **0%**. The large pure-Root recognition gain does not apply to full trees, actual action execution, or every selected-record projection. Some fallback controls slowed. See the [D01 measurements](../performance/phase3/D01-report.md) and [D02 decision](../performance/phase3/D02-report.md).

## Required contract

| Requirement | Active mode | Otherwise |
|---|---|---|
| Build | `NPeggedPureIslands`, generated `ParserBackend.direct` | Existing implementation |
| Entry | Generated pure-entry proof: known, action-free, acyclic/shareable | Reference tree fallback |
| Output | `check`, or a proved matching compact-record projection | Full trees/incompatible projections fall back |
| Limits | Step, depth and parser memory all `size_t.max`; records output also `size_t.max` | Any finite limit falls back |
| Observability | No trace; no action/opaque behavior reachable from the chosen entry | Reference behavior |
| Allocator/state | Healthy arenas using the default allocator | Reference behavior |

The generated `npeggedPureIslandEntries` list describes recognition entry eligibility. Records have a separate `npeggedPureIslandRecordEntries` proof, and the runtime selector must exactly match compiled tags while omitting the anonymous name `""`. A declaration in one list does not guarantee entry in another mode. Actual metrics must confirm operations.

Unlimited is a deliberate resource policy. It removes these per-parse finite quotas; it does not guarantee allocation success, remove result ownership, or change `@nogc nothrow` error handling. Do not relax limits merely to make a benchmark select this path. No general finite-budget fast variant has been proved: fallback constructs diagnostic trees, charges allocations, and may traverse them again to project records. A scalar implementation must preserve those resource decisions before it can replace finite fallback.

## Existing API usage

This complete example chooses one root record. `Store` makes the grammar action-bearing; the selected `Root` entry does not execute that action. The callback is a placeholder for application behavior.

```d
module pure_island_mode_example;
import npegged.grammar;
import core.stdc.stdio : printf;

private ParseTree remember(bool CT)(ref State!CT state, ParseTree tree) @nogc nothrow {
    return tree;
}

private uint selected(string name) @nogc nothrow pure {
    return name == "WordMode.Root" ? 0 : uint.max;
}

mixin(grammar!(Memoization.selective, selected, ParserBackend.direct)(`
WordMode:
    Root <- Identifier (' ' Identifier)* eoi
    Identifier <~ [a-z]+
    Store <- Identifier{remember}
`));

int main() @nogc nothrow {
    enum input = "one two";
    ParseContext context;
    context.stepLimit = context.depthLimit = context.memoryLimit = size_t.max;
    version (NPeggedMetrics) {
        ParseMetrics metrics;
        context.metrics = &metrics;
    }
    auto checked = check!(WordMode.Root)(context, input);
    assert(checked.successful && checked.end == input.length);
    version (NPeggedMetrics) {
        assert(metrics.pureIslandEntries > 0);
        metrics = ParseMetrics.init;
    }
    auto records = parseRecords!(WordMode.Root, selected, true)(context, input, size_t.max);
    assert(records.successful && records.input == input && records.nodes.length == 1);
    assert(records.nodes[0].kind == 0 && records.nodes[0].begin == 0
        && records.nodes[0].end == input.length && records.nodes[0].parent == size_t.max);
    version (NPeggedMetrics)
        assert(metrics.pureIslandEntries > 0);

    ParseContext ordinary;
    version (NPeggedMetrics) {
        ParseMetrics ordinaryMetrics;
        ordinary.metrics = &ordinaryMetrics;
    }
    auto fallback = check!(WordMode.Root)(ordinary, input);
    assert(fallback.status == checked.status && fallback.end == checked.end
        && fallback.failEnd == checked.failEnd);
    version (NPeggedMetrics)
        assert(ordinaryMetrics.pureIslandEntries == 0);
    printf("pure-island specialized mode passed\n");
    return 0;
}
```

Compile with LDC's `-d-version=NPeggedPureIslands` or DMD's `-version=NPeggedPureIslands`, with the repository's druntime-only flags and source modules. Add `NPeggedMetrics` only to verify activation; measure performance in a separate uninstrumented build. `python3 scripts/d02_decision.py` compiles and runs this exact documentation example on both compilers under a deadline and memory ceiling.

`OwnInput=true` copies and retains input in the result arena; `false` retains only borrowed offsets and requires the caller to keep input alive. Keep ownership identical in comparisons. Results own their arenas and must not be implicitly copied. The generated `Grammar(context, input)` overload returns a full tree and does not select this specialization; use the explicit `check`/`parseRecords` APIs shown above.
