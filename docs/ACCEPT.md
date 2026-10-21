# `accept!` — yes/no recognition (decision D3)

```d
import npegged.peg : accept, AcceptResult, ParseContext;
ParseContext context;
AcceptResult r = accept!(MyGrammar.Root)(context, input);   // r.accepted, r.status
```

`accept` answers one question: does `parser` match the **whole** input? It equals
`check!parser(...).successful && end == input.length`, with the same `Status` (`ok`, `mismatch`, `resourceLimit`, ...) and the
same work-unit accounting (`docs/WORK_UNITS.md`). It differs from `check` in what it does **not** report: no `failEnd`, no
arena counters, and no failure diagnostics.

What the direct backend does with that freedom: every rule gets a second cursor, `_acursor_<Rule>`, emitted from the same code
generator with `acceptActive` set. It omits failure recording, probe bookkeeping, mismatch-offset scans, `s.failure(...)`
nodes and the scanner's diagnostic records. The exact entry `_<Rule>` routes to it when `State.acceptOnly` is set (only
`accept` sets it) and `trace` is null; with a trace, or on the combinator backend, `accept` simply runs the exact parser.

Guarantees, checked by `tests/differential.d` for both backends, all memo policies and dense step/depth/memory/output limits:
same verdict as `check`, same status, same trace events.

Not implemented (C1(b)): running `check!` optimistically through the accept clone and replaying the exact parser on
rejection. `CheckResult` also carries arena counters and `failEnd`, which the accept clone does not reproduce, and a
rejection would cost both passes; `accept!` is the supported way to get the speed.
