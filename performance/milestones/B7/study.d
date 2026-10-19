import npegged.grammar;
import core.stdc.stdio; import core.stdc.stdlib : malloc; import core.time : MonoTime;
int main(string[] args) {
    foreach (name; args[1 .. $]) {
        auto f = fopen((name ~ "\0").ptr, "rb"); fseek(f, 0, SEEK_END); const n = cast(size_t)ftell(f); fseek(f, 0, SEEK_SET);
        auto buf = cast(char*)malloc(n + 1); fread(buf, 1, n, f); fclose(f);
        string g = cast(string)buf[0 .. n];
        size_t[2] pairs, disjoint, improves, unknown; double[2] ms; int ok = 1;
        foreach (mode; 0 .. 2) {
            auto t0 = MonoTime.currTime;
            auto r = prefixDiscriminationReport(g, EligibilityFormat.json, mode == 1);
            ms[mode] = (MonoTime.currTime - t0).total!"usecs" / 1000.0;
            if (r.status != Status.ok) { ok = 0; break; }
            foreach (c; r.choices) foreach (p; c.pairs) {
                ++pairs[mode]; disjoint[mode] += p.bites == "proven-disjoint"; improves[mode] += p.bitesImprovesFirst; unknown[mode] += p.bites == "unknown";
            }
        }
        if (ok) printf("%s,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%.3f,%.3f\n", (name ~ "\0").ptr, pairs[0], disjoint[0], disjoint[1], unknown[0], unknown[1], improves[0], improves[1], ms[0], ms[1]);
    }
    return 0;
}
