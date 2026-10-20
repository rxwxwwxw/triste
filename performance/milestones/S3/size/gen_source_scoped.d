import npegged.grammar : generate, Memoization, ParserBackend;
import npegged.io : File;
import npegged.storage : Buffer, Status;
import core.stdc.stdio : fwrite, stdout;

int main(string[] args) nothrow {
    if (args.length != 2)
        return 2;
    auto file = File.open(args[1]);
    if (!file.valid)
        return 2;
    Buffer!char input;
    if (file.read(input) != Status.ok)
        return 2;
    auto generated = generate!(Memoization.selective, void, ParserBackend.direct)(cast(string)input
            .data);
    if (generated.status != Status.ok)
        return 1;
    return fwrite(generated.source.ptr, 1, generated.source.length, stdout) == generated.source
        .length ? 0 : 2;
}

nothrow unittest {
    assert(main(["gen_source"]) == 2);
    assert(main(["gen_source", "/npegged/nonexistent/input"]) == 2);
}
