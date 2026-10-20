# O1 — Whole-body DFA for regular leaf-record rules — CLOSED NO-GO (premise does not hold)

Roadmap premise: CSV `Field` is a leaf record whose body is regular "under the same eligibility rules validation
uses", so a single `dfaToken` over the body would replace the node-by-node cursor.

Finding: validation compiles `Root` (not `Field`) into one DFA. `regularLeaf` accepts `Field`'s
`'"' ('""' / !'"' .)* '"'` doubled-quote escape loop only with `anchored == true` (the DFA must reach end-of-input,
so longest-match cannot disagree with the PEG's possessive escape loop) and only given Root's follow context
(`Sep` / `eoi`, which exclude `"`). For `Field` on its own `regularTable` returns null
(`performance/milestones/O1/csv_spans_generated.d.txt`: `_cursor_Field` is built from four separate
`_dfa_Field*` scanners plus a `predictiveChoice`, i.e. `emitTokens` merged what it could and no whole-body table
exists). `"a""` is the counterexample for an unanchored whole-body Field scanner: the PEG fails (the escape loop
takes the pair and no closing quote follows) while longest-match returns `"a"`. Making it exact needs a
context-sensitive proof over every call site of the leaf (follow sets) plus lookahead-aware accepting states,
which is the tagged-DFA / region work of O4, not a local change.

Where the premise does hold (Arithmetic `Number`, `Identifier`, `Numbers.*` leaves), the body already becomes a single
`dfaToken` and the direct cursor already routes it (`directRecords`); there is nothing left for O1 to do.

Disposition: closed NO-GO. The CSV-records gap is attacked by S4 (scanner calls), O2 (checkpoint elision, -5.2%
on CSV.Flat/spans), O3 (record put) and, if profiles justify it, O4.
