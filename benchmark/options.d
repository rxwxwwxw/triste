module benchmark.options;
import benchmark.json_output : OutputMode;

enum OptionStatus {
    ok,
    help,
    invalid
}

struct Options {
    size_t iterations;
    size_t samples = 5;
    string filter;
    bool json, memory, exportCorpus, targetEngines, workloads, explicitMode;
    bool comparison = true;
    OutputMode mode = OutputMode.tree;
}

size_t positiveNumber(string value) @nogc nothrow pure {
    size_t result;
    foreach (c; value) {
        if (c < '0' || c > '9' || result > (size_t.max - (c - '0')) / 10)
            return 0;
        result = result * 10 + c - '0';
    }
    return result;
}

@nogc nothrow pure unittest {
    assert(positiveNumber("12") == 12);
    assert(positiveNumber("") == 0);
    assert(positiveNumber("x") == 0);
    assert(positiveNumber("999999999999999999999999999999999") == 0);
}

/// Accept both --key=value and --key value, preserving the original short aliases.
OptionStatus parseOptions(scope const(string)[] args, ref Options options) @nogc nothrow pure {
    for (size_t index = 1; index < args.length; ++index) {
        string key = args[index], value;
        bool assigned;
        foreach (i, c; key) {
            if (c != '=')
                continue;
            value = key[i + 1 .. $];
            key = key[0 .. i];
            assigned = true;
            break;
        }
        switch (key) {
        case "--iterations":
        case "-n":
        case "--samples":
        case "--filter":
        case "-f":
        case "--mode":
            if (!assigned) {
                if (++index == args.length)
                    return OptionStatus.invalid;
                value = args[index];
            }
            switch (key) {
            case "--iterations":
            case "-n":
                options.iterations = positiveNumber(value);
                if (!options.iterations)
                    return OptionStatus.invalid;
                break;
            case "--samples":
                options.samples = positiveNumber(value);
                if (!options.samples || options.samples == size_t.max)
                    return OptionStatus.invalid;
                break;
            case "--filter":
            case "-f":
                options.filter = value;
                break;
            default:
                options.comparison = true;
                options.explicitMode = true;
                switch (value) {
                case "validation":
                    options.mode = OutputMode.validation;
                    break;
                case "spans":
                    options.mode = OutputMode.spans;
                    break;
                case "tree":
                    options.mode = OutputMode.tree;
                    break;
                default:
                    return OptionStatus.invalid;
                }
            }
            break;
        default:
            if (assigned)
                return OptionStatus.invalid;
            switch (key) {
            case "--json":
                options.json = true;
                break;
            case "--memory":
            case "-m":
                options.memory = true;
                break;
            case "--export-corpus":
                options.exportCorpus = true;
                break;
            case "--workloads":
                options.workloads = true;
                options.comparison = true;
                break;
            case "--target-engines":
                options.targetEngines = true;
                break;
            case "--help":
            case "-h":
                return OptionStatus.help;
            default:
                return OptionStatus.invalid;
            }
        }
    }
    return OptionStatus.ok;
}

@nogc nothrow pure unittest {
    static immutable string[][] valid = [
        ["runner"], ["runner", "-n", "2", "-f", "JSON", "-m", "--json"],
        ["runner", "--iterations=3", "--samples=2", "--filter=", "--mode=tree"],
        ["runner", "--iterations", "3", "--samples", "2", "--filter", "JSON", "--mode", "spans"],
        ["runner", "--mode=validation", "--export-corpus", "--memory", "--target-engines"]
    ];
    foreach (args; valid) {
        Options options;
        assert(parseOptions(args, options) == OptionStatus.ok);
    }
    static immutable string[] combined = [
        "runner", "-n=2", "-f=JSON", "-m", "--json", "--mode=tree", "--samples=3",
        "--export-corpus", "--target-engines"
    ];
    Options options;
    assert(parseOptions(combined, options) == OptionStatus.ok);
    assert(options.iterations == 2 && options.samples == 3 && options.filter == "JSON");
    assert(options.memory && options.json && options.comparison && options.exportCorpus && options
            .targetEngines);
    assert(options.mode == OutputMode.tree);
    foreach (flag; ["--help", "-h"]) {
        string[2] args = ["runner", flag];
        assert(parseOptions(args, options) == OptionStatus.help);
    }
    static immutable string[][] invalid = [
        ["runner", "--iterations"], ["runner", "--iterations=0"], ["runner", "--iterations=x"],
        ["runner", "--samples=0"], ["runner", "--samples=18446744073709551615"],
        ["runner", "--samples=9999999999999999999999999999"], ["runner", "--mode=nope"],
        ["runner", "--json=true"], ["runner", "--unknown"], ["runner", "--samples"],
        ["runner", "--filter"], ["runner", "--mode"]
    ];
    foreach (args; invalid)
        assert(parseOptions(args, options) == OptionStatus.invalid);
}

@nogc nothrow pure unittest {
    Options options;
    assert(parseOptions(["runner", "--workloads"], options) == OptionStatus.ok);
    assert(options.workloads && options.comparison);
    Options records;
    assert(parseOptions(["runner", "--workloads", "--mode=tree"], records) == OptionStatus.ok);
    assert(records.mode == OutputMode.tree && records.workloads && records.comparison);
}
