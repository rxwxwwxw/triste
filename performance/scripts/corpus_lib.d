/** Reproducible benchmark corpus construction (G7). Shared by the generator tool and the tests so a test can regenerate
    exactly what is committed. Pure functions of (grammar, seed, policy, targets); no clocks, no host state.

    Every valid entry is accepted by the real parser with the whole input consumed (G2 oracle, also for the composites);
    invalid entries are oracle-verified rejections (G6 mutator). Labels say how an entry was made: `synthetic-default`
    (uniform weights), `synthetic-learned(<corpus>)` (weights learned from a real corpus, G5) or `adversarial-handwritten`.
*/
module corpus_lib;
import npegged.grammar;
import npegged.fuzz : Mutator, observe, accepts;
import core.stdc.stdio : FILE, fopen, fclose, fread, fseek, ftell, SEEK_END, SEEK_SET;
import core.stdc.stdlib : malloc, free;

nothrow:

struct Entry {
    string name, family, sizeClass, provenance;
    bool valid;
    ulong seed;
    string text;
}

struct Family {
    string name, grammarText, startRule;
    string prefix, joiner, suffix; /// composition of accepted samples into one larger valid input
    string[] adversarial; /// handwritten pathological inputs (must be accepted)
}

/// Whole file as a string; null when missing. Cold helper for corpus files.
string readFile(string path) {
    auto file = fopen((path ~ "\0").ptr, "rb");
    if (file is null)
        return null;
    scope (exit)
        fclose(file);
    fseek(file, 0, SEEK_END);
    const length = cast(size_t)ftell(file);
    fseek(file, 0, SEEK_SET);
    auto buffer = new char[length];
    fread(buffer.ptr, 1, length, file);
    return cast(string)buffer;
}

string decimal(size_t value) {
    char[20] digits;
    size_t count;
    do {
        digits[count++] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value);
    string result;
    while (count)
        result ~= digits[--count];
    return result;
}

/// Index of the pool sample whose length is closest to `target`.
private size_t closest(const string[] pool, size_t target) {
    size_t best;
    size_t bestDistance = size_t.max;
    foreach (i, text; pool) {
        const distance = text.length > target ? text.length - target : target - text.length;
        if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
        }
    }
    return best;
}

/// Build the classes of one family. `targets` are byte sizes for small, medium and large.
Entry[] buildFamily(alias parser)(Family family, string policyText, string provenance, ulong seed,
        const size_t[3] targets) {
    Entry[] entries;
    GeneratorOptions options;
    options.seed = seed;
    options.maxOutput = 1024;
    auto pool = generateWithPolicy!parser(family.grammarText, family.startRule, 600, policyText, options,
            20_000);
    if (!pool.policyOk || pool.accepted.texts.length < 20)
        return entries;
    static immutable classNames = ["small", "medium", "large"];
    foreach (c; 0 .. 3) {
        string text;
        if (c == 0)
            text = pool.accepted.texts[closest(pool.accepted.texts, targets[0])];
        else {
            text = family.prefix;
            size_t at = cast(size_t)(seed % pool.accepted.texts.length);
            bool first = true;
            while (text.length + family.suffix.length < targets[c]) {
                text ~= (first ? "" : family.joiner) ~ pool.accepted.texts[at % pool.accepted.texts
                        .length];
                first = false;
                ++at;
            }
            text ~= family.suffix;
        }
        // The composite is validated by the real parser like every other entry.
        if (!accepts(observe!parser(text, size_t.max / 2), text.length))
            continue;
        entries ~= Entry(family.name ~ "-" ~ classNames[c] ~ "-valid-" ~ decimal(cast(size_t)seed),
                family.name, classNames[c], provenance, true, seed, text);
    }
    // An oracle-verified invalid input derived from the small valid entry.
    if (entries.length) {
        auto mutator = Mutator(seed ^ 0x5EEDUL, []);
        mutator.maxLength = 512;
        foreach (attempt; 0 .. 400) {
            const candidate = mutator.mutate(entries[0].text);
            if (!accepts(observe!parser(candidate), candidate.length)) {
                entries ~= Entry(family.name ~ "-small-invalid-" ~ decimal(cast(size_t)seed),
                        family.name, "small", provenance ~ " + mutation", false, seed, candidate);
                break;
            }
        }
    }
    foreach (i, text; family.adversarial)
        if (accepts(observe!parser(text, size_t.max / 2), text.length))
            entries ~= Entry(family.name ~ "-adversarial-valid-" ~ decimal(i), family.name,
                    "adversarial", "adversarial-handwritten", true, 0, text);
    return entries;
}

string repeatText(string unit, size_t count) {
    string result;
    foreach (_; 0 .. count)
        result ~= unit;
    return result;
}
