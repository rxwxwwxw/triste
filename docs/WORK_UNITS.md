# Work units (the `stepLimit` contract)

`ParseContext.stepLimit` bounds the work of one parse. Decision D2 (approved by the maintainer on 2026-10-20) replaced the
old per-node model by the coarser model below. Both backends (`combinators`, `direct`, `ll1`) implement exactly the same
model; the A4 differential gate checks every step limit densely.

## Model v2

One work unit is charged for each of:

| event | units |
|---|---|
| rule invocation (memoized or not, any output mode) | 1 |
| repetition attempt (`zeroOrMore`, `oneOrMore`, `option`: every iteration attempt, including the one that fails) | 1 |
| DFA scanner call | `examined - pos + 1` (unchanged) |
| tagged region in records mode (O4) | `examined - pos + 1`, as the scanner above; the rules inside the region charge nothing, and the scan is attempted only when the budget shows the whole input, otherwise the region is walked rule by rule |
| tree projection of a record (`projectRecords`) and failure-chain walks in tree mode | 1 each (unchanged) |

Terminals (`literal`, `charClass`, `charRange`, `any`, case-insensitive literals), sequences, ordered and predictive choices
and lookaheads charge nothing. They only observe the status: once a limit has fired (`status != ok`) they fail
immediately, exactly like before; only the point at which the limit fires moves.

Why this still bounds run time: any unbounded evaluation has to go through a rule call, a repetition attempt or a scanner,
and each of those pays a unit. Between two charges the parser executes a bounded amount of straight-line code (its size is
the grammar's, not the input's).

What changed observably: the step count at which `Status.resourceLimit` fires, and the `end`/`failEnd` reported by a parse
that exhausts the limit. Results of parses that stay under the limit are unchanged. Typical inputs now need fewer units, so
callers with tuned limits can lower them. `tests/differential.d` sweeps step limits 0..80 over every fixture on both
backends.

The old model charged one unit per evaluated node (the "v1" numbers recorded in `performance/milestones/` up to and including Q2).
