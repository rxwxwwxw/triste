// L4 study: how many overlapping choice pairs of the real grammars are resolved by a bounded literal prefix of k bytes?
// Usage: l4_study <grammar file>...  (CSV on stdout: file,pairs,firstFirstConflicts,depth2,depth3,depth4,deeper,unbounded,shadowed)
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
        auto report = prefixDiscriminationReport(cast(string)buffer[0 .. length]);
        if (report.status != Status.ok)
            continue;
        size_t pairs, conflicts, d2, d3, d4, deeper, unbounded, shadowed;
        foreach (choice; report.choices)
            foreach (pair; choice.pairs) {
                ++pairs;
                conflicts += pair.firstFirstConflict;
                if (pair.kind == DiscriminationKind.disjointTails) {
                    if (pair.discriminatingDepth == 2)
                        ++d2;
                    else if (pair.discriminatingDepth == 3)
                        ++d3;
                    else if (pair.discriminatingDepth == 4)
                        ++d4;
                    else
                        ++deeper;
                } else if (pair.kind == DiscriminationKind.unbounded)
                    ++unbounded;
                else if (pair.kind == DiscriminationKind.shadowed)
                    ++shadowed;
            }
        printf("%s,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu\n", (name ~ "\0").ptr, pairs, conflicts, d2, d3,
                d4, deeper, unbounded, shadowed);
    }
    return 0;
}
