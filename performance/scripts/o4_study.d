// O4(a): count composed regular regions (regions that call rules, i.e. would carry inner records) per grammar.
// Usage: o4_study <grammar file>...  -> CSV on stdout: file,rules,regions,composedRegions,rulesWithComposed
import npegged.grammar;
import core.stdc.stdio;
import core.stdc.stdlib : malloc;

int main(string[] args) {
    foreach (name; args[1 .. $]) {
        auto file = fopen((name ~ "\0").ptr, "rb");
        if (file is null)
            continue;
        fseek(file, 0, SEEK_END);
        const length = cast(size_t)ftell(file);
        fseek(file, 0, SEEK_SET);
        auto buffer = cast(char*)malloc(length + 1);
        fread(buffer, 1, length, file);
        fclose(file);
        const report = tagRegionReport(cast(string)buffer[0 .. length]);
        if (report.status == Status.ok)
            printf("%s,%zu,%zu,%zu,%zu\n", (name ~ "\0").ptr, report.rules, report.regions,
                    report.composedRegions, report.rulesWithComposed);
    }
    return 0;
}
