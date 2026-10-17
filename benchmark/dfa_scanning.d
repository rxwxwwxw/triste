/** Isolated phase-2 token throughput. Run with an external timeout. */
module benchmark.dfa_scanning;

import npegged.grammar;
import benchmark.measurement : consume, opaqueInput, currentChecksum;
import core.stdc.stdio : printf;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;

mixin(grammar!(Memoization.no)(`
TokenScan:
    Number <- ~([0-9]+ ('.' [0-9]+)? ([eE] [+-]? [0-9]+)?)
    Identifier <- ~([a-zA-Z_] [a-zA-Z0-9_]*)
    Whitespace <- ~[ \t\r\n]+
    Comment <- ~('#' (!'\n' .)* '\n')
    String <- ~('"' (!["\\] .)* '"')
    Escaped <- ~('"' ('\\' . / (!'"' .))* '"')
`));

private ulong now() @nogc nothrow {
    timespec time;
    if (clock_gettime(CLOCK_MONOTONIC, &time))
        return 0;
    return cast(ulong)time.tv_sec * 1_000_000_000 + time.tv_nsec;
}

int main() @nogc nothrow {
    enum length = 1024 * 1024;
    enum iterations = 64;
    enum samples = 7;
    enum runs = 3;
    Arena arena;
    auto buffer = arena.allocate!char(length);
    if (buffer.length != length)
        return 2;
    bool passed = true;
    static foreach (name; ["Number", "Identifier", "Whitespace", "Comment", "String", "Escaped"]) {
        {
            alias table = __traits(getMember, TokenScan, "_dfa_" ~ name);
            static assert(table.valid);
            buffer[] = name == "Number" ? '7' : name == "Whitespace" ? ' ' : 'a';
            if (name == "Comment") {
                buffer[0] = '#';
                buffer[$ - 1] = '\n';
            }
            if (name == "String" || name == "Escaped")
                buffer[0] = buffer[$ - 1] = '"';
            if (name == "Escaped")
                for (size_t offset = 64; offset + 1 < buffer.length - 1; offset += 64) {
                    buffer[offset] = '\\';
                    buffer[offset + 1] = '"';
                }
            const input = cast(string)buffer;
            foreach (run; 0 .. runs) {
                ulong elapsed;
                foreach (sample; 0 .. samples) {
                    const start = now();
                    foreach (iteration; 0 .. iterations) {
                        const end = scanDFA!table(opaqueInput(input), 0);
                        if (end != length)
                            return 3;
                        consume(true, end);
                    }
                    const stop = now();
                    if (!start || stop <= start)
                        return 4;
                    elapsed += stop - start;
                }
                const gbPerSecond = cast(double)length * iterations * samples / elapsed;
                printf("%s run %u: %.3f GB/s (%u samples, %u iterations)\n", (name ~ "\0").ptr,
                        cast(uint)run + 1, gbPerSecond, samples, iterations);
                passed = passed && gbPerSecond >= 1.0;
            }
        }
    }
    printf("checksum: %llu\n", cast(ulong)currentChecksum());
    return passed ? 0 : 1;
}
