# Grammar-driven input generation

Walking a PEG's syntax tree does **not** guarantee acceptance (ordered choice, greedy repetition, predicates), so the **real parser is
the acceptance oracle** and a generator must report failures instead of emitting invalid candidates as valid.

## G1: seeded bounded candidate generator (`src/npegged/generator.d`, `generateCandidates`)

- PRNG: splitmix64 seeded by `GeneratorOptions.seed`; the stream is a pure function of grammar, start rule, options and seed.
- Terminals: escape-free and simply-escaped literals (`\n \t \r \0 \\ \" \' \xNN`), single-byte classes (uniform member). `eps`/`eoi` emit
  nothing; predicates are zero-width and ignored by the walk. Everything else (actions, parameters, `external`, multi-byte ranges) gives
  `GenStatus.unsupported` with a reason.
- Choice: uniform proposal (weights arrive with G4). `e?`: taken with probability 1/2. `e*`: empty with probability 1/4, else
  1 + geometric(1/2) capped at `maxRepeat` (default 8); one repetition in 32 may reach 4 * `maxRepeat`. `e+`: at least one, same tail.
  A nullable body that makes no progress twice ends the loop.
- Budgets: past `softDepth` (12) choices take their minimal-length alternative (so productive grammars terminate); `maxDepth` (48)
  and `maxOutput` (4096 bytes) are hard stops reporting `budgetExceeded`; no truncated candidate is ever returned.
- No acceptance claim: candidates are proposals only (G2 filters them).

Tests: `tests/generator.d` plus unit tests in `generator.d` (determinism, divergence, branch coverage, recursion stop, nullable loop,
EOF, UTF-8 roundtrip, unsupported, budgets, splitmix64 reference value).

## G2: full-acceptance oracle (`generateAccepted!(parser)(definition, startRule, count, options, maxAttempts)`)

Every proposal is parsed by the real compiled rule (`parser`, e.g. `Fixture.Root` from `mixin(grammar!(...)(definition))`) with a fresh default
`ParseContext`. A sample is listed in `AcceptedSet.texts` only if the parse succeeded **and consumed the whole input**; resource-limit
statuses and partial consumption count as rejections. The definition/parser pairing is the caller's responsibility (it is not checked).

`AcceptedSet` reports `proposed`, `rejected`, `generationFailures` (unsupported constructs, depth/output budgets, with distinct
reasons) and `exhausted` (the `maxAttempts` budget ran out before `count` samples were accepted; the samples found so far are still
verified). Nothing unverified is ever returned as valid. User actions are never run: a start rule that reaches an action fails
generation as `unsupported` (the parse of a candidate never happens for it).

Tests (`tests/acceptance_oracle.d`, 90 s alarm): the candidate trap `('a' / 'ab') 'c'` (proposes `abc`, which the PEG rejects; only
`ac` is returned), the impossible branch `'a'* 'a' eoi` (budget exhausted, nothing listed), lookahead rejection, a disjoint grammar
(no retries), attempt-budget exhaustion, unsupported actions, reproducibility, and an independent re-check of every returned sample.

## G3: coverage-guided generation (`generateCovering!(parser)`, `src/npegged/coverage.d`)

Coverage comes from **accepted parses**, never from what the generator proposed. Each accepted sample is replayed by a reference PEG
derivation over the expression graph (`Attributor`), which records the winning alternative of every choice, `e?` taken/skipped and
`e*`/`e+` iteration buckets (0, 1, many). A sample the matcher cannot follow (actions, unknown nodes, left recursion, or a
disagreement with the parser) is counted as `unattributed` and contributes nothing.

Targets in rules the start rule cannot reach are `unreachable`; targets whose subtree has constructs the matcher cannot evaluate are
`unknown`. Both are reported separately and excluded from `covered/coverable`.

Guidance (before every proposal): uncovered alternatives get weight 8 (covered ones 1); an uncovered optional or repetition outcome is
favored three times in four. `CoveringSet` reports accepted samples, `covered`, `coverable`, `unreachable`, `unknown`, `unattributed`,
`uncovered` descriptions, and both `proposedAlternatives` (what the walk chose) and `exercisedAlternatives` (what accepted samples
use); they differ for `('a' / 'ab') 'c'` (2 vs 1). The attempt budget bounds unreachable targets.

Measured (`tests/coverage_generation.d`, ten-alternative choice, 8 seeds): 12 samples cover 76/80 targets with guidance vs 57/80 without;
20 samples cover 80/80 vs 70/80. Fixed seeds reproduce results.
