/** End-to-end tests for the Pegged-derived conversion (Boost 1.0).
    Run only through scripts/build.sh, which applies a mandatory process timeout. */
module tests.runner;
import npegged.grammar;
import npegged.records : RecordBuffer;
import npegged.parser;
import npegged.definition;
import npegged.formatting;
import npegged.tohtml;
import npegged.io;
import npegged.examples.json;
import npegged.examples.c;
static import npegged.examples.xml2;
import npegged.examples.xml;
import npegged.examples.csv;
import npegged.examples.numbers;
import npegged.examples.strings;
import npegged.examples.composition;
import npegged.examples.parameterized;
import npegged.examples.oberon2;
import npegged.examples.dgrammar;
import npegged.examples.markdown;
import npegged.examples.PEG;
import npegged.examples.python;
import npegged.examples.pattern;
import npegged.examples.constraints;
import core.memory : GC;
import core.sys.posix.unistd : alarm;

extern (C) __gshared string[] rt_options = ["gcopt=disable:1 parallel:0 cleanup:none"];

version (Posix) {
    import core.sys.posix.pthread : pthread_self, pthread_t;

    extern (C) int pthread_detach(pthread_t th) nothrow @nogc {
        return 0;
    }
}

mixin(grammar(`
Cycle:
    Start <- A eoi
    A <- B 'a' / 'a'
    B <- A 'b' / 'a'
`));
mixin(grammar(`
Hidden:
    A <- B? A 'a' / 'a'
    B <- 'b'
`));
mixin(grammar(`
Mutual:
    A <- L eoi
    L <- P '.x' / 'x'
    P <- P '(n)' / L
`));
mixin(grammar(`
Parameters(Token = identifier):
    Start <- Entry(Token) eoi
    Entry(T, Separator = ',') < T (:Separator T)*
`));
mixin(grammar!(Memoization.no)("Uncached: Start <- ('a' / 'b')+ eoi"));

mixin(grammar(`ParameterIdentity: Start <- Pick('a') / Pick('b') Pick(Token) <- Token`));

@nogc nothrow private void leftRecursion() {
    ParseContext context;
    auto direct = Cycle(context, "ababa");
    assert(direct.successful && direct.end == 5);
    auto hidden = Hidden(context, "aaa");
    assert(hidden.successful && hidden.end == 3);
    auto mutual = Mutual(context, "x(n).x(n).x");
    assert(mutual.successful && mutual.end == 11);
    auto repeated = Cycle(context, "a");
    assert(repeated.successful && repeated.end == 1);
    auto uncached = Uncached(context, "abba");
    assert(uncached.successful && uncached.end == 4);
    auto identity = ParameterIdentity(context, "b");
    assert(identity.successful && identity.matches == ["b"]);
    auto params = Parameters!()(context, "a,b,c");
    assert(params.successful && params.matches == ["a", "b", "c"]);
}

private void traced(string rule, size_t pos, bool success, void* user) @nogc nothrow {
    ++*cast(size_t*)user;
}

@nogc nothrow private void ownershipAndLimits() {
    ParseContext context;
    char[3] input = ['1', '2', '3'];
    auto owned = Numbers(context, cast(string)input[]);
    input[] = 'x';
    assert(owned.input == "123" && owned.matches == ["123"]);
    auto second = Numbers(context, "456");
    assert(second.matches == ["456"]);
    assert(owned.matches == ["123"]);
    context.memoryLimit = 1;
    auto memory = Numbers(context, "123");
    assert(memory.status == Status.resourceLimit);
    context = ParseContext.init;
    context.stepLimit = 1;
    auto steps = Numbers(context, "123");
    assert(steps.status == Status.resourceLimit);
    context = ParseContext.init;
    context.depthLimit = 1;
    auto depth = Cycle(context, "ababa");
    assert(depth.status == Status.resourceLimit);
    size_t calls;
    context = ParseContext.init;
    context.trace = &traced;
    context.userData = &calls;
    auto trace = Numbers(context, "42");
    assert(trace.successful && calls > 0);
}

@nogc nothrow private void workflows() {
    ParseContext context;
    auto json = JSON(context, `{"data":[1,2,"<&>"]}`);
    assert(json.successful);
    auto text = json.toString;
    assert(text.status == Status.ok && text.data.length);
    auto html = toHTML(json.tree);
    assert(html.status == Status.ok && html.data.length);
    auto xml = XML(context, "<a><b>text</b></a>");
    assert(xml.successful);
    auto invalid = XML(context, "<a><b></a></b>");
    assert(!invalid.successful);
    auto next = XML(context, "<c></c>");
    assert(next.successful);
    auto csv = CSV(context, "a,b\nc,d\n");
    assert(csv.successful && csv.end == 8);
    auto grammar = Pegged(context, PEGGEDgrammar);
    assert(grammar.successful && grammar.end == PEGGEDgrammar.length);
    auto peg = PEG(context, "A <- 'a'\n");
    assert(peg.successful);
    auto markdown = Markdown(context, "Hello world\n\n");
    assert(markdown.successful);
    auto c = C(context, "int value;");
    assert(c.successful);
    auto d = D(context, "module example;\n");
    assert(d.successful);
    version (Posix) {
        assert(pthread_detach(pthread_self()) == 0);
    }
}

enum actionFixture = q"GRAM
Actions(Token = 'a'):
    Start <- Item(Token) :eoi
    Item(T = 'b') <{p => p} (T / 'A'i / [a-z])
        {p => foo(p, r"raw", `raw`, "quoted\"value", q{token}, q"[[]]", q"{{}}", q"((x))", q"<<x>>")}
    Commented <- 'x'{p => { // line comment
        /* block comment */ /+ nested /+ inner +/ outer +/
        return p;
    }}
GRAM";

@nogc nothrow private void recognition() {
    ParseContext context;
    foreach (input; ["a", "ababa", "x"]) {
        auto tree = Cycle(context, input);
        auto checked = check!(Cycle.opCall)(context, input);
        assert(checked.status == tree.status && checked.successful == tree.successful);
        assert(checked.end == tree.end && checked.failEnd == tree.failEnd);
    }
    foreach (input; ["<a>text</a>", "<a>text</b>"]) {
        auto tree = XML(context, input);
        auto checked = check!(XML.opCall)(context, input);
        assert(checked.status == tree.status && checked.successful == tree.successful);
        assert(checked.end == tree.end);
    }
    auto first = check!(Numbers.opCall)(context, "123");
    auto second = Numbers(context, "456");
    assert(first.successful && second.matches == ["456"]);
    context.stepLimit = 1;
    assert(check!(Cycle.opCall)(context, "ababa").status == Status.resourceLimit);
}

private uint everyRule(string name) @nogc nothrow pure {
    return 0;
}

int main() nothrow {
    alarm(180);
    scope (exit)
        alarm(0);
    foreach (definition; [
        Cgrammar, Dgrammar, MarkdownGrammar, Oberon2Grammar, PEGGgrammar, PEGGEDgrammar,
        pythonGrammar, parameterizedExamples, npegged.examples.xml2.XMLgrammar, actionFixture
    ]) {
        auto generated = generate(definition);
        assert(generated.status == Status.ok && generated.source.length);
        ParseContext context;
        auto parsed = Pegged(context, definition);
        assert(parsed.successful && parsed.end == definition.length);
        auto checked = check!(Pegged.opCall)(context, definition);
        assert(checked.successful && checked.end == parsed.end);
        auto compact = parseRecords!(Pegged.opCall, everyRule)(context, definition);
        assert(compact.successful && compact.end == parsed.end && compact.nodes.length > 0);
        foreach (i, node; compact.nodes)
            assert(node.parent == size_t.max || node.parent < i);
        Arena recordWork, recordStorage;
        RecordBuffer records;
        records.arena = &recordStorage;
        records.selector = &everyRule;
        State!(true, 2) alternateRecords;
        alternateRecords.arena = &recordWork;
        alternateRecords.input = definition;
        alternateRecords.context = context;
        alternateRecords.attachRecords(records);
        auto recorded = Pegged(alternateRecords, 0);
        assert(recorded.successful && recorded.end == parsed.end);
        assert(records.nodes == compact.nodes);
        Arena checkedArena;
        State!(true, true) checkedCompilerStorage;
        checkedCompilerStorage.arena = &checkedArena;
        checkedCompilerStorage.input = definition;
        auto checkedAlternate = Pegged(checkedCompilerStorage, 0);
        assert(checkedAlternate.successful && checkedAlternate.end == parsed.end);
        static assert(typeof(checkedAlternate).sizeof < ParseTree.sizeof);
        Arena alternateArena;
        State!true compileTimeStorage;
        compileTimeStorage.arena = &alternateArena;
        compileTimeStorage.input = definition;
        auto alternate = Pegged(compileTimeStorage, 0);
        assert(alternate.successful && alternate.matches == parsed.matches);
    }
    // Unit tests run before main. The parser itself must work with collections disabled.
    GC.disable();
    leftRecursion();
    ownershipAndLimits();
    recognition();
    workflows();
    GC.enable();
    return 0;
}
