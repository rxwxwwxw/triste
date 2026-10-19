# triste / npegged

The first part of triste converts Philippe Sigaud's Pegged into a Linux,
druntime-only D library. Original sources remain in `third-party/Pegged`.
The conversion is derivative work under Boost 1.0; see `LICENSE` and `NOTICE`.

## Using a grammar

```d
import npegged.grammar;

mixin(grammar(`
Arithmetic:
    Sum    < Number (:'+' Number)* :eoi
    Number <~ [0-9]+
`));

int main() @nogc nothrow {
    ParseContext context;
    auto result = Arithmetic(context, "12 + 34");
    assert(result.status == Status.ok);
    assert(result.matches == ["12", "34"]);
    return 0;
}
```

`ParseResult` owns its input and tree storage. It is move-only. Nodes, matches,
and child slices are borrowed views valid until that result is destroyed.
A context can be reused; separate parses retain independent results and memo
state. Contexts expose memory, step, and recursion-depth limits, plus a tracing
callback and user-data pointer. Runtime parser functions and callbacks are
`@nogc nothrow`. Allocation and operating-system resources use RAII structs.

Grammar syntax follows the supplied Pegged examples: ordered and longest
choice, repetition, lookahead, spacing arrows, captures and tree transforms,
parameterized rules and grammars, composition, actions, and runtime left
recursion. Parsing accepts prefixes unless the grammar includes `eoi`.
`Status` distinguishes mismatch, invalid input, memory failure, resource limits,
and I/O failure. `result.failMsg` returns an owning diagnostic text buffer.

For validation without a retained tree, use
`check!(Arithmetic.opCall)(context, input)`. This synchronous recognizer borrows
input for the call and returns a move-only `CheckResult` with status, success,
end and furthest-failure offsets. It omits match, child and diagnostic arrays;
memoized grammars still allocate memo storage. Generated grammars containing
actions conservatively use tree execution so callbacks retain their captures
and seed-growth behavior. Include `eoi` to require complete input consumption.

Use `grammar!(Memoization.selective)(definition)` to retain memoization for
left-recursive components while bypassing it for other analyzed rules. The default remains `Memoization.yes`; keep full packrat memoization for
backtracking-heavy grammars. Unknown external calls, actions and parameterized
rules use conservative caching. Ordinary nested recursion alone does not require
seed growth. Recognition uses a small offset/status value rather than a tree.

ASCII range/class repetitions in recognition mode use scalar byte scanners.
Fused or discarded range/class repetitions also use those scanners in tree mode;
contiguous fused captures borrow the result-owned input. Ordinary repetition
retains its per-character matches, and Unicode ranges retain scalar decoding.
Byte choices and delimiter lookahead followed by `.` also expose scanner metadata,
including predictive choices. Scanner boundaries use the generic parser so
failure diagnostics and partially exhausted step budgets retain their behavior.

Compile-time parsing remains available:

```d
enum result = Arithmetic("12 + 34");
static assert(result.successful);
```

As upstream, left-recursive input parsing requires runtime execution.

The grammar frontend supports both compile-time mixins and cold runtime
code generation (`generate` and `asModule`). These cold operations selectively
use druntime GC. Compiler execution uses compiler-managed arrays; parser
execution uses scoped arenas, including the alternate backend when exercised
at runtime. There are no Phobos dependencies in maintained D code or emitted
parsers. Strict `-betterC` compilation is not a target of this first conversion.

Use `eligibilityReport!(memo, Selector, backend)(definition)` for a cold JSON
report of actual scalar/direct eligibility, memoization, fallback reasons and
record selection. Pass `EligibilityFormat.text` for text. The result has explicit
status and typed rule rows; requesting a report preserves parser generation
policy. See the [eligibility report guide](performance/results/H01/README.md) for
field meanings, examples and current whole-grammar barriers. Reports also expose
[rule-local knowledge and potential actions](performance/results/H02/README.md);
these diagnostic facts do not change parser or memo policy.

Unicode folding and alphabetic-property tables are generated from the vendored
Unicode 17 database, independently of the process locale. As in Pegged, `.`
consumes one byte, character ranges decode UTF-8, and case-insensitive literals
consume the literal's byte length. Offsets and columns are byte-based.

## Parser modes and recommendations

NPegged supports multiple execution backends, output contracts, and optimization flags. See the comprehensive [Parser Modes & Performance Guide](docs/PARSER_MODES.md) for full configuration details and benchmark analysis.

| Mode | Invocation | Characteristics |
|---|---|---|
| **Reference ParseTree** | `Grammar(context, input)` | Default; complete `ParseTree` AST, full memoization, scoped arena. |
| **Selective Recognition** | `check!(Grammar.opCall)(context, input)` | Returns `CheckResult`; scanner eligibility, memoization and action fallback determine allocation. |
| **Compact Records** | `parseRecords!(Grammar.opCall, selector)(context, input)` | Result-owned compact records, `@nogc`; input is copied by default. No universal zero-overhead or handwritten-ratio claim. |
| **Shared Left Recursion (opt-in)** | Eligible `parseRecords` with sharing requested | Requires explicit unlimited context/output limits and no trace. Active synthetic results and finite-policy limits are documented in [C01/C02](performance/phase3/C01-report.md). |
| **Action Pure Islands (opt-in)** | Explicit `check` or proved `parseRecords` entry | Requires a generated direct backend, eligible entry/projection, no trace and explicit unlimited limits. Default finite policies fall back; see the [mode contract](docs/PURE_ISLAND_POLICY.md). |

## Building and checking

Required compiler targets: DMD and LDC (`ldc2`). Other tools: separately linkable
druntime libraries, `dfmt`, Python 3, GNU `timeout`, `rg`, and Valgrind with matching
libc debug symbols. GDC remains an optional compatibility compiler. The current
branch-coverage collector additionally requires GDC 16 and matching `gcov`, including
when invoked by full validation or the pre-commit hook; replacing that collector is
still needed to make the complete coverage gate independent of GDC. No DUB dependency
is needed for the library.

```sh
scripts/build.sh                       # unit tests and integration runner
DC=ldc2 scripts/build.sh
DC=gdc scripts/build.sh                 # optional compatibility check
scripts/examples.sh                    # Pascal and DConf programs; regeneration check
scripts/hotpaths.sh                     # GC diagnostics on DMD and LDC
scripts/coverage.sh                     # line and source-branch coverage gate
scripts/validate.sh --full              # full checks, including GDC-based coverage
scripts/install-hooks.sh               # install into a writable Git checkout
```

Each integration executable invocation has an explicit timeout. Builds enable
fatal invariant checks, disable exception unwinding with compiler-specific
flags, and link druntime explicitly. `build/<compiler>/tests` accepts
`--DRT-testmode=run-main`; the runner script always passes it so integration
checks execute after unit tests.

The pre-commit hook validates an isolated copy of the Git index, chains an
existing hook, and leaves unstaged changes out of validation. An existing
`core.hooksPath` configuration is reported rather than overwritten. Installing
the active hook requires writable Git metadata; the installer cannot install
into this workspace's read-only `.git` mount.

`.dfmt` records the requested baseline. `.editorconfig` supplies those settings
to dfmt, which reads EditorConfig. Format maintained D files with:

```sh
find src tests examples scripts -name '*.d' -exec dfmt -i {} +
```

Coverage requires greater than 90% line and branch coverage per executable
module in `src/` only. Tests, examples, benchmarks, and scripts are excluded
from this threshold; their verification still runs. Raw DMD and gcov
reports remain in `build/coverage`. Source-branch measurement merges template
instantiations, excludes unittest bodies and compiler-generated invariant
checks identified by GCC's CFG, and retains ordinary error branches. The branch collector uses GDC 16 JSON block identifiers. Missing,
stale, or insufficient reports fail the gate. Compiler-only modules with no
executable code have no runtime coverage denominator.

## Examples and generation

Converted grammar modules and their assertions live in `examples/`.
Supporting testers, introspection, text output, and HTML output live under
`src/npegged`. `scripts/examples.sh` rebuilds the Pascal parser, parses the
supplied `.pas` file, and writes `build/example.txt` and `build/example.html`.
The Pascal application supports `--trace`, writing rule events to stderr. HTML output supports
selective expansion through `Expand.ifMatch` and `Expand.ifNotMatch`.
It also runs the DConf demonstrations, including a bounded version of the
intentionally naive left-recursion example.

`scripts/generate_parser.d` reproduces the checked-in bootstrap parser from
`src/npegged/definition.d`. Regenerate and format it with:

```sh
build/generate-parser
dfmt -i src/npegged/parser.d
```

`python3 scripts/generate_unicode.py --check` verifies the Unicode data tables.
The original Python example's empty-prefix acceptance is retained and tested;
it is an incomplete Python grammar. The unfinished constraints prototype now
has a self-contained boolean-constraint grammar. Pattern matching remains an
experimental demonstration, with explicit status results replacing throwing
range helpers. The XML example validates nested tags without global state. Arithmetic evaluation returns a
status and value, including errors for undefined variables and division by zero.

Memory tools must run successfully for complete validation. On restricted
hosts, LeakSanitizer may be unable to inspect threads, and Valgrind may require
libc debug symbols that are not installed. Those failures are reported as
failed checks, never counted as clean memory runs.

## Benchmark comparisons

Run `make benchmark-compare DC=ldc2` for local NPegged, Pegged, handwritten D,
and chumsky comparisons with matching validation, span, and tree outputs.
The runner verifies complete consumption and output records before timing and
reports repeated-run dispersion, MB/s, compiler/CPU metadata, and allocator
traffic. With the initial 5.0x performance target achieved across all paired acceptance
gates (513/513 checks passing), our active project goal is for NPegged to execute within
**1.5x of handwritten D baselines** across all supported equal-output workloads.
See [benchmark instructions](benchmark/README.md) for output contracts, commands, and
measurement limits.


The [performance roadmap](docs/PERFORMANCE_PLAN.md) and [Phase 2 plan](docs/Performance_Plan_Phase2.md)
track optimization milestones, lane decisions, and acceptance criteria.
