# `accept!` — yes/no recognition (decision D3)

```d
import npegged.peg : accept, AcceptResult, ParseContext;
ParseContext context;
AcceptResult r = accept!(MyGrammar.Root)(context, input);   // r.accepted, r.status
```

`accept` answers one question: does `parser` match the **whole** input? It equals
`check!parser(...).successful && end == input.length`, with the same `Status` (`ok`, `mismatch`, `resourceLimit`, ...) whenever
`check` finishes inside its limits, and the same work-unit accounting (`docs/WORK_UNITS.md`) except for directly left-recursive
rules (below). It differs from `check` in what it does **not** report: no `failEnd`, no
arena counters, and no failure diagnostics.

What the direct backend does with that freedom: every rule gets a second cursor, `_acursor_<Rule>`, emitted from the same code
generator with `acceptActive` set. It omits failure recording, probe bookkeeping, mismatch-offset scans, `s.failure(...)`
nodes and the scanner's diagnostic records. The exact entry `_<Rule>` routes to it when `State.acceptOnly` is set (only
`accept` sets it) and `trace` is null; with a trace, or on the combinator backend, `accept` simply runs the exact parser.

Directly left-recursive rules (P8): in the direct accept clone `E <- E S1 / .. / B1 / ..` runs as `(B1 / ..) (S1 / ..)*` when the
suffix alternatives come first, consume, and the bases never lead back to `E`. That form charges fewer work units and less depth than
seed growth, so `accept` can finish where `check` reports `resourceLimit` (never the reverse). `check`, trees and records keep seed
growth.

Guarantees, checked by `tests/differential.d` for both backends, all memo policies and dense step/depth/memory/output limits:
same verdict as `check` and the same status whenever `check` does not hit a limit; where it does, `accept` either also reports the
limit or returns the true verdict; same trace events when a trace is set.

Not implemented (C1(b)): running `check!` optimistically through the accept clone and replaying the exact parser on
rejection. `CheckResult` also carries arena counters and `failEnd`, which the accept clone does not reproduce, and a
rejection would cost both passes; `accept!` is the supported way to get the speed.
