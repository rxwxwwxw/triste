# S3 work in progress — not complete

## Current verification state (2026-10-20)

The final controlled report gives 87 -> 89/171 within target and 14 repeatable
>5% regressions: default NO-GO, feature stays experimental/opt-in. The tiny
cluster has only three new crossings, refuting the >=15 hypothesis. Production
source is unchanged since those measurements; later changes are unit tests,
verified by `audit-test-only.py`. Native four-way entry tests pass. Final full
coverage is collecting as session 20854, log `build/S3/coverage-final.log`;
strict coverage remains the pending acceptance check. See the latest entries
in `checks.md`. No S3 completion mark or commit yet.

## Earlier retention state (2026-10-20)

The current code keeps whole-DFA entry behind `NPeggedLeanEntry`; generic context
borrowing and the explicit finish-return experiments were rejected after isolated
measurements. Their patches and all samples are retained under `context-*` and
`finish-*`. Feature-on/off DMD/LDC entry tests and the default 72-case generated
source matrix pass. See `checks.md` for the frozen-source run handles/logs and
remaining verification. S3 is still open and uncommitted.

## Earlier continuation audit (2026-10-20)

- HEAD remains `2d501e8` (Q1); the S3 implementation and verification additions
  are uncommitted in the main worktree. The historical prototype notes below
  describe earlier stages, not the current source state.
- Q1 is already marked complete in its section and Phase 2 table. The roadmap
  header and completion inventory now agree with those marks.
- Current `tryDFAEntry` has an eight-byte input guard. Both broad and guarded
  candidate benchmark artifacts retain disclosed regressions; neither establishes
  S3's acceptance criteria. State setup, finish and invariant-hoisting requirements
  still need a requirement-by-requirement implementation/measurement audit.
- Earlier coverage refresh failed the strict branch threshold in bites, grammar,
  ll and peg. Added coverage tests in other modules have not yet been established
  as passing by a fresh complete run.
- Fresh `bash scripts/coverage.sh` is collecting into `build/coverage`, with log
  `build/S3/coverage-current.log`. Fresh DMD/LDC entry verification logs to
  `build/S3/entry-current.log`. Check live tool handles and final results before
  treating either run as finished.
- `python3 tests/test_performance_record.py`: nine tests passed in this audit.
- No S3 completion mark or commit is justified yet.

## Historical implementation notes


Q1 is committed as 2d501e8, including the roadmap audit; its full fast pre-commit
hook passed. Main worktree parser sources remain unchanged pending a fresh Linux
baseline. Earlier S2b measurements are Apple M1/macOS and cannot serve as a
same-host baseline on this Ryzen/Linux host.

The first full baseline build exceeded performance_gate.py's 300-second build
timeout. A retry is running through `/tmp/triste-long-build-gate.py`, extending
only the build timeout to 900 seconds. All runtime test/timing timeouts remain
unchanged. Expected output: `build/S3-before.json`.

Prototype checkout: `/tmp/triste-s3-ceiling` (copies of maintained source,
benchmarks, scripts, examples and vendored Pegged; no git checkout). Changes:
- `src/npegged/peg.d`: check dispatch to a generated constrained entry marker.
- `src/npegged/grammar.d`: marker only for direct, nonmemoized, whole-DFA rules
  whose ReferenceDepth is exactly zero; named entry and default opCall dispatch.
- `src/npegged/dfa.d`: tryDFAEntry uses the exact rule+scanner budget; directly
  returns known success/failure observations, otherwise replays the primitive
  body with steps=1/depth=1, matching dfaToken without a second scan.
- Metrics, scanner reports, rule reports, dependency tracing and trace callbacks
  keep the original entry path. Depth zero and step limits below two also fall
  back. Unknown, referenced, parameterized and memoized roots do not specialize.
- `tests/entry.d`: three cross-module suites cover dense limits, output parity,
  fallback grammars and tracing; `dfa.d` has an adjacent helper unittest.

Proof: scanner success and fast failure use exactly dfaToken's existing outcomes
and failure frontier. One rule tick and one depth entry are accounted before
primitive replay. ReferenceDepth=0 excludes nested rule effects. No allocation
occurs in scanner-only outcomes, preserving memoryLimit=0 and arena counters.
No State or finish construction is needed for those outcomes; remaining paths
retain exact primitive failure/limit behavior and State setup.

The throwaway unsound ceiling ignored trace/depth/step guards (never copy that
version into the repository). Its raw file is `ladder-unsound.csv` in the
prototype directory. The rebuilt exact prototype (`ladder-exact-verified.csv`)
measured ~6.99 ns on empty and one-byte inputs; ceiling ~6.98 ns. Q1's general
check path measured ~17 ns, but the initial prototype ladder uses a different
regular body; use the upcoming same-grammar paired benchmark instead of claiming
this as a controlled speedup. `benchmark/entry_pair.d` is that paired benchmark:
identical grammar and input through generated entry vs an exact wrapper that has
no marker, 21 samples after three warmup blocks, alternating order.

Focused tests: LDC and DMD prototype runs each passed 23 modules. The latest LDC
run includes the new colocated helper tests. DMD will need rebuilding after that
last helper-test addition. Tests are bounded by timeout and 4 GiB address space.
No main source edit, S3 completion mark, performance claim or commit yet.

Q1 supplemental Valgrind evidence: setting DEBUGINFOD_CACHE_PATH to the existing
`build/debug-cache-cachy` and DEBUGINFOD_URLS to the CachyOS service resolved loader
symbols without a new install. Default druntime exit collection reports an
uninitialized conservative-root scan; `--DRT-gcopt=cleanup:finalize` avoids that
scan and passed Memcheck with zero errors and zero definite/indirect leaks.
32 bytes remain possibly lost in druntime initialization; 216 bytes reachable.
This is an explicitly different runtime cleanup configuration, not a suppression
of repository errors. Q1 ASan/LSan had already passed with default cleanup.
