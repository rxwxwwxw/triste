module benchmark.entry_pair;
import npegged.grammar;
import benchmark.measurement : Observation, consume, opaqueInput, currentChecksum, expectedChecksum;
import core.time : MonoTime;
import core.stdc.stdio : printf;

mixin(grammar!(Memoization.selective, void, ParserBackend.direct)("Entry: Root <- [a-z]* eoi"));
private auto reference(ref State!(false, 1) state, size_t pos) @nogc nothrow {
    return Entry.Root(state, pos);
}

Observation observeEntry(bool Fast)(string input) @nogc nothrow {
    ParseContext context;
    static if (Fast)
        auto checked = check!(Entry.Root)(context, input);
    else
        auto checked = check!reference(context, input);
    return Observation(checked.successful, checked.end * 65537UL + checked.failEnd, 0,
            checked.arena.allocationCalls, checked.arena.requestedBytes, checked.arena.used, true, checked
                .status);
}

@nogc nothrow unittest {
    foreach (input; ["", "a", "aaaaaaaa", "!", "aaa!", "\xFF"])
        assert(observeEntry!true(input) == observeEntry!false(input));
}

int main() @nogc nothrow {
    enum iterations = 1_000_000;
    static immutable string[6] inputs = ["", "a", "aaaaaaaa", "!", "aaa!", "\xFF"];
    static immutable string[6] names = [
        "empty", "one", "eight", "invalid", "trailing", "utf8_invalid"
    ];
    printf("fixture,implementation,iteration,input_bytes,elapsed_ns,successful,output_digest,status\n");
    foreach (fixture, input; inputs) {
        if (observeEntry!true(input) != observeEntry!false(input))
            return 1;
        foreach (sample; 0 .. 24)
            foreach (offset; 0 .. 2) {
                const fast = ((sample + offset) % 2) != 0;
                auto expected = observeEntry!true(input);
                expected.outputHash += cast(ulong)expected.status * 65537;
                const checksum = expectedChecksum(currentChecksum(), expected, iterations);
                const start = MonoTime.currTime;
                foreach (i; 0 .. iterations) {
                    auto observation = fast ? observeEntry!true(opaqueInput(input))
                        : observeEntry!false(opaqueInput(input));
                    consume(observation.accepted, observation.outputHash, observation.outputNodes, observation
                            .status);
                }
                const ns = (MonoTime.currTime - start).total!"nsecs";
                if (currentChecksum() != checksum)
                    return 2;
                expected = observeEntry!true(input);
                if (sample >= 3)
                    printf("%s,%s,%d,%zu,%.9f,%d,%llu,%d\n", names[fixture].ptr, fast ? "entry".ptr
                            : "exact".ptr, sample - 3, input.length, cast(double)ns / iterations,
                            cast(int)expected.accepted, expected.outputHash, cast(int)expected.status);
            }
    }
    return 0;
}
