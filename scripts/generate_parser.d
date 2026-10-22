module generate_parser;
import npegged.grammar;
import npegged.definition;
import npegged.io : File;

int main(string[] args) nothrow {
    string destination = args.length > 1 ? args[1] : "src/npegged/parser";
    enum generated = generate!(Memoization.yes, void, ParserBackend.combinators)(PEGGEDgrammar, "npegged.parser");
    static assert(generated.status == Status.ok);
    enum tests = q"TESTS
@nogc nothrow unittest {
    ParseContext context;
    enum definition = "Tiny: A <- 'a' eoi";
    auto valid = Pegged(context, definition);
    assert(valid.successful && valid.end == definition.length);
    auto invalid = Pegged(context, "Tiny: A <- (");
    assert(!invalid.successful);
    auto space = Pegged.Space(context, "\t\n");
    assert(space.successful && space.end == 2);
}
TESTS";
    enum source = "// Generated from Pegged-derived npegged grammar. Boost 1.0.\n" ~ generated.source ~ tests;
    auto file = File.open(destination ~ ".d", true);
    return file.write(source) == Status.ok ? 0 : 1;
}
