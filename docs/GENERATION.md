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

## G4: weighted choice and repetition policies (`generateWithPolicy!(parser)`, `src/npegged/policy.d`)

Weights live **outside** the grammar syntax, in a line-based policy text (`#` comments):

```
choice   <Rule> <k> weights <w0> <w1> ...     # k-th choice in the rule body (preorder; references not followed)
optional <Rule> <k> probability <0..1>        # up to three decimals
repeat   <Rule> <k> histogram <n>:<w> ...     # relative weight of each repetition count n (e.g. long-tail runs)
attenuation <0..1>                            # recursive alternatives are scaled by attenuation^depth
zero-weights allow|deny                       # default allow
```

Validation is strict and reports every error with its line: weights and counts are plain non-negative decimal integers (negative,
NaN, infinite, decimal or malformed numbers are rejected), probabilities have at most three decimals (nothing is rounded silently),
a zero weight disables an alternative only when allowed and when another alternative of that choice stays positive, histograms need a
positive total. A policy with errors, or one that does not bind (unknown rule or ordinal, wrong number of weights), generates nothing
and reports `problems` — there is no silent fallback to default weights. Output and depth budgets stay in `GeneratorOptions`.

Attenuation keeps availability: with it active every weight is scaled by 1000, a recursive alternative (one that can reach its own
rule again) is multiplied by `attenuation/1000` per level of depth and floored at 1, so recursion becomes less likely, never impossible.

`PolicyGeneration.metadata` is the normalized policy as JSON (weights, share in permille, probabilities, histograms), so a generated
corpus records how it was made. Same grammar, seed and policy reproduce the stream exactly. Defaults reproduce G1 behavior bit for bit.

Tests (`tests/policy_generation.d`): 80%/10% distribution, disabled branch, malformed and unbound policies, long-tail histogram, optional
probability (0.9 and 0), attenuation shortening recursive derivations, and output-budget failures (not truncated samples).

## G5: learning weights from representative inputs (`learnPolicy!(parser)`, `compareToHoldout!(parser)`, `src/npegged/learning.d`)

Every corpus input is parsed with the real rule; only inputs accepted with the whole input consumed are learned from, and each is
replayed through the reference derivation (the G3 `Attributor`) to count which alternative each choice took, whether each `e?` was
taken, and exact repetition counts. `LearnedModel` reports `accepted` (used), `invalid` (rejected by the parser, ignored),
`unattributable` (accepted but not followable, e.g. actions or left recursion; ignored; no action is ever executed), a G4 `policyText`
(alternative weights = counts + smoothing, default 1, optional probabilities in thousandths, histograms of observed counts), and a
`provenance` string.

Limits, stated in the model: it is a **marginal** model. Each construct is modeled independently of context (a rule reached from
two parents shares one statistic; correlations between neighbors, token classes or depth are lost), so it does not reproduce the
joint distribution of real inputs, and it inherits the corpus's sampling bias. Counts are commutative: replaying a corpus in any
order gives the same text.

`compareToHoldout` gives holdout distances (permille): mean absolute difference of alternative shares and total variation of
power-of-two length buckets, plus mean lengths. Test (`tests/learning.d`): from a 3000-input corpus with known weights, the learned
`'a'` share is within ±6 points of 70%, the learned policy's regenerated samples are closer to a held-out corpus than default
weights (share distance < 60 permille), noise (invalid, unattributable) is ignored with exact counts, and the model is reproducible.
