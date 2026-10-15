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

Run `make benchmark-checks` for all three D compilers, unit/integration checks,
and diagnostic line/branch coverage reports. The greater-than-90% coverage gate
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
partial-mode pass is not a full performance-plan acceptance. The current corpus
covers JSON and ambiguity; the other handwritten workloads still need adapters.
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
Both engines return boolean acceptance with complete consumption; input is borrowed
synchronously. These rows do not time generic trees or claim span/tree coverage.
The suite omits Pegged because its illustrative grammars have different syntax.
The PEG adapter follows the handwritten recognizer's permissive syntax (including
balanced parameter text and repeated suffixes), rather than the bootstrap language.
Adjacent differential tests cover short exhaustive arithmetic/CSV/numeric inputs
and PEG token combinations. The default repeated `performance_gate.py` now includes
this corpus in addition to the requested JSON/ambiguity output modes. A pass still
requires every row to meet 5× in every run; exploratory results are not acceptance.
