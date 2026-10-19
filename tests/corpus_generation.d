module tests.corpus_generation;
// Build with: -I. -Isrc -Iperformance/scripts plus benchmark/json_grammar.d json_output.d workload_grammars.d handwritten/*.d
import corpus_lib;
import npegged.grammar;
import npegged.fuzz : observe, accepts, sameObservation;
import benchmark.json_grammar : jsonGrammar;
import benchmark.workload_grammars : arithmeticGrammar, csvGrammar;
import core.stdc.stdio : printf;
import core.sys.posix.unistd : alarm;

private struct JsonDirect {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(jsonGrammar));
}

private struct JsonCombinators {
    mixin(grammar!(Memoization.selective, void, ParserBackend.combinators)(jsonGrammar));
}

private struct ArithDirect {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(arithmeticGrammar));
}

private struct ArithCombinators {
    mixin(grammar!(Memoization.selective, void, ParserBackend.combinators)(arithmeticGrammar));
}

private struct CsvDirect {
    mixin(grammar!(Memoization.selective, void, ParserBackend.direct)(csvGrammar));
}

private struct CsvCombinators {
    mixin(grammar!(Memoization.selective, void, ParserBackend.combinators)(csvGrammar));
}

private enum targets = [200UL, 8192, 262_144];

private Family jsonFamily() {
    return Family("json", jsonGrammar, "Document", "[", ",", "]", [
        repeatText("[", 200) ~ "1" ~ repeatText("]", 200)
    ]);
}

private Family arithmeticFamily() {
    return Family("arithmetic", arithmeticGrammar, "Root", "", " + ", "", [
        "1" ~ repeatText(" + 1", 600)
    ]);
}

private Family csvFamily() {
    return Family("csv", csvGrammar, "Root", "", "\n", "", ["\"" ~ repeatText("ab\"\"", 4000) ~ "\""]);
}

private string[] realJson(bool training) {
    string[] files;
    auto listing = readFile("performance/corpora/real/json/INDEX.txt");
    size_t begin, index;
    foreach (i; 0 .. listing.length) {
        if (listing[i] != '\n')
            continue;
        const name = listing[begin .. i];
        begin = i + 1;
        if (name.length && (index++ % 2 == 0) == training)
            files ~= readFile("performance/corpora/real/json/" ~ name);
    }
    return files;
}

private string committedPath(const Entry entry) {
    return "performance/corpora/synthetic/" ~ entry.family ~ "/" ~ entry.name ~ ".txt";
}

int main() {
    alarm(180);
    // Regenerate everything in memory exactly as the tool does.
    Entry[] all;
    all ~= buildFamily!(JsonDirect.JSON.Document)(jsonFamily(), "", "synthetic-default", 101, targets);
    const learned = learnPolicy!(JsonDirect.JSON.Document)(jsonGrammar, "Document", realJson(true));
    assert(learned.status == Status.ok && learned.accepted >= 5 && learned.invalid == 0);
    auto learnedFamily = jsonFamily();
    learnedFamily.adversarial = null;
    all ~= buildFamily!(JsonDirect.JSON.Document)(learnedFamily, learned.policyText,
            "synthetic-learned(real-json:training)", 102, targets);
    all ~= buildFamily!(ArithDirect.BenchArithmetic.Root)(arithmeticFamily(), "", "synthetic-default",
            201, targets);
    all ~= buildFamily!(CsvDirect.BenchCSV.Root)(csvFamily(), "", "synthetic-default", 301, targets);
    assert(all.length == 19);
    size_t committedBytes, checked, large;
    foreach (entry; all) {
        // Reproducibility: committed files are byte-identical to a fresh regeneration (large ones are not committed).
        if (entry.sizeClass == "large") {
            ++large;
            assert(entry.text.length >= 200_000);
            continue;
        }
        assert(readFile(committedPath(entry)) == entry.text);
        committedBytes += entry.text.length;
        // Size budget per class.
        assert(entry.sizeClass != "small" || entry.text.length <= 2048);
        assert(entry.sizeClass != "medium" || entry.text.length <= 24 * 1024);
        ++checked;
    }
    assert(committedBytes <= 256 * 1024 && large == 4 && checked == 15);
    // Full-acceptance validity (and the invalid label) with the real parsers, and output parity across backends.
    foreach (entry; all) {
        Observation a, b;
        if (entry.family == "json") {
            a = observe!(JsonCombinators.JSON.Document)(entry.text, size_t.max / 2);
            b = observe!(JsonDirect.JSON.Document)(entry.text, size_t.max / 2);
        } else if (entry.family == "arithmetic") {
            a = observe!(ArithCombinators.BenchArithmetic.Root)(entry.text, size_t.max / 2);
            b = observe!(ArithDirect.BenchArithmetic.Root)(entry.text, size_t.max / 2);
        } else {
            a = observe!(CsvCombinators.BenchCSV.Root)(entry.text, size_t.max / 2);
            b = observe!(CsvDirect.BenchCSV.Root)(entry.text, size_t.max / 2);
        }
        assert(sameObservation(a, b));
        assert(accepts(a, entry.text.length) == entry.valid);
    }
    // Real corpus: every snapshot file is accepted by the grammar (it is a real JSON corpus, not a rejected one).
    foreach (file; realJson(true) ~ realJson(false))
        assert(accepts(observe!(JsonDirect.JSON.Document)(file, size_t.max / 2), file.length));
    // Synthetic-vs-holdout histograms: learned weights are closer to the held-out real half than default weights.
    const holdout = realJson(false);
    auto fromLearned = generateWithPolicy!(JsonDirect.JSON.Document)(jsonGrammar, "Document", 200, learned
            .policyText);
    auto fromDefault = generateWithPolicy!(JsonDirect.JSON.Document)(jsonGrammar, "Document", 200, "");
    auto learnedReport = compareToHoldout!(JsonDirect.JSON.Document)(jsonGrammar, "Document",
            holdout, fromLearned.accepted.texts);
    auto defaultReport = compareToHoldout!(JsonDirect.JSON.Document)(jsonGrammar, "Document",
            holdout, fromDefault.accepted.texts);
    assert(learnedReport.status == Status.ok && fromLearned.accepted.texts.length == 200);
    assert(learnedReport.choiceShareDistance < defaultReport.choiceShareDistance);
    printf("corpus generation passed (%zu entries, %zu committed bytes, learned share distance %zu vs default %zu)\n",
            all.length, committedBytes, learnedReport.choiceShareDistance, defaultReport
                .choiceShareDistance);
    return 0;
}

import npegged.fuzz : Observation;
