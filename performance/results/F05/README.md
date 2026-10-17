# Four small PEG gate failures: diagnosis, not optimization

Reproduce the focused experiment with:

```
bash scripts/peg-probe.sh build/peg-probe
python3 scripts/summarize-peg-probe.py build/peg-probe performance/results/F05
```

The fixture reads the existing `pegGrammar` text verbatim via a compile-time string
import. It instantiates only the focused parser, avoiding unrelated benchmark
grammars. All four backend/memo combinations have three independent runs × seven
samples × 2000 parses. Raw timing, untimed semantic trace counts, source hashes,
flags, compiler version, machine metadata and optimized-code evidence are retained.
Each runner has a 60-second timeout and 4 GiB address-space limit.

## Fresh gate evidence

The complete F01 gate passed 380/387 checks. Seven failures span four inputs:

| Input | Exact shape | Bytes | Ratios in runs 1 / 2 / 3 |
|---|---|---:|---|
| Permissive | `G: A <-- / []**` | 15 | 5.754 / 5.175 / 4.704 |
| Truncated | `G: A <- ('a'` | 12 | 4.493 / 5.229 / 4.608 |
| Trailing | `G: A <- 'a' )` | 13 | 4.495 / 4.927 / 5.146 |
| Deep | `G: R <- ` + 64 opening parentheses + `'x'` + 64 closing parentheses | 139 | 5.391 / 5.324 / 5.420 |

All four NPegged validation rows report **zero allocations, requested bytes and
retained arena bytes**. Corpus construction is outside the timed parse loop in
both the complete gate and this fixture. Recognition borrows the input. Input
copying and resource disposal therefore cannot explain these validation failures.

`timing-summary.md` separates uninstrumented end-to-end parsing from diagnostic
clock probes around State/context setup, parser body/finish and arena teardown.
Stage percentages normalize the three measured stage intervals; each interval
includes a clock probe, and teardown includes the observation sink. They are
approximate upper bounds on setup/teardown costs, not exact gate CPU percentages.
The body accounts for 77.6–80.5% in the three short combinator/selective cases and
99.1% in Deep. The focused binary omits generic workload dispatch, so its absolute
ns/parse must not replace the complete equal-output acceptance gate.

Full memoization is substantially slower than selective on all four focused cases.
Direct/selective is faster in this fixture, especially for Deep, but no parser
policy or default has been changed and no global <=5× success is claimed.

## Optimized code and shape-specific decisions

`assembly-evidence.json` retains disassembly SHA-256 hashes, per-symbol static
instruction/call/conditional-branch counts and representative call instructions.
Regenerate full disassembly with `objdump -Cd build/peg-probe/<mode>.runner`.
Counts include cold trace/resource paths; they are not executed-branch counts or
a sampled CPU profile. The trace cohort enables tracing and therefore exercises
the reference fallback for rewritten bodies; its counts describe semantic rule
frequency, not the instruction distribution in the untraced fast path.

| Failed shape | Remaining code and observed rule frequency | Follow-up / deferral |
|---|---|---|
| Permissive | TopBoundary called once; Prefix/Primary once; Sp four times. Combinator TopBoundary retains 6 calls and 52 conditional branches, including charClass, repeat.scan, literal, ParamGuard and ParamAhead. | Defer a boundary-specific rewrite: one boundary call does not establish a dominant duplicated probe. Evaluate the shared empty-Sp candidate below first. |
| Truncated | Prefix/Primary twice; Sp four times; SequenceBoundary once. Combinator Prefix retains 14 calls / 98 conditional branches and Primary 27 / 149. | Defer failure-replay redesign: exact failEnd must be retained and this measurement does not isolate one safe shortcut. Shared empty-Sp candidate is applicable. |
| Trailing | TopBoundary once; Prefix/Primary once; Sp three times, followed by rejection of the unmatched closing parenthesis. | Defer accepting a faster top-boundary predicate until exhaustive predicate/EOF/finite-budget equivalence is established. Shared empty-Sp candidate is applicable. |
| Deep | Prefix/Primary 65 times, SequenceBoundary 64 times, Sp 131 times. Direct SequenceBoundary still has 77 instructions / 13 conditional branches; direct Sp has 579 / 92 and 3 repeat.scan call sites. | Choose the empty-Sp scalar-lowering experiment as one bounded, one-file candidate. Recursive invalidation is not implicated by this non-left-recursive input. |

## Checkpoint F

Choose **H05: specialize the empty whitespace/comment `Sp` path in grammar.d's
existing direct lowering**, after H01 confirms rule eligibility. The hypothesis is
that avoiding surviving repeat.scan/cursor work when the next byte is neither
whitespace nor `#` helps the 3/4/4/131 semantic invocations above. This is a candidate,
not a claim that Sp consumes most CPU: profiling and isolated micro-measurements
must confirm the hotspot before editing. Preserve the reference fallback, trace
sequence, exact failure offsets and finite step/depth/output accounting. Require
>=15–20% repeated improvement in the intended case and the full differential
matrix; abandon the experiment if the existing lowering already removes that work
or the proof/performance threshold fails. Only grammar.d may change for that fix.

Classify recursion as **output-dominated in the measured chains**: F04 shows
quadratic snapshot/restore bytes and linear recognition invalidation/hash visits.
Do not promote narrower invalidation based on historical scaling numbers. R04/R05
are the evidence-backed recursion follow-ups; they remain outside Phase F.
