module tests.test_phrase_cache;

import npegged.peg;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;
import core.time : MonoTime, Duration;

// Mock parser simulating rule parsing with a PhraseCache
struct RuleEvaluator(size_t Capacity) {
    PhraseCache!Capacity cache;
    ulong rawEvaluations;

    // Simulates an ordinary rule with a simulated scan length
    bool parseRule(string input, ref size_t cursor, size_t scanLen, char expectedSuffix) @nogc nothrow {
        size_t end, fail;
        bool ok;
        if (cache.lookup(cursor, end, fail, ok)) {
            cursor = end;
            return ok;
        }

        const startPos = cursor;
        ++rawEvaluations;

        // Simulate scanning scanLen bytes
        if (cursor + scanLen <= input.length) {
            cursor += scanLen;
            ok = true;
        } else {
            ok = false;
        }

        cache.store(startPos, cursor, startPos, ok);
        return ok;
    }
}

// 1. Adversarial Shared Prefix Benchmark: M branches sharing scanLen prefix
struct AdversarialResult {
    size_t capacity;
    ulong rawEvaluations;
    ulong lookups;
    ulong hits;
    ulong stores;
    ulong evictions;
    long elapsedNanos;
}

AdversarialResult runAdversarial(size_t Capacity)(size_t branches, size_t scanLen, size_t iterations) {
    RuleEvaluator!Capacity evaluator;
    string input;
    // Build dummy input buffer
    char[2048] buf;
    foreach (ref c; buf)
        c = 'a';
    input = cast(string)buf[0 .. scanLen + 1];

    const start = MonoTime.currTime();
    foreach (iter; 0 .. iterations) {
        evaluator.cache.clear();
        // Simulate ordered choice: try branch 0 .. branches - 1
        foreach (b; 0 .. branches) {
            size_t cursor = 0;
            // Branch matches prefix, then tests suffix character
            if (evaluator.parseRule(input, cursor, scanLen, 'x')) {
                // Suffix matches only on the last branch
                if (b == branches - 1) {
                    // Success!
                    break;
                }
                // Backtrack!
            }
        }
    }
    const elapsed = (MonoTime.currTime() - start).total!"nsecs";

    AdversarialResult res;
    res.capacity = Capacity;
    res.rawEvaluations = evaluator.rawEvaluations;
    res.lookups = evaluator.cache.lookups;
    res.hits = evaluator.cache.hits;
    res.stores = evaluator.cache.stores;
    res.evictions = evaluator.cache.evictions;
    res.elapsedNanos = elapsed / cast(long)iterations;
    return res;
}

// 2. Ping-pong Thrashing Benchmark: alternating between 2 positions
struct PingPongResult {
    size_t capacity;
    ulong lookups;
    ulong hits;
    ulong evictions;
    long elapsedNanos;
}

PingPongResult runPingPong(size_t Capacity)(size_t rounds) {
    RuleEvaluator!Capacity evaluator;
    char[512] buf;
    foreach (ref c; buf)
        c = 'a';
    string input = cast(string)buf[];

    const start = MonoTime.currTime();
    foreach (r; 0 .. rounds) {
        // Interleave pos 0 and pos 10
        size_t c1 = 0;
        evaluator.parseRule(input, c1, 5, 'x');
        size_t c2 = 10;
        evaluator.parseRule(input, c2, 5, 'x');
    }
    const elapsed = (MonoTime.currTime() - start).total!"nsecs";

    PingPongResult res;
    res.capacity = Capacity;
    res.lookups = evaluator.cache.lookups;
    res.hits = evaluator.cache.hits;
    res.evictions = evaluator.cache.evictions;
    res.elapsedNanos = elapsed;
    return res;
}

// 3. Linear Monotonic Workload: strictly advancing cursor (measuring pure cache lookup tax)
struct LinearResult {
    size_t capacity;
    ulong lookups;
    ulong hits;
    long elapsedNanos;
}

LinearResult runLinear(size_t Capacity)(size_t tokens) {
    RuleEvaluator!Capacity evaluator;
    char[4096] buf;
    foreach (ref c; buf)
        c = 'a';
    string input = cast(string)buf[];

    const start = MonoTime.currTime();
    size_t cursor = 0;
    while (cursor + 4 <= input.length) {
        evaluator.parseRule(input, cursor, 4, 'a');
    }
    const elapsed = (MonoTime.currTime() - start).total!"nsecs";

    LinearResult res;
    res.capacity = Capacity;
    res.lookups = evaluator.cache.lookups;
    res.hits = evaluator.cache.hits;
    res.elapsedNanos = elapsed;
    return res;
}

int main() nothrow {
    alarm(45);

    // Run contract assertions across all capacities
    // 1. Adversarial shared-prefix tests
    auto a0 = runAdversarial!0(16, 100, 100);
    auto a1 = runAdversarial!1(16, 100, 100);
    auto a2 = runAdversarial!2(16, 100, 100);
    auto a4 = runAdversarial!4(16, 100, 100);
    auto a8 = runAdversarial!8(16, 100, 100);

    // Capacity 0 has zero hits and 16 evaluations per iteration
    assert(a0.hits == 0);
    assert(a0.rawEvaluations == 16 * 100);

    // Capacity >= 1 eliminates rescans: 1 evaluation and 15 hits per iteration!
    assert(a1.rawEvaluations == 1 * 100);
    assert(a1.hits == 15 * 100);
    assert(a2.rawEvaluations == 1 * 100);
    assert(a2.hits == 15 * 100);
    assert(a4.rawEvaluations == 1 * 100);
    assert(a4.hits == 15 * 100);
    assert(a8.rawEvaluations == 1 * 100);
    assert(a8.hits == 15 * 100);

    // 2. Ping-pong thrashing tests (alternating 2 positions)
    auto p1 = runPingPong!1(200);
    auto p2 = runPingPong!2(200);
    auto p4 = runPingPong!4(200);
    auto p8 = runPingPong!8(200);

    // 1-entry cache thrashes on 2 positions (0 hits, 399 evictions)
    assert(p1.hits == 0);
    assert(p1.evictions > 0);

    // 2-entry, 4-entry, 8-entry caches do NOT thrash on 2 positions: full hit rate after warm-up!
    assert(p2.hits > 0);
    assert(p4.hits > 0);
    assert(p8.hits > 0);

    // 3. Linear non-backtracking tests
    auto l0 = runLinear!0(500);
    auto l1 = runLinear!1(500);
    auto l2 = runLinear!2(500);
    auto l4 = runLinear!4(500);
    auto l8 = runLinear!8(500);
    assert(l0.hits == 0 && l1.hits == 0 && l2.hits == 0 && l4.hits == 0 && l8.hits == 0);

    // Print JSON summary for reporting script
    printf("{\n");
    printf("  \"adversarial\": [\n");
    printf("    {\"capacity\": 0, \"rawEvaluations\": %llu, \"hits\": %llu, \"elapsedNanos\": %lld},\n",
            a0.rawEvaluations, a0.hits, a0.elapsedNanos);
    printf("    {\"capacity\": 1, \"rawEvaluations\": %llu, \"hits\": %llu, \"elapsedNanos\": %lld},\n",
            a1.rawEvaluations, a1.hits, a1.elapsedNanos);
    printf("    {\"capacity\": 2, \"rawEvaluations\": %llu, \"hits\": %llu, \"elapsedNanos\": %lld},\n",
            a2.rawEvaluations, a2.hits, a2.elapsedNanos);
    printf("    {\"capacity\": 4, \"rawEvaluations\": %llu, \"hits\": %llu, \"elapsedNanos\": %lld},\n",
            a4.rawEvaluations, a4.hits, a4.elapsedNanos);
    printf("    {\"capacity\": 8, \"rawEvaluations\": %llu, \"hits\": %llu, \"elapsedNanos\": %lld}\n",
            a8.rawEvaluations, a8.hits, a8.elapsedNanos);
    printf("  ],\n");
    printf("  \"pingpong\": [\n");
    printf("    {\"capacity\": 1, \"hits\": %llu, \"evictions\": %llu, \"elapsedNanos\": %lld},\n",
            p1.hits, p1.evictions, p1.elapsedNanos);
    printf("    {\"capacity\": 2, \"hits\": %llu, \"evictions\": %llu, \"elapsedNanos\": %lld},\n",
            p2.hits, p2.evictions, p2.elapsedNanos);
    printf("    {\"capacity\": 4, \"hits\": %llu, \"evictions\": %llu, \"elapsedNanos\": %lld},\n",
            p4.hits, p4.evictions, p4.elapsedNanos);
    printf("    {\"capacity\": 8, \"hits\": %llu, \"evictions\": %llu, \"elapsedNanos\": %lld}\n",
            p8.hits, p8.evictions, p8.elapsedNanos);
    printf("  ],\n");
    printf("  \"linear\": [\n");
    printf("    {\"capacity\": 0, \"elapsedNanos\": %lld},\n", l0.elapsedNanos);
    printf("    {\"capacity\": 1, \"elapsedNanos\": %lld},\n", l1.elapsedNanos);
    printf("    {\"capacity\": 2, \"elapsedNanos\": %lld},\n", l2.elapsedNanos);
    printf("    {\"capacity\": 4, \"elapsedNanos\": %lld},\n", l4.elapsedNanos);
    printf("    {\"capacity\": 8, \"elapsedNanos\": %lld}\n", l8.elapsedNanos);
    printf("  ]\n");
    printf("}\n");

    printf("phrase cache oracle passed\n");
    return 0;
}
