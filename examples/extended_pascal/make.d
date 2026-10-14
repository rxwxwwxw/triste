// Derived from Pegged examples (Boost 1.0).
/**
 * Recreate the EP parser from the grammar.
 */

import npegged.grammar;
import epgrammar;

int main(string[] args) nothrow {
    auto header = `
PT failOnWordSymbol(PT)(PT p) @nogc nothrow
{
    
    // 6.1.2
    if (caseEqual(p.matches[0], "AND") ||
        caseEqual(p.matches[0], "AND_THEN") ||
        caseEqual(p.matches[0], "ARRAY") ||
        caseEqual(p.matches[0], "BEGIN") ||
        caseEqual(p.matches[0], "BINDABLE") ||
        caseEqual(p.matches[0], "CASE") ||
        caseEqual(p.matches[0], "CONST") ||
        caseEqual(p.matches[0], "DIV") ||
        caseEqual(p.matches[0], "DO") ||
        caseEqual(p.matches[0], "DOWNTO") ||
        caseEqual(p.matches[0], "ELSE") ||
        caseEqual(p.matches[0], "END") ||
        caseEqual(p.matches[0], "EXPORT") ||
        caseEqual(p.matches[0], "FILE") ||
        caseEqual(p.matches[0], "FOR") ||
        caseEqual(p.matches[0], "FUNCTION") ||
        caseEqual(p.matches[0], "GOTO") ||
        caseEqual(p.matches[0], "IF") ||
        caseEqual(p.matches[0], "IMPORT") ||
        caseEqual(p.matches[0], "IN") ||
        caseEqual(p.matches[0], "LABEL") ||
        caseEqual(p.matches[0], "MOD") ||
        caseEqual(p.matches[0], "MODULE") ||
        caseEqual(p.matches[0], "NIL") ||
        caseEqual(p.matches[0], "NOT") ||
        caseEqual(p.matches[0], "OF") ||
        caseEqual(p.matches[0], "ONLY") ||
        caseEqual(p.matches[0], "OR") ||
        caseEqual(p.matches[0], "OR_ELSE") ||
        caseEqual(p.matches[0], "OTHERWISE") ||
        caseEqual(p.matches[0], "PACKED") ||
        caseEqual(p.matches[0], "POW") ||
        caseEqual(p.matches[0], "PROCEDURE") ||
        caseEqual(p.matches[0], "PROGRAM") ||
        caseEqual(p.matches[0], "PROTECTED") ||
        caseEqual(p.matches[0], "QUALIFIED") ||
        caseEqual(p.matches[0], "RECORD") ||
        caseEqual(p.matches[0], "REPEAT") ||
        caseEqual(p.matches[0], "RESTRICTED") ||
        caseEqual(p.matches[0], "SET") ||
        caseEqual(p.matches[0], "THEN") ||
        caseEqual(p.matches[0], "TO") ||
        caseEqual(p.matches[0], "TYPE") ||
        caseEqual(p.matches[0], "UNTIL") ||
        caseEqual(p.matches[0], "VALUE") ||
        caseEqual(p.matches[0], "VAR") ||
        caseEqual(p.matches[0], "WHILE") ||
        caseEqual(p.matches[0], "WITH") ||
    // Prospero extensions:
        caseEqual(p.matches[0], "ABSTRACT") ||
        caseEqual(p.matches[0], "CLASS") ||
        caseEqual(p.matches[0], "CONSTRUCTOR") ||
        caseEqual(p.matches[0], "DESTRUCTOR") ||
        caseEqual(p.matches[0], "EXCEPT") ||
        caseEqual(p.matches[0], "IS") ||
        caseEqual(p.matches[0], "PROPERTY") ||
        caseEqual(p.matches[0], "REM") ||
        caseEqual(p.matches[0], "SHL") ||
        caseEqual(p.matches[0], "SHR") ||
        caseEqual(p.matches[0], "TRY") ||
        caseEqual(p.matches[0], "VIEW") ||
        caseEqual(p.matches[0], "XOR"))
    {
        p.successful = false;
    }
    return p;
}
`;
    const destination = args.length > 1 ? args[1] : "build/epparser";
    return asModule!()("epparser", destination, EPgrammar, header) == Status.ok ? 0 : 1;
}
