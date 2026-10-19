// Writes the generated parser source for a grammar file to stdout and stats to stderr.
import npegged.grammar;
import core.stdc.stdio;
import core.stdc.stdlib : malloc;

int main(string[] args) {
    if (args.length < 2)
        return 2;
    auto file = fopen((args[1] ~ "\0").ptr, "rb");
    if (file is null)
        return 2;
    fseek(file, 0, SEEK_END);
    const length = cast(size_t)ftell(file);
    fseek(file, 0, SEEK_SET);
    auto buffer = cast(char*)malloc(length + 1);
    fread(buffer, 1, length, file);
    fclose(file);
    auto generated = generate!(Memoization.selective, void, ParserBackend.direct)(cast(string)buffer[0 .. length]);
    if (generated.status != Status.ok)
        return 1;
    fwrite(generated.source.ptr, 1, generated.source.length, stdout);
    return 0;
}
