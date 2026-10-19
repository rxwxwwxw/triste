# BITES analysis (report-only)

Reference: Redziejowski, "BITES Instead of FIRST for Parsing Expression Grammar", Fundamenta Informaticae 109(3), 2011.
Nothing here changes generated code; FIRST machinery is untouched.

## B1: input languages (`src/npegged/language.d`)

`InputLanguage` = set of whole input strings (EOF included), stored as a complete byte DFA. Union and intersection are exact
product constructions, complement flips acceptance, emptiness is decided by reachability (with a shortest witness).
Constructors: `empty`, `universal`, `endOfInput` (only ""), `prefix("abc")` (= L Σ*), `bytePrefix(class)`.

Proof contract: `provenEmpty`/`provenNonempty` are exact; `unknown` appears only after a budget (`Budget.maxStates`, default 512
product states) is exceeded and is never read as empty. Over-approximations (BITES, NULL) map `unknown` to `universal`;
under-approximations (SUCC) map it to `empty`. Zero-width terminals (`eps`, `eoi`) never become `prefix(...)`.
Trusted facts: byte-oriented terminals, pure (action-free) expressions. Excluded: actions, left recursion, parameters/dynamic
nodes — treated as unknown.
