# R02 — memo dependency trace

Reproduce: `python3 scripts/memo-dependencies.py performance/results/R02`.
The collector uses NPeggedDependencyTrace only, 60-second runners, 4 GiB address
space and 8192 caller-owned event slots per buffer. No parser invalidation or
memo policy changes. The diagnostic layout is larger; do not use it for timing.
Ordinary builds contain neither the sink/type/context field nor event branches.

## Protocol and bounds

IDs start at one and increase per trace, never wrap and never refer to addresses.
Created events identify rule names and positions; events log each seed-loop
iteration, active seed hit, completed cache hit, successful growth, broad
retirement and completion. Caller zero means outside a memoized evaluation (e.g.
a non-memoized root); non-memoized helpers within a memoized body retain its caller
ID. The fixture adds a CSV kind-7 case terminator, not a parser event. Missing
terminators, active retirements, dangling IDs and discontinuous sequences are
rejected by the analyzer. Raw CSV hashes and source manifests are retained.

The sink owns no memory and allocates nothing. It never grows its caller's slice.
Overflow/ID exhaustion sets truncated and discards further diagnostics without
changing parser status. A truncated trace cannot justify keeping entries. The
fixture checks exact trace repetition with fresh buffers and tests one-slot
saturation under finite step limits. Use independent mutable sinks across threads.

The analyzer propagates conservative active-seed read sets through newly evaluated
and already completed memo calls, up all active memo callers. It unions reads from
all iterations, including failed probes, rather than claiming a minimal dependency
set for the final seed. Graph edges mean `(dependent entry, consulted seed ID)`.
They do not describe arbitrary action/global-state effects or prove purity.

## Regression evidence

| Backend / memo | Cases | CSV rows | Broad retirements | With recorded seed dependency | Missed by direct-read-only policy |
|---|---:|---:|---:|---:|---:|
| combinators / full | 112 | 2149 | 101 | 33 | 14 |
| combinators / selective | 112 | 1377 | 49 | 33 | 14 |
| direct / full | 112 | 2149 | 101 | 33 | 14 |
| direct / selective | 112 | 1377 | 49 | 33 | 14 |

Fixtures include direct, indirect, mutual, nullable recursion; overlapping choices;
nested instances at different positions; two simultaneous recursive heads at the
same position; and transitive completed-cache dependencies.

The important counterexample is TraceCached on `aaa`:

```
H <- B / 'a'
B <- &C D
D <- C 'a'
C <- H
```

`&C` evaluates C using the active H seed, then D consumes that completed C entry.
D depends on H despite never directly consulting an active seed. Retaining D (or
B) solely because it has no direct seed read can freeze growth at an older result.
The reference recognizes all three bytes. In full memo mode there are eight broad
retirements and all eight have a recorded H dependency; five require transitive
propagation. Selective mode has the same retirement/dependency counts.

TraceNested on `(((n)))` has four simultaneously active Expr instances. Full memo
creates 46 entries and retires 37; selective creates 15 and retires 11. None of
those retirements has a recorded dependency on the *growing outer* seed. This is an
opportunity to investigate, not a proof that general retention is safe: the graph
omits arbitrary semantic effects and context-dependent resource/work accounting.

## Checks

- Source-adjacent unit tests pass under DMD/LDC with the diagnostic flag.
- Both compilers pass the full F02 differential corpus with the sink enabled,
  including deliberate saturation, exact tree/record/failure fields, callbacks,
  CTFE and finite limits. scripts/differential.sh now forwards compiler flags.
- DMD and LDC emit byte-identical combinator/full fixture streams. Each fixture
  also repeats every parse and checks identical IDs/events in-process.
- Sink ID exhaustion, absent-entry tracing, null sinks, cache hits, saturation,
  active-head lifetimes and nested/cached dependency propagation have tests.
- Both compilers emit zero -vgc diagnostics with the trace flag. Separate static
  assertions verify the field/type/current-frame pointer disappear without it.
- Diagnostic ASan/LSan passes outside the sandbox's LSan ptrace restriction;
  diagnostic Valgrind uses the repository GC test configuration and reports zero
  errors and zero definite/indirect leaks. No suppressions.
- Default-build full repository checks are being recorded separately; R02's
  runtime changes are exclusively behind the explicit diagnostic version.

R03 must use a proven action-free subset, retain a general fallback, and handle
cached transitive dependencies. A direct-read-only invalidator is rejected by this
corpus. No defaults are changed here.
