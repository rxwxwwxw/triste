# P1: localize action barriers (pure islands)

Already implemented behind `-d-version=NPeggedPureIslands` (analysis `RuleEffect`, `grammar.d` `islands`). Verified in the
current tree: for a mixed grammar the eligibility report changes `directFallback` of pure rules from `grammar-action` to
`root-combinator` (they become DFA scanners / direct candidates), actionful rules still fall back.

Measured (LDC -O3, `mixed.txt`; best of 5, identical output sinks): pure header/body/footer grammar in recognition and
compact-record modes, and JSON under an actionful root in record mode: all within 1% of the default build. Recognition of an
actionful grammar uses the tree fallback regardless. No code change in this milestone; the flag stays off by default (consistent
with the earlier D01/D02 decisions). Adverse/negative case: the actionful rules themselves, which never take the island path.
