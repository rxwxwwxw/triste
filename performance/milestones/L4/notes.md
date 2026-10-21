# L4 — Bounded-lookahead (LL(k)) dispatch — COMPLETE for literal prefixes up to 4 bytes (direct backend)

`literalChoiceK!(texts...)` (src/npegged/peg.d): an ordered choice of 1-4 byte literals (at least one of 3-4 bytes; the 1-2 byte case
stays on P3's table) is evaluated by a walk down a trie over the alternatives, keeping the smallest terminal index passed, which is
exactly the winner of the ordered choice (the lowest-index alternative that is a prefix of the input). It replays what the ordered
choice records: earlier alternatives fail after the bytes they share with the input (the deepest trie node an earlier alternative
still passes through), and with no winner every alternative failed at the walk's depth. `grammar.d` selects it for the direct backend
(`firstTwoChoice`, <= 240 trie nodes, <= 254 alternatives) and emits the walk natively in cursors; the accept clone uses
`winnerOnly` (no path, no replay). Combinator backends keep the plain choice unless `NPeggedFirst2`.

Exactness: peg.d unit test (every input up to length 4 over `<=>.!x`, 12 alternatives, step limits 0/1/5/100, end/failEnd/status
against the combinator choice, plus `dispatch`/`winnerOnly` agreement), the A4 differential fixture with 3-4 byte operators
(`<<=`, `...`, `>>=>`; all inputs up to length 5 over `<=.>x`, limits 0..15, all output modes, tracing on/off), with and without
`NPeggedFirst2`, A4 + 26-module unit tests, scripts/build.sh and the fixture checks on LDC. DMD, sanitizers, Valgrind, coverage
tooling: not run on this host.

Measured (Ops family now with `<<=`/`>>=`; Apple M1, LDC 1.43, direct; 3 interleaved repetitions x 9 samples x 20000; raw JSON here):
validation, before (ordered choice) -> after (trie): Empty 30.1 -> 15.7 ns (-48%), Pairs 73.7 -> 43.8 (-41%), Invalid 42.2 -> 27.3 (-35%),
Short 114 -> 77 (-32%), Long (7.4k operators) 82.6 -> 68.2 us (-17.5%), LongInvalid -16.5%, Truncated -10%. Accept mode (where the ordered
choice records nothing and is already cheap): tiny cases improve (Empty 19 -> 14 ns, Pairs 36 -> 32), Long is within noise to +5%
(42.6 -> 44.8 us). Ratios vs handwritten stay above 1.5x (accept Long 2.5x, validation 3.8x).

Corpus study (`performance/scripts/l4_study.d`, `corpus-study.csv`; 105 real grammars, 25,520 choice pairs): 10,652 FIRST/FIRST conflicts;
a bounded literal prefix resolves 271 pairs at k=2 (P3), 50 at k=3, 9 at k=4, 78 deeper; 10,218 conflicts are not literal-prefix
resolvable at all (unbounded: classes, rules, repetitions) and 6 are shadowed. Bounded-prefix dispatch therefore reaches about 3% of the
conflicts; the extra k=3,4 coverage is 59 pairs. Regular-lookahead DFA classification beyond literals (LL-regular) was not built: the 10k
unbounded conflicts would need it, but they are not literal choices and no benchmark workload contains one.
