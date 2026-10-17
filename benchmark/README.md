Run `python3 scripts/compare_benchmarks.py --iterations=20 --samples=5
--output=build/comparison.json` from the repository root to build and compare
NPegged, vendored Pegged, handwritten D, and pinned chumsky 0.13.0 locally.
The command is written on two lines here; invoke it as one shell command.
Rust dependencies are locked in `chumsky/Cargo.lock`; the first build needs
crates.io access. D defaults to LDC; set `DC=dmd` or `DC=gdc` to change compiler.
Use `--filter=JSON.Small` to restrict timed cases while retaining acceptance gates.
All build and benchmark subprocesses have deadlines.

The report embeds compiler versions, release flags, CPU/platform, Git revision,
worktree status, repeated-sample mean/min/max, decimal MB/s, actual iterations,
and checksums. One warmup sample precedes measured samples. Parsing, output
construction/projection, fingerprinting, checksum updates, and disposal are timed;
parser construction and correctness checks are outside the intervals. Timed
checksums are checked after each interval against the expected repeated result;
resource failures cannot count as expected invalid input. A volatile input barrier
keeps pure D validators inside the loop, and Rust uses `black_box`. Increase
iterations when samples reach clock resolution (zero elapsed time reports zero
MB/s). Invalid-input throughput uses submitted input bytes, even for early failure.

Inspect the optimized LDC timing loop with
`objdump -d --disassemble=_Dmain build/ldc2/benchmark_runner`. The inspected
release binary retains the `observeCase` call and volatile checksum update
between the loop target and its backward branch, inside the two clock reads.
This verifies that the current runner executes observations on each iteration;
it does not establish whether older benchmark binaries eliminated parsing.

Three output obligations are identical across engines and checked record by
record before timing:

- `validation`: complete input acceptance, with no retained output.
- `spans`: ordered scalar token spans, including object keys. A span is a kind
  plus byte begin/end; quotes and escapes remain in the original input.
- `tree`: the full concrete JSON value tree as preorder records with kind, byte
  begin/end, and parent index. Objects contain ordered key/value children;
  arrays contain ordered values. No engine decodes strings or converts numbers.

The caller retains immutable input for every engine. Copies required by an
engine are included. NPegged validation uses its synchronous borrowing recognizer
(`execution=recognition`), with memo storage still included. Its spans/tree modes
and all Pegged modes build native generic trees and project them to these outputs
(`execution=native-tree-projection`). Chumsky validation uses `Parser.check`;
its span/tree outputs project a native AST. The handwritten parser emits the
common outputs directly. Equal output obligations do not imply equal internal
work; the measurements expose the cost of each current implementation.

The corpus covers small/medium JSON, large strings, escape-heavy and
whitespace-heavy documents, deep nesting, invalid escapes/numbers/trailing
bytes/truncation, and an ambiguous ordered-choice grammar with a shared long
prefix, `('a'* 'b' / 'a'* 'c') eoi`. That grammar emits one whole-input span in
span/tree modes. Acceptance gates also exercise JSON syntax independently of
timed-case filtering.

`--memory` on the D runner measures one extra parse outside timing. Allocator
calls include failed allocator invocations; payload bytes count successful
requests; reserved bytes count cumulative successful block requests, including
arena block/alignment overhead. These figures are allocation traffic, not live
output size or malloc usable-size. NPegged counts parser plus common output;
handwritten counts common output. Pegged counts common output only (its parser
uses GC); `arenaMeasured=false` identifies that incomplete allocator scope.
Chumsky measures actual allocator calls and successful requested bytes in an
extra parse, including reallocations; reserved bytes are `null` because portable
System allocator overhead is unknown. GC counters are reported separately and
exclude malloc traffic. Parser construction is excluded from allocator samples.

The NPegged comparison grammars explicitly use `Memoization.selective`.
JSON groups ordinary string runs into a fused lexical rule with escape fallback;
the same grammar text is used for both PEG engines. The acceptance language and
common output records remain checked. Validation of these grammars allocates
no parser storage; owned tree output still includes its allocation and copying.

Use `--target-engines` on the D runner to time NPegged and handwritten D only.
All-engine acceptance/output checks still execute before timing. This avoids
spending most of a high-iteration target measurement in the contextual Pegged
engine. The four-engine comparison script keeps its original engine set.

For the D engines alone, run `scripts/benchmark.sh --mode=tree --memory --json
--iterations=20 --samples=5` as one command. Omitting `--mode` retains the legacy
mixed-output suite (arithmetic, CSV, numbers, and PEG grammars as well as JSON).
Those legacy rows have different output obligations and should not be used as
equal-work ratios. `--export-corpus` emits shared inputs and expected output
records for the Rust runner. JSON schema version 2 replaces the former subprocess
RSS and approximate GC-live metrics; `arenaCumulativeBytes` is a compatibility
alias for `reservedBytesPerOp`.

Run `make benchmark-checks` for DMD/LDC unit/integration checks and diagnostic
line coverage. Use `BENCH_BRANCH_COVERAGE=1 make benchmark-checks` to additionally
collect diagnostic branch coverage with GDC 16 and matching gcov. The greater-than-90% coverage gate
applies only to `src/`, through `make coverage`. Benchmark coverage collection runs in
isolated directories and includes generated comparator wrappers. Runner coverage
uses the release assertion/bounds settings of the measured executable; helper
unit coverage keeps assertions and bounds checks enabled. The raw reports
and source hashes are in `build/benchmark-coverage`.

Run release integration checks with `python3 tests/test_benchmark.py
build/ldc2/benchmark_runner` and `python3 tests/test_benchmark_comparison.py`.
The D helper modules contain adjacent unit tests; Rust tests run with
`timeout 30s cargo test --locked --manifest-path benchmark/chumsky/Cargo.toml`.
Chumsky parser APIs are documented at
https://docs.rs/chumsky/0.13.0/chumsky/trait.Parser.html.

`python3 scripts/performance_gate.py` builds once and runs NPegged/handwritten
pairs in three independent processes per output mode, each with seven measured
samples. It writes raw measurements, per-case ratios, failures and source/compiler
metadata to `build/performance-acceptance.json`, and fails if any ratio exceeds 5.
It rejects unequal outputs, incomplete pairs, unresolved clocks and source changes
during measurement. Use `--modes validation` to gate that mode separately; a
partial-mode pass is not a full performance-plan acceptance. The corpus covers JSON/ambiguity in all output modes, arithmetic/CSV in validation,
spans and tree modes, and numbers/PEG syntax in validation mode.
Run it without concurrent compilation or other heavy work. `make DC=ldc2
performance-check` is equivalent (one shell command).

### Additional handwritten validation workloads

`--workloads` selects paired NPegged/handwritten validation for arithmetic, CSV,
scientific/hex/binary numbers, and the handwritten PEG syntax recognizer:

```bash
scripts/benchmark.sh --workloads --json --memory --iterations=2000 --samples=7
build/ldc2/benchmark_runner --workloads --export-corpus
```

NPegged uses selective generated recognition grammars in `workload_grammars.d`.
The default workload mode measures boolean acceptance with complete consumption;
input is borrowed synchronously. `--workloads --mode=spans` and `--mode=tree` select
arithmetic/CSV output obligations. Numbers and PEG syntax remain validation-only.
The suite omits Pegged because its illustrative grammars have different syntax.
The PEG adapter follows the handwritten recognizer's permissive syntax (including
balanced parameter text and repeated suffixes), rather than the bootstrap language.
Adjacent differential tests cover short exhaustive arithmetic/CSV/numeric inputs
and PEG token combinations. The default repeated `performance_gate.py` now includes
this corpus in addition to the requested JSON/ambiguity output modes. A pass still
requires every row to meet 5× in every run; exploratory results are not acceptance.

### Isolated DFA token scanning

The phase-2 scanner benchmark measures numbers, identifiers, whitespace, line
comments, unescaped strings, and strings with escaped quotes every 64 bytes.
Each token spans 1 MiB, with 64 iterations per
sample, seven samples per run, and three runs. Every token must reach 1.0 GB/s in
every run. Parsing results feed an observable checksum. Input allocation and CTFE
automaton construction are outside the timed region.

```bash
ldc2 -I. -Isrc -defaultlib=druntime-ldc -fno-exceptions -O3 -release \
  -boundscheck=off -w -i benchmark/dfa_scanning.d -of=build/dfa-scanning
timeout --kill-after=2s 60s build/dfa-scanning
```

Run this on an idle machine. Its isolated throughput result complements the
paired performance gate; it does not establish whole-parser performance.

### Experimental direct recognition backend

Use `PARSER_BACKEND=direct python3 scripts/performance_gate.py --output
build/direct-acceptance.json` to compare the direct generator against the same
handwritten corpus and output obligations. The default backend is `combinators`.
The chosen backend, build wall time, binary bytes, compiler flags, and source hashes
are recorded in the report. `.text` section bytes are also recorded when the
`size` utility is available. When `/usr/bin/time` is available, the captured compiler
log also contains compiler elapsed time and peak RSS. Binary bytes include data and
debug/metadata sections; inspect object text size separately when evaluating inlining.

Library callers select `grammar!(Memoization.selective, void,
ParserBackend.direct)(definition)`; the third template parameter also applies to
`generate` and `asModule`. This experimental backend emits scalar recognition
control and eligible non-memoized rule calls. Existing scanners remain available;
unsupported expressions, memoized rule boundaries, actions, tracing, parameterized
grammars, legacy trees, and compact-record output retain compatible paths. Performance
acceptance is still pending; selecting this backend does not imply every grammar
or output mode improves. See the implementation record for measured experiments.

Arithmetic spans are number/identifier byte intervals. Arithmetic trees retain concrete
Root, Term, Factor, Primary, Number, and Identifier rules, including whitespace in
syntactic rule intervals where the grammar consumes it. CSV spans retain Field
intervals, including quotes and surrounding spaces; trees add a Root parent. Empty
fields are included, including after a trailing separator. Invalid parses produce
empty output. Exported output corpora include the exact expected records.

`workload_output.d` implements independent handwritten output parsers and generated
selected-record projections. Both construct output while parsing, use the same record
layout and consumer, and include allocation/disposal costs. Every output row is checked
record by record before timing; fingerprints remain consumed in the timed loop.
The direct backend now also lowers compact-output control while preserving selected
rule boundaries, rollback, and lookahead suppression. Full current-tree acceptance
remains pending; historical gate results do not establish acceptance of later edits.

### Left-recursion scaling

Run `bash scripts/recursion-scaling.sh > build/recursion-combinators.csv`, then
`python3 scripts/summarize-recursion.py build/recursion-combinators.csv`.
Repeat with `PARSER_BACKEND=direct` for the experimental backend. Copy
`build/recursion-scaling/metadata.json` beside each CSV before the next build;
metadata records compiler/flags, backend, CPU, and source hashes.

`PARSER_MEMOIZATION=full` selects full memoization instead of the default selective
policy. Run both policies with both backends to isolate memoization and execution
costs. All combinations retain the same three output obligations; comparing tree
timings to recognition timings is a cost breakdown rather than an acceptance ratio.
`bash scripts/recursion-matrix.sh [output-directory]` runs all four configurations
sequentially, preserving timing samples, summaries, counters, and their separate
source manifests. Each execution has the scaling runner's 60-second timeout.

The timeout-bound LDC release probe exercises direct and indirect left recursion
at 8–512 terms, seven samples per size, with valid and trailing-operator inputs.
Recognition, borrowed compact records selecting every named rule, and owned legacy
trees are separate obligations. Samples include construction and disposal; allocator
metrics are captured before disposal. It checks expected success/mismatch status.
The summary reports medians and adjacent-size growth, with no performance pass
threshold. It measures cumulative arena traffic, not live memory or dependency and
snapshot counters. This probe supplements the equal-output gate; it cannot establish
full acceptance or isolate a specific source of quadratic growth by itself.

Use `PARSER_METRICS=1 bash scripts/recursion-scaling.sh > build/recursion-metrics.csv`
for a separate diagnostic build. `NPeggedMetrics` adds an optional caller-owned
`ParseMetrics` pointer to `ParseContext`, recording memo calls/hits, successful seed
updates, invalidation visits/entries, and snapshot payload bytes. This build emits
one counter row per case rather than timing samples; do not feed it to the timing
summarizer or compare its timings. Ordinary builds compile out these fields and
branches entirely. Counters aggregate the parse rather than identifying each rule.
