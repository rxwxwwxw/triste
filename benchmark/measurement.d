module benchmark.measurement;
import core.volatile : volatileLoad, volatileStore;
import npegged.storage : Status;

struct Observation {
    bool accepted;
    ulong outputHash;
    size_t outputNodes;
    size_t allocationCalls, payloadBytes, reservedBytes;
    bool allocatorMeasured;
    Status status;
}

// Every invocation feeds an observable sink, including release builds.
private __gshared ulong checksum;

ulong currentChecksum() @nogc nothrow {
    return volatileLoad(&checksum);
}

@nogc nothrow unittest {
    auto before = currentChecksum();
    consume(true);
    assert(currentChecksum() == before * 33 + 1);
}

void consume(bool accepted, ulong outputHash = 0, size_t nodes = 0, Status status = Status.ok) @nogc nothrow {
    volatileStore(&checksum, volatileLoad(&checksum) * 33 + (accepted
            ? 1 : 2) + outputHash + nodes + cast(ulong)status * 65537);
}

@nogc nothrow unittest {
    consume(true);
    auto first = volatileLoad(&checksum);
    consume(false);
    assert(volatileLoad(&checksum) == first * 33 + 2);
}

ulong expectedChecksum(ulong seed, Observation expected, size_t iterations) @nogc nothrow pure {
    const word = (expected.accepted ? 1UL : 2UL) + expected.outputHash + expected.outputNodes;
    foreach (i; 0 .. iterations)
        seed = seed * 33 + word;
    return seed;
}

@nogc nothrow unittest {
    Observation expected;
    expected.accepted = true;
    expected.outputHash = 12;
    expected.outputNodes = 3;
    assert(expectedChecksum(7, expected, 0) == 7);
    assert(expectedChecksum(7, expected, 2) == (7 * 33 + 16) * 33 + 16);
    expected.accepted = false;
    assert(expectedChecksum(0, expected, 1) == 17);
}

/// Keep pure validators inside the timed loop, even under interprocedural optimization.
string opaqueInput(string input) @nogc nothrow {
    auto address = cast(size_t)input.ptr;
    auto length = input.length;
    return (cast(immutable(char)*)volatileLoad(&address))[0 .. volatileLoad(&length)];
}

@nogc nothrow unittest {
    assert(opaqueInput("abc") == "abc");
    assert(opaqueInput(null).length == 0);
    Observation rejected;
    auto seed = currentChecksum();
    consume(false, 0, 0, Status.resourceLimit);
    assert(currentChecksum() != expectedChecksum(seed, rejected, 1));
}
