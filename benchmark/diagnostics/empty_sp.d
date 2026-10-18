module benchmark.diagnostics.empty_sp;
import npegged.grammar;
import benchmark.measurement : opaqueInput, consume;
import core.stdc.stdio : printf;
import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;

enum source = `EmptySP:
    Root <- Sp 'x' eoi
    Sp <: [ \t\r\n]* ('#' (!'\n' .)* [ \t\r\n]*)*
`;
mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(source));
private ulong now() @nogc nothrow {
    timespec t;
    return clock_gettime(CLOCK_MONOTONIC, &t) ? 0 : cast(ulong)t.tv_sec * 1_000_000_000 + t.tv_nsec;
}

int main() @nogc nothrow {
    version (EmitSource) {
        enum generated = grammar!(Memoization.selective, void, ParserBackend.direct)(source);
        printf("%.*s", cast(int)generated.length, generated.ptr);
        return 0;
    } else {
        printf("case,sample,iterations,ns,end,fail_end\n");
        foreach (caseIndex, input; ["x", "", " ", "#", "#comment\n", " \t#one\n#two\n x"]) {
            auto borrowed = opaqueInput(input);
            foreach (sample; 0 .. 7) {
                ParseContext context;
                size_t end, failure;
                foreach (_; 0 .. 1000) {
                    auto result = check!(EmptySP.Sp)(context, borrowed);
                    consume(result.successful, result.end, result.failEnd, result.status);
                }
                auto start = now();
                foreach (_; 0 .. 100_000) {
                    auto result = check!(EmptySP.Sp)(context, borrowed);
                    if (!result.successful || result.status != Status.ok)
                        return 2;
                    end = result.end;
                    failure = result.failEnd;
                    consume(result.successful, end, failure, result.status);
                }
                printf("%llu,%u,100000,%llu,%llu,%llu\n", cast(ulong)caseIndex, cast(uint)sample,
                        now() - start, cast(ulong)end, cast(ulong)failure);
            }
        }
        return 0;
    }
}
