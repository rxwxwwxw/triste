// Writes the G7 corpora: every entry to <outdir>/<name>.txt and a JSON description array to stdout.
// Build and run through performance/scripts/make_corpora.py.
import corpus_lib;
import npegged.grammar;
import benchmark.json_grammar : jsonGrammar;
import benchmark.workload_grammars : arithmeticGrammar, csvGrammar;
import core.stdc.stdio;

private struct Json {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(jsonGrammar));
}

private struct Arithmetic {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(arithmeticGrammar));
}

private struct Csv {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(csvGrammar));
}

enum targets = [200UL, 8192, 262_144];

Family jsonFamily() {
    return Family("json", jsonGrammar, "Document", "[", ",", "]", [
        repeatText("[", 200) ~ "1" ~ repeatText("]", 200)
    ]);
}

Family arithmeticFamily() {
    return Family("arithmetic", arithmeticGrammar, "Root", "", " + ", "", [
        "1" ~ repeatText(" + 1", 600)
    ]);
}

Family csvFamily() {
    return Family("csv", csvGrammar, "Root", "", "\n", "", ["\"" ~ repeatText("ab\"\"", 4000) ~ "\""]);
}

/// Training half of the real JSON corpus (even indices); the odd half is the holdout used by the tests.
string[] realJson(bool training) {
    string[] files;
    auto listing = readFile("performance/corpora/real/json/INDEX.txt");
    size_t begin, index;
    foreach (i; 0 .. listing.length) {
        if (listing[i] != '\n')
            continue;
        const name = listing[begin .. i];
        begin = i + 1;
        if (!name.length)
            continue;
        if ((index++ % 2 == 0) == training)
            files ~= readFile("performance/corpora/real/json/" ~ name);
    }
    return files;
}

string quote(string text) {
    string result = "\"";
    foreach (c; text) {
        if (c == '"' || c == '\\')
            result ~= '\\';
        result ~= c;
    }
    return result ~ "\"";
}

int main(string[] args) {
    if (args.length < 2)
        return 2;
    Entry[] all;
    all ~= buildFamily!(Json.JSON.Document)(jsonFamily(), "", "synthetic-default", 101, targets);
    const learned = learnPolicy!(Json.JSON.Document)(jsonGrammar, "Document", realJson(true));
    if (learned.status != Status.ok || learned.accepted < 5)
        return 3;
    auto learnedFamily = jsonFamily();
    learnedFamily.adversarial = null; // the handwritten outlier is emitted once, with the default build
    all ~= buildFamily!(Json.JSON.Document)(learnedFamily, learned.policyText,
            "synthetic-learned(real-json:training)", 102, targets);
    all ~= buildFamily!(Arithmetic.BenchArithmetic.Root)(arithmeticFamily(), "", "synthetic-default", 201,
            targets);
    all ~= buildFamily!(Csv.BenchCSV.Root)(csvFamily(), "", "synthetic-default", 301, targets);
    printf("[");
    foreach (i, entry; all) {
        auto path = (args[1] ~ "/" ~ entry.name ~ ".txt\0");
        auto file = fopen(path.ptr, "wb");
        if (file is null)
            return 4;
        fwrite(entry.text.ptr, 1, entry.text.length, file);
        fclose(file);
        const line = (i ? ",\n" : "\n") ~ "{\"name\":" ~ quote(entry.name) ~ ",\"family\":" ~ quote(
                entry.family) ~ ",\"class\":" ~ quote(entry.sizeClass) ~ ",\"valid\":" ~ (entry.valid
                ? "true" : "false") ~ ",\"provenance\":" ~ quote(entry.provenance) ~ ",\"seed\":"
            ~ decimal(cast(size_t)entry.seed) ~ ",\"bytes\":" ~ decimal(entry.text.length) ~ "}";
        printf("%.*s", cast(int)line.length, line.ptr);
    }
    printf("\n]\n");
    return 0;
}
