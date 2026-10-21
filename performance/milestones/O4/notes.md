# O4 — Tagged-DFA lowering of record-emitting regular regions — (a), (b), (c) COMPLETE for leaf records

## (a) Count (report only)

`tagRegionReport(definition)` (`src/npegged/grammar.d`) and `performance/scripts/o4_study.d` + `corpus-study.csv` over the 105-grammar corpus:
1,688 rules, 260 regular regions, **119 composed** (they call rules, so a record selector forbids the plain scanner), in 25 of 105 grammars
(xml2 50, markdown 21, csv 8 of 8, oberon2 6, pascal 5). Not rare, so (b) and (c) were built.

## (b) Generated recognizer with tag replay

* `RegularKind.mark` (`src/npegged/dfa.d`): an output event on the path (`0` remembers the offset, `k + 1` finishes a leaf record of kind `k`).
  The generator wraps each reference to a *compiled leaf* record rule (selector kind `!= uint.max`, `recordLeaves`, so no selected descendant)
  in open/close marks while it lowers a region (`regularTable`, `src/npegged/grammar.d`). Plain `compileDFA` treats a mark as an empty
  sequence, so the validation/accept tables, and their golden bytes, are unchanged.
* `compileTaggedDFA` determinizes with threads in priority order (earlier alternative first; a repetition goes round again before it
  leaves). Where threads that consume the same byte would fire different events, the first wins and the others are dropped (the ordered
  choice has committed). Equal events merge. The result is then **verified against the plain automaton**: a product walk from the start
  states must find the same defined transitions, accepting states and EOF-accepting states byte for byte; otherwise the table declines
  (`valid == false`) and the region is walked rule by rule as before (`static if (_dfa_X.tagged.valid)` in the generated cursor).
  This is what keeps the verdict, `examined` frontier and failure diagnostics exactly those of the existing scanner.
  Example it refuses: `a close1 / open a b close2` (the winner of `a` could not take `b`).
* `scanTaggedRecords`: straight-line state code (`codeScannerSource`, extended with the events and the accept bookkeeping) up to 48
  states, a table loop otherwise; both are tested equal. Events run before the byte they belong to; a state that accepts remembers the
  record count, the open record's start and its tail events; when the scan ends, records written past the last accepting offset are
  rolled back and the tail events of that offset run. Nothing is written when nothing is accepted.
* Work units, step budget, depth and trace: as for scanner regions (`docs/WORK_UNITS.md`): `examined - pos + 1`; attempted only when the
  budget shows the whole input and there is no trace; otherwise the original walk decides.

Tags are used only with a compile-time selector (`grammar!(…, Selector, …)`); the runtime-selector form (`void`) keeps walking.

## (c) Records parity and rollback

* Records, verdict, status and (on success) end equal those of the walked region: `tests/tagged_regions.d`
  (`scripts/tagged-regions-check.sh`) compares tagged, walked (`grammar!(…, TaggedRegions=false)`) and combinators backends on **977,413
  strings** (all strings up to length 6-8 over small alphabets) of three grammars with `\r\n?` ambiguity, quote escapes, nullable records
  and an alternation, in span and tree mode; plus the output hashes of all 176 benchmark workloads in span/tree/validation mode (322
  comparisons, 0 differences, the earlier pre-change runner against the new one).
* Rollback on late failure: a scan that accepts nothing (or only a prefix, or not at the end for anchored tables) leaves the buffer as it
  found it; an exhausted record arena fails the parse with the arena's status and leaves no record (unit tests).
* Documented difference: on a *failed* records-mode parse the reported `end` is the scanner's failure frontier (as in validation mode)
  where the walk reported the frontier of the rule it was inside. Output-limit parity is one-directional: a walk can exhaust the record
  arena through records it later rolls back, the tagged scan only through records of the accepted path.

## Measurements (Apple M1, LDC 1.43, direct backend, 3 interleaved repetitions x 7 samples x 4000 iterations, raw JSON in `raw/`)

| workload | mode | before | after | handwritten | ratio before -> after |
|---|---|---|---|---|---|
| CSV.Flat | spans / tree | 9,997 / 9,974 ns | 5,152 / 5,144 ns | 5,885 ns | 1.70 -> 0.88 / 1.69 -> 0.87 |
| CSV.MultiLine | spans / tree | 1,165 / 1,152 | 626 / 617 | 630 | 1.85 -> 0.99 / 1.82 -> 0.97 |
| CSV.SingleLine | spans / tree | 161 / 153 | 110 / 104 | 89 / 101 | 1.81 -> 1.24 / 1.52 -> 1.03 |
| CSV.LongField | spans / tree | 3,606 / 3,601 | 3,479 / 3,520 | 2,687 | 1.34 -> 1.29 / 1.33 -> 1.30 |
| corpus csv-medium-valid | spans / tree | 45,213 / 35,288 | 21,019 / 20,884 | 21,270 | 2.13 -> 0.99 / 1.65 -> 0.98 |
| corpus csv-large-valid | spans / tree | 1,278,770 / 1,073,338 | 665,234 / 667,400 | 682,050 | 1.87 -> 0.98 / 1.57 -> 0.98 |
| corpus csv-adversarial-valid | spans / tree | 9,137 | 9,493 / 9,537 | 6,448 | 1.42 -> 1.47 / 1.42 -> 1.48 |

Over all 176 workloads x 3 modes the median change is -3.0%; the largest regression is the adversarial quote-escape input (+3.9..4.4%,
more states than the plain scanner); next is +3.1% (CSV.Empty/tree), all other changes are within +-2.5% apart from the CSV improvements
above. The first version (table loop without the straight-line scanner) made long fields 5x slower; the code scanner removed that.

Checks: unit tests (26 modules), A4 differential (all fixtures, limits, both backends), `tests/tagged_regions.d`, AddressSanitizer on
the unit tests and on `tests/tagged_regions.d` (LeakSanitizer and Valgrind are not available on this arm64 macOS host), eligibility golden
hashes refreshed for the 8 generated sources that contain a leaf-record region. DMD segfaults on this host and the coverage tool needs
dmd+gdc+gcov: not run.
