# H02 — rule-local knowledge and potential actions

Eligibility rows now include `known` and `actionful`. An unrelated opaque or
action-bearing rule no longer taints the local facts for every pure rule. These
facts are descriptive only: scalar/direct dispatch and memoization retain the
existing grammar-wide barriers. H03/H04 are separate policy changes.

`known` means the parser-expression structure and referenced rules are understood.
It does not mean action-free, terminating, acyclic, or eligible for a fast path.
`actionful` conservatively means execution may invoke actions. Opaque references
and parameterized entries are unknown and potentially actionful. Action callback
D code is not inspected: an explicit action with a known operand is structurally
known but remains actionful, as do all its transitive callers.

Actual direct/selective fixture rows:

| Rule | Known | Potential actions | Existing scalar eligibility | Existing memoization |
|---|---|---|---|---|
| MixedEffects.Root | yes | no | no | yes |
| MixedEffects.Pure | yes | no | no | yes |
| MixedEffects.Opaque | no | yes | no | yes |
| MixedEffects.CallOpaque | no | yes | no | yes |
| MixedEffects.Effect | yes | yes | no | yes |
| MixedEffects.CallEffect | yes | yes | no | yes |
| MixedEffects.CycleA / CycleB | no | yes | no | yes |
| MixedEffects.PureA / PureB | yes | no | no | yes |
| MixedEffects.Literal | yes | no | no | yes |

The grammar-wide `conservative`, textual `actionRules`, actual eligibility fields
and scalar blocker lists retain H01's meaning. In particular, `Literal` contains
`action!(` as literal data; the existing textual barrier still applies even
though the new local facts correctly find no semantic action there.

## Proof boundary and implementation

A separate graph is built only for requested reports. It never replaces or
mutates the graph used by FIRST analysis, left recursion, memo policy or lowering.
The small grammar.d helper is necessary to expose action operands to diagnostics;
ordinary analysis intentionally treats the entire action expression as unknown.
Nested action operands preserve their call dependencies. Callback text is never
executed or used as a purity assertion.

The diagnostic frontend has independent parameter scope. Parameterized rules and
all rules in a parameterized grammar are unknown; a parameter name declared in
one rule does not hide an unrelated real rule elsewhere. Template calls whose
names shadow locally declared rules, including builtin-like names, stay unknown.
Unicode terminals with unknown FIRST bytes remain structurally known.

`GrammarAnalysis.ruleEffects` collects every understood call, including calls
after consumed input and inside predicates/wrappers, rather than reusing the
left-edge graph. It initializes closed structure optimistically, then propagates
unknownness downward in knowledge and potential actions upward to a fixed point.
Both flags are monotone, with at most two changes per rule. Unknown/action facts
therefore reach every member and caller of contaminated cycles. Closed pure
cycles can remain known and action-free; this does not prove termination or
permit recursive lowering. A separate acyclicity proof remains necessary for H03.

The method and graph construction are cold, nothrow operations using selective
druntime GC. No hot parser code, arena ownership or cleanup protocol changes.
No parsing speed improvement is claimed.

## Verification

Test-first commit: `8e0bfa7`; the initial integration fixture fails because the
new fields are absent. `scripts/rule-effects-check.sh` runs DMD/LDC with warnings
as errors, druntime only, explicit GC-retention stress, a 45-second alarm,
60-second outer timeout and 4 GiB address-space ceiling. It verifies typed facts,
parses the serialized JSON, checks every expected flag pair, and compares complete
compiler transcripts. The pure island must still be memoized and blocked from
scalar lowering, proving that reporting did not adopt a new policy.

Source-adjacent units cover unknown and explicit-action propagation, repeated
expression nodes, reverse-ordered multi-round dependency chains, contaminated and
action-bearing cycles, closed pure cycles, parameter overrides, action operands,
parameter-name scope and template-name shadowing. H01's full 72-cohort oracle
also passes on both compilers: every pre-H01 generated-source hash remains
unchanged, and repeated JSON/text and forced-GC retention checks pass.

DMD/LDC differential checks and hot-path -vgc checks pass. Repository-wide DMD
line/GDC source-branch coverage must exceed 90% in every executable source module;
final source hashes and summaries are in verification/. Normal validation now
includes the H02 integration fixture alongside H01.

Both `scripts/rule-effects-memory-check.sh` and the existing H01 memory helper
pass. ASan/LSan uses native-stack GC compatibility settings and forced collection;
Memcheck covers the full workload with collection disabled and no suppressions.
See [H01's documented configuration limits](../H01/README.md#memory-check-configuration-and-limits).
The H02 Memcheck log reports zero errors, no definite/indirect leaks, 32 possibly
lost bytes and 216 reachable bytes in druntime. These are not claimed as zero
bytes in every leak category. Memory runners use 4 GiB physical-memory scopes,
60-second ASan and 120-second Memcheck outer timeouts, plus the internal alarm.

Final changed-module coverage: analysis 99.69% lines / 93.52% branches; grammar
98.97% lines / 93.02% branches. Optimized LDC (-O3, assertions retained) returns
the same complete transcript as native DMD/LDC and the memory-check builds.
