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
import npegged.examples.xml;
import npegged.examples.csv;
import npegged.examples.numbers;
import npegged.examples.parameterized;
import npegged.examples.PEG;
import core.memory : GC;
import core.sys.posix.unistd : alarm;

extern (C) string npegged_Cgrammar() @nogc nothrow pure;
extern (C) bool npegged_checkC() @nogc nothrow;
extern (C) string npegged_Dgrammar() @nogc nothrow pure;
extern (C) bool npegged_checkD() @nogc nothrow;
extern (C) string npegged_MarkdownGrammar() @nogc nothrow pure;
extern (C) bool npegged_checkMarkdown() @nogc nothrow;
extern (C) string npegged_Oberon2Grammar() @nogc nothrow pure;
extern (C) string npegged_pythonGrammar() @nogc nothrow pure;
extern (C) string npegged_XMLgrammar() @nogc nothrow pure;

extern (C) __gshared string[] rt_options = ["gcopt=disable:1 parallel:0 cleanup:none"];

version (Posix) {
    import core.sys.posix.pthread : pthread_self, pthread_t;

    extern (C) int pthread_detach(pthread_t th) nothrow @nogc {
        return 0;
    }
}

// The direct backend must preserve recognition and resource boundaries while
// retaining the existing tree/record paths. The runner has a process deadline.
private enum directRules = `:
    Root <- !'z' Item+ eoi
    Item <- '(' RootPart ')' / 'a' Tail? / 'b' / eps 'x'
    RootPart <- (!')' Item)* &')'
    Tail <- 'a' / 'b'
`;
mixin(grammar!(Memoization.selective, void, ParserBackend.direct)("DirectControl" ~ directRules));
mixin(grammar!(Memoization.selective)("ReferenceControl" ~ directRules));

@nogc nothrow unittest {
    enum ctTree = DirectControl("ab");
    static assert(ctTree.successful && ctTree.end == 2);
    enum ctRecognition = () {
        State!(true, 1) state;
        state.input = "ab";
        return state.finish(DirectControl.opCall(state, 0));
    }();
    static assert(ctRecognition.successful && ctRecognition.end == 2);

    char[4] bytes;
    enum alphabet = "ab()xz";
    size_t combinations = 1;
    foreach (length; 0 .. bytes.length + 1) {
        foreach (encoded; 0 .. combinations) {
            size_t value = encoded;
            foreach (ref c; bytes[0 .. length]) {
                c = alphabet[value % alphabet.length];
                value /= alphabet.length;
            }
            const input = cast(string)bytes[0 .. length];
            foreach (budget; 0 .. 48) {
                ParseContext context;
                context.stepLimit = budget;
                auto actual = check!(DirectControl.opCall)(context, input);
                auto expected = check!(ReferenceControl.opCall)(context, input);
                assert(actual.status == expected.status);
                assert(actual.successful == expected.successful);
                assert(actual.end == expected.end && actual.failEnd == expected.failEnd);
            }
        }
        combinations *= alphabet.length;
    }
    foreach (input; ["", "a", "abab", "(a(b))", "((a)", "((((a))))", "ax", "()"])
        foreach (limit; 0 .. 12) {
            ParseContext context;
            context.depthLimit = limit;
            auto actual = check!(DirectControl.opCall)(context, input);
            auto expected = check!(ReferenceControl.opCall)(context, input);
            assert(actual.status == expected.status && actual.end == expected.end);
            assert(actual.failEnd == expected.failEnd);
        }
}

private uint allDirectRecords(string name) @nogc nothrow pure {
    return 1;
}

@nogc nothrow unittest {
    static void observe(string name, size_t pos, bool accepted, void* userData) @nogc nothrow {
        auto counters = cast(size_t*)userData;
        ++counters[0];
        counters[1] = counters[1] * 33 + pos * 2 + accepted;
        size_t offset;
        while (offset < name.length && name[offset] != '.')
            ++offset;
        foreach (c; name[offset .. $])
            counters[1] = counters[1] * 33 + cast(ubyte)c;
    }

    foreach (input; ["", "a", "abab", "(a(b))", "((a)", "x", "z"]) {
        ParseContext context;
        auto directTree = DirectControl(context, input);
        auto referenceTree = ReferenceControl(context, input);
        assert(directTree.status == referenceTree.status);
        assert(directTree.matches == referenceTree.matches);
        auto directRecords = parseRecords!(DirectControl.opCall, allDirectRecords)(context, input);
        auto referenceRecords = parseRecords!(ReferenceControl.opCall, allDirectRecords)(context, input);
        assert(directRecords.status == referenceRecords.status);
        assert(directRecords.end == referenceRecords.end && directRecords.failEnd == referenceRecords
                .failEnd);
        assert(directRecords.nodes == referenceRecords.nodes);
        size_t[2] actual, expected;
        context.trace = &observe;
        context.userData = actual.ptr;
        auto directCheck = check!(DirectControl.opCall)(context, input);
        context.userData = expected.ptr;
        auto referenceCheck = check!(ReferenceControl.opCall)(context, input);
        assert(actual == expected);
        assert(directCheck.status == referenceCheck.status && directCheck.end == referenceCheck.end);
        assert(directCheck.failEnd == referenceCheck.failEnd);
    }
}

@nogc nothrow unittest {
    foreach (input; ["", "a", "(a(b))", "((a)", "ax", "z"])
        foreach (budget; 0 .. 80) {
            ParseContext context;
            context.stepLimit = budget;
            auto actual = parseRecords!(DirectControl.opCall, allDirectRecords, false)(context, input);
            auto expected = parseRecords!(ReferenceControl.opCall, allDirectRecords, false)(context, input);
            assert(actual.status == expected.status && actual.successful == expected.successful);
            assert(actual.end == expected.end && actual.failEnd == expected.failEnd);
            assert(actual.nodes == expected.nodes);
        }
    foreach (input; ["", "a", "(a(b))", "((a)"])
        foreach (limit; [0, 1024, 1047, 2048, 4096]) {
            ParseContext context;
            auto actual = parseRecords!(DirectControl.opCall, allDirectRecords, false)(context, input,
                    limit);
            auto expected = parseRecords!(ReferenceControl.opCall, allDirectRecords, false)(context, input,
                    limit);
            assert(actual.status == expected.status && actual.nodes == expected.nodes);
            assert(actual.end == expected.end && actual.failEnd == expected.failEnd);
        }
}

private enum directLeftRules = `:
    Root <- Sum eoi
    Sum <- Sum '+' Number / Number
    Number <- [0-9]+
`;
mixin(grammar!(Memoization.selective, void, ParserBackend.direct)("DirectLeft" ~ directLeftRules));
mixin(grammar!(Memoization.selective)("ReferenceLeft" ~ directLeftRules));

@nogc nothrow unittest {
    foreach (input; ["", "1", "1+2+3", "1+", "1+x"])
        foreach (budget; 0 .. 100) {
            ParseContext context;
            context.stepLimit = budget;
            auto actual = check!(DirectLeft.opCall)(context, input);
            auto expected = check!(ReferenceLeft.opCall)(context, input);
            assert(actual.status == expected.status && actual.successful == expected.successful);
            assert(actual.end == expected.end && actual.failEnd == expected.failEnd);
        }
}

private enum directNullableRules = `:
    Root <- Item eoi
    Item <- 'a' Item 'x' / 'b'?
`;
mixin(grammar!(Memoization.selective, void, ParserBackend.direct)("DirectNullable" ~ directNullableRules));
mixin(grammar!(Memoization.selective)("ReferenceNullable" ~ directNullableRules));

@nogc nothrow unittest {
    foreach (input; ["", "a", "ax", "b", "abx", "aabxx", "aabx", "ab", "x"])
        foreach (budget; 0 .. 64) {
            ParseContext context;
            context.stepLimit = budget;
            auto actual = check!(DirectNullable.opCall)(context, input);
            auto expected = check!(ReferenceNullable.opCall)(context, input);
            assert(actual.status == expected.status && actual.successful == expected.successful);
            assert(actual.end == expected.end && actual.failEnd == expected.failEnd);
        }
}

private enum nativeRules = `:
    Root <- Item* eoi
    Item <- '(' RootPart ')' / 'abé' / [a-z] '.' / ![()z] .
    RootPart <- Item*
`;
mixin(grammar!(Memoization.selective, void, ParserBackend.direct)("DirectNative" ~ nativeRules));
mixin(grammar!(Memoization.selective)("ReferenceNative" ~ nativeRules));

@nogc nothrow unittest {
    foreach (input; [
        "", "abé", "ab", "abx", "a.", "aé", "(abé)", "(ab", "(", ")", "z", "é", "\xff"
    ])
        foreach (budget; 0 .. 72) {
            ParseContext context;
            context.stepLimit = budget;
            auto actual = check!(DirectNative.opCall)(context, input);
            auto expected = check!(ReferenceNative.opCall)(context, input);
            assert(actual.status == expected.status && actual.successful == expected.successful);
            assert(actual.end == expected.end && actual.failEnd == expected.failEnd);
            auto actualItem = check!(DirectNative.Item)(context, input);
            auto expectedItem = check!(ReferenceNative.Item)(context, input);
            assert(actualItem.status == expectedItem.status && actualItem.successful == expectedItem
                    .successful);
            assert(actualItem.end == expectedItem.end && actualItem.failEnd == expectedItem.failEnd);
        }
    char[4096] bytes;
    bytes[] = 'a';
    foreach (budget; [0, 1, 10, 100, 200]) {
        ParseContext context;
        context.stepLimit = budget;
        auto actual = check!(DirectControl.opCall)(context, cast(string)bytes[]);
        auto expected = check!(ReferenceControl.opCall)(context, cast(string)bytes[]);
        assert(actual.status == Status.resourceLimit && actual.status == expected.status);
        assert(actual.end == expected.end && actual.failEnd == expected.failEnd);
    }
}

private State!(CT, Check).Node enableDirectTrace(bool CT, int Check = 0)(ref State!(CT, Check) state, size_t pos) nothrow {
    state.context.trace = &traced;
    return state.node(pos, pos);
}

@nogc nothrow unittest {
    State!(false, 1) state;
    auto node = enableDirectTrace(state, 0);
    assert(node.successful && state.context.trace == &traced);
}

private enum opaqueRules = ": Root <- enableDirectTrace Leaf eoi Leaf <- 'a'";
mixin(grammar!(Memoization.no, void, ParserBackend.direct)("DirectOpaque" ~ opaqueRules));
mixin(grammar!(Memoization.no)("ReferenceOpaque" ~ opaqueRules));

@nogc nothrow unittest {
    ParseContext context;
    size_t actualCalls, expectedCalls;
    context.userData = &actualCalls;
    auto actual = check!(DirectOpaque.opCall)(context, "a");
    context.userData = &expectedCalls;
    auto expected = check!(ReferenceOpaque.opCall)(context, "a");
    assert(actual.successful && expected.successful && actualCalls == expectedCalls && actualCalls == 2);
}

private State!(CT, Check).Node directResourceSeed(bool CT, int Check = 0)(ref State!(CT, Check) state,
        size_t pos) nothrow {
    state.status = Status.resourceLimit;
    auto node = state.node(pos, pos);
    node.successful = true;
    return node;
}

@nogc nothrow unittest {
    State!(false, 1) state;
    assert(directResourceSeed(state, 0).successful && state.status == Status.resourceLimit);
}

private enum resourceSeedRules = ": Root <- 'a' Parent 'b' eoi Parent <- 'x' directResourceSeed";
mixin(grammar!(Memoization.no, void, ParserBackend.direct)("DirectResourceSeed" ~ resourceSeedRules));
mixin(grammar!(Memoization.no)("ReferenceResourceSeed" ~ resourceSeedRules));

@nogc nothrow unittest {
    ParseContext context;
    auto actual = check!(DirectResourceSeed.opCall)(context, "ax");
    auto expected = check!(ReferenceResourceSeed.opCall)(context, "ax");
    assert(actual.status == Status.resourceLimit && actual.status == expected.status);
    assert(actual.end == 0 && actual.end == expected.end && actual.failEnd == expected.failEnd);
}

private enum batchRules = `:
    Root <- 'a' Sp 'b' eoi
    Sp <: [ \t\r\n]* ('#' (!'\n' .)* [ \t\r\n]*)*
    Empty <- (eps+ eps+ eps+)
    Suffix <- (!('x' 'y'))?
`;
mixin(grammar!(Memoization.selective, void, ParserBackend.direct)("DirectBatch" ~ batchRules));
mixin(grammar!(Memoization.selective)("ReferenceBatch" ~ batchRules));

@nogc nothrow unittest {
    char[4] bytes = ['x', 'x', 'y', 'z'];
    foreach (first; 0 .. 257) {
        bytes[0] = cast(char)first;
        const input = first == 256 ? "" : cast(string)bytes[];
        foreach (budget; 0 .. 40) {
            Arena owner;
            State!(false, 1) actual, expected;
            actual.arena = expected.arena = &owner;
            actual.input = expected.input = input;
            actual.context.stepLimit = expected.context.stepLimit = budget;
            auto actualNode = actual.finish(DirectBatch.Sp(actual, 0));
            auto expectedNode = expected.finish(ReferenceBatch.Sp(expected, 0));
            assert(actual.status == expected.status && actual.steps == expected.steps);
            assert(actualNode.successful == expectedNode.successful && actualNode.end == expectedNode
                    .end);
            assert(actualNode.failEnd == expectedNode.failEnd);
            assert(actual.checkpointFailure().present == expected.checkpointFailure().present);
            assert(owner.allocationCalls == 0);
        }
    }
    foreach (input; ["", "x", "xy", "xz", "a b", "a#comment\nb", "ab"])
        foreach (budget; 0 .. 40) {
            ParseContext context;
            context.stepLimit = budget;
            auto actual = check!(DirectBatch.Root)(context, input);
            auto expected = check!(ReferenceBatch.Root)(context, input);
            assert(actual.status == expected.status && actual.end == expected.end && actual.failEnd == expected
                    .failEnd);
            auto emptyActual = check!(DirectBatch.Empty)(context, input);
            auto emptyExpected = check!(ReferenceBatch.Empty)(context, input);
            assert(emptyActual.status == emptyExpected.status && emptyActual.end == emptyExpected.end);
            auto suffixActual = check!(DirectBatch.Suffix)(context, input);
            auto suffixExpected = check!(ReferenceBatch.Suffix)(context, input);
            assert(suffixActual.status == suffixExpected.status && suffixActual.end == suffixExpected
                    .end);
            assert(suffixActual.failEnd == suffixExpected.failEnd);
            auto recordsActual = parseRecords!(DirectBatch.Root, allDirectRecords, false)(context, input);
            auto recordsExpected = parseRecords!(ReferenceBatch.Root, allDirectRecords, false)(context,
                    input);
            assert(recordsActual.status == recordsExpected.status && recordsActual.nodes == recordsExpected
                    .nodes);
            assert(recordsActual.end == recordsExpected.end && recordsActual.failEnd == recordsExpected
                    .failEnd);
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

mixin(grammar!(Memoization.no)(`
Factored:
    Start <- (Token '.' Token / Token ':' Token / Token) eoi
    Token <- [0-9]+
`));

@nogc nothrow private void factoredChoices() {
    alias original = defined!(and!(or!(and!(Factored.Token, literal!".", Factored.Token),
            and!(Factored.Token, literal!":", Factored.Token), Factored.Token), eoi), "Factored.Start");
    ParseContext context;
    foreach (input; ["123", "123.456", "123:456"]) {
        auto tree = Factored(context, input);
        auto baseline = parse!original(context, input);
        assert(tree.successful && tree.end == input.length);
        assert(tree.matches == baseline.matches && tree.children.length == baseline.children.length);
        foreach (i, child; tree.children) {
            assert(child.name == baseline.children[i].name);
            assert(child.begin == baseline.children[i].begin && child.end == baseline.children[i].end);
        }
        auto checked = check!(Factored.opCall)(context, input);
        assert(checked.successful && checked.end == input.length);
    }
    foreach (input; ["", "123.", "123:", "123x"]) {
        auto optimized = Factored(context, input);
        auto baseline = parse!original(context, input);
        assert(!optimized.successful && optimized.failEnd == baseline.failEnd);
    }
    size_t calls;
    context.trace = &traced;
    context.userData = &calls;
    assert(Factored(context, "123").successful && calls == 4);
}

mixin(grammar!(Memoization.no)(`
RegularTokens:
    Number <- ~([0-9]+ ('.' [0-9]+)? ([eE] [+-]? [0-9]+)?)
    Identifier <- ~([a-zA-Z_] [a-zA-Z0-9_]*)
    Whitespace <- ~[ \t\r\n]+
    Comment <- ~('#' (!'\n' .)* '\n')
    String <- ~('"' (!["\\] .)* '"')
    Bytes <- 'é\x80'
    Unsafe <- 'a'* 'a'
    Referenced <- Identifier ':' Identifier
    Anchored <- Number eoi
    Nullable <- 'a' / 'b'?
    Committed <- ('a' / 'ab') 'c'
    EscapeBody <- ('\\' . / (!'"' .))*
    Escaped <- ~('"' ('\\' . / (!'"' .))* '"')
    EscapeSubsetBody <- ([\\%] . / [a\\])*
    GroupedEscapeBody <- ('\\' . / (!'"' .)+)*
    DisjointEscapeBody <- ('\\' . / 'a')*
    DisjointGroupedEscapeBody <- ('\\' . / 'a'+)*
    Class <- '[' '^'? ('\\' . / (!']' .))* ']'
    Absorbed <- 'a'? 'a'* 'b'
    RequiredTail <- 'a'? 'a'+ 'b'
    Maximal <- ('a' 'b'? / 'bc')*
    MaximalPlus <- ('a' 'b'? / 'bc')+
    Closed <- ('a' 'b'*) 'a'
    NestedRepeat <- ('a'+)*
    RepeatableTail <- ('a' 'a'* 'b'*)*
    CommittedTail <- ('a' 'b'* 'a'*)*
`));

private uint tokenSelection(string name) @nogc nothrow pure {
    return name == "RegularTokens.Identifier" ? 1 : name == "RegularTokens.Referenced" ? 2 : uint.max;
}

mixin(grammar(`GuardedParameter(any = 'z'): Start <- (!'q' .)+`));
mixin(grammar!(Memoization.no)(`
DelimitedQuotes:
    Whole <- Prefix ',' eoi
    Prefix <- '"' ('""' / (!'"' .)+)* '"'
`));

@nogc nothrow private void regularTokens() {
    static assert(!__traits(hasMember, GuardedParameter!(), "_dfa_Start"));
    ParseContext guardedContext;
    assert(check!(GuardedParameter!().opCall)(guardedContext, "zz").successful);
    assert(!check!(GuardedParameter!().opCall)(guardedContext, "aa").successful);
    static assert(RegularTokens._dfa_Number.valid);
    static assert(RegularTokens._dfa_Identifier.valid);
    static assert(RegularTokens._dfa_Whitespace.valid);
    static assert(RegularTokens._dfa_Comment.valid);
    static assert(RegularTokens._dfa_String.valid);
    static assert(RegularTokens._dfa_Referenced.valid);
    static assert(RegularTokens._dfa_Anchored.requireEnd);
    static foreach (rule; [
        "Number", "Identifier", "Whitespace", "Comment", "String", "Bytes", "Referenced",
        "Anchored", "Nullable", "Unsafe", "Committed"
    ]) {
        foreach (input; [
            "", "1", "12.3e-4!", "12.", "12e+", "a_b42", " \t\n!", "# comment\n!",
            "# unterminated", `"string"!`, `"unterminated`, `"back\slash"`, "é\x80!"
        ]) {
            ParseContext bounded, unlimited;
            unlimited.stepLimit = size_t.max;
            auto original = check!(__traits(getMember, RegularTokens, rule))(bounded, input);
            auto compiled = check!(__traits(getMember, RegularTokens, rule))(unlimited, input);
            auto tree = parse!(__traits(getMember, RegularTokens, rule))(bounded, input);
            assert(original.status == compiled.status && original.successful == compiled.successful);
            assert(original.end == compiled.end && original.failEnd == compiled.failEnd);
            assert(tree.status == compiled.status && tree.end == compiled.end && tree.failEnd == compiled
                    .failEnd);
        }
    }
    ParseContext context;
    size_t calls;
    context.trace = &traced;
    context.userData = &calls;
    assert(check!(RegularTokens.Referenced)(context, "a:b").successful && calls == 3);
    context.trace = null;
    context.depthLimit = 1;
    assert(check!(RegularTokens.Referenced)(context, "a:b").status == Status.resourceLimit);
    context.depthLimit = 2;
    assert(check!(RegularTokens.Referenced)(context, "a:b").successful);
    auto records = parseRecords!(RegularTokens.Referenced, tokenSelection)(context, "a:b");
    assert(records.successful && records.nodes.length == 3);
    assert(records.nodes[0].kind == 2 && records.nodes[1].kind == 1 && records.nodes[2].kind == 1);
    assert(records.nodes[1].begin == 0 && records.nodes[1].end == 1);
    assert(records.nodes[2].begin == 2 && records.nodes[2].end == 3);
    context = ParseContext.init;
    context.stepLimit = 3;
    assert(check!(RegularTokens.Number)(context, "123456789").status == Status.resourceLimit);
}

@nogc nothrow private void escapedTokens() {
    import npegged.meta : AliasSeq;

    alias body = zeroOrMore!(or!(and!(literal!"\\", any), and!(negLookahead!(literal!"\""), any)));
    alias token = fuse!(and!(literal!"\"", body, literal!"\""));
    enum prefixes = CharSetMask.fromChars('\\', '%');
    enum ordinary = CharSetMask.fromChars('a', '\\');
    alias subset = zeroOrMore!(or!(and!(charClass!prefixes, any), charClass!ordinary));
    alias grouped = zeroOrMore!(or!(and!(literal!"\\", any), oneOrMore!(and!(negLookahead!(literal!"\""),
            any))));
    alias disjoint = zeroOrMore!(or!(and!(literal!"\\", any), literal!"a"));
    alias disjointGrouped = zeroOrMore!(or!(and!(literal!"\\", any), oneOrMore!(literal!"a")));
    static assert(RegularTokens._dfa_Escaped.valid && RegularTokens._dfa_EscapeBody.valid);
    static assert(RegularTokens._dfa_EscapeBody.automaton.eofAccepting.length);
    char[6] bytes;
    enum alphabet = "a\"\\%";
    size_t combinations = 1;
    foreach (length; 0 .. bytes.length + 1) {
        foreach (encoded; 0 .. combinations) {
            size_t value = encoded;
            foreach (ref c; bytes[0 .. length]) {
                c = alphabet[value % alphabet.length];
                value /= alphabet.length;
            }
            const input = cast(string)bytes[0 .. length];
            ParseContext context;
            static foreach (i, original; AliasSeq!(body, token, subset, grouped, disjoint, disjointGrouped)) {
                {
                    auto baseline = check!original(context, input);
                    alias compiled = __traits(getMember, RegularTokens, [
                        "EscapeBody", "Escaped", "EscapeSubsetBody", "GroupedEscapeBody",
                        "DisjointEscapeBody", "DisjointGroupedEscapeBody"
                    ][i]);
                    auto result = check!compiled(context, input);
                    assert(baseline.status == result.status && baseline.successful == result
                            .successful);
                    assert(baseline.end == result.end && baseline.failEnd == result.failEnd);
                }
            }
        }
        combinations *= alphabet.length;
    }
}

@nogc nothrow private void optionalTokenPrefixes() {
    alias body = zeroOrMore!(or!(and!(literal!"\\", any), and!(negLookahead!(literal!"]"), any)));
    alias original = and!(literal!"[", option!(literal!"^"), body, literal!"]");
    static assert(RegularTokens._dfa_Class.valid && RegularTokens._dfa_Absorbed.valid);
    char[6] bytes;
    enum alphabet = "a^[]\\";
    size_t combinations = 1;
    foreach (length; 0 .. bytes.length + 1) {
        foreach (encoded; 0 .. combinations) {
            size_t value = encoded;
            foreach (ref c; bytes[0 .. length]) {
                c = alphabet[value % alphabet.length];
                value /= alphabet.length;
            }
            const input = cast(string)bytes[0 .. length];
            ParseContext context;
            auto baseline = check!original(context, input);
            auto result = check!(RegularTokens.Class)(context, input);
            assert(baseline.status == result.status && baseline.successful == result.successful);
            assert(baseline.end == result.end && baseline.failEnd == result.failEnd);
        }
        combinations *= alphabet.length;
    }
    ParseContext context;
    assert(check!(RegularTokens.Absorbed)(context, "ab").successful);
    assert(!check!(RegularTokens.RequiredTail)(context, "ab").successful);
}

@nogc nothrow private void regularCommitment() {
    import npegged.meta : AliasSeq;

    alias unit = or!(and!(literal!"a", option!(literal!"b")), literal!"bc");
    alias closed = and!(and!(literal!"a", zeroOrMore!(literal!"b")), literal!"a");
    static assert(!__traits(hasMember, RegularTokens, "_dfa_Maximal"));
    static assert(RegularTokens._dfa_Closed.valid);
    char[6] bytes;
    enum alphabet = "abc";
    size_t combinations = 1;
    foreach (length; 0 .. bytes.length + 1) {
        foreach (encoded; 0 .. combinations) {
            size_t value = encoded;
            foreach (ref c; bytes[0 .. length]) {
                c = alphabet[value % alphabet.length];
                value /= alphabet.length;
            }
            const input = cast(string)bytes[0 .. length];
            ParseContext context;
            static foreach (i, original; AliasSeq!(zeroOrMore!unit, oneOrMore!unit, closed,
                    zeroOrMore!(oneOrMore!(literal!"a")), zeroOrMore!(and!(literal!"a",
                    zeroOrMore!(literal!"a"), zeroOrMore!(literal!"b"))),
                    zeroOrMore!(and!(literal!"a",
                    zeroOrMore!(literal!"b"), zeroOrMore!(literal!"a"))))) {
                {
                    alias compiled = __traits(getMember, RegularTokens, [
                        "Maximal", "MaximalPlus", "Closed", "NestedRepeat", "RepeatableTail",
                        "CommittedTail"
                    ][i]);
                    auto baseline = check!original(context, input);
                    auto result = check!compiled(context, input);
                    assert(baseline.status == result.status && baseline.successful == result
                            .successful);
                    assert(baseline.end == result.end && baseline.failEnd == result.failEnd);
                }
            }
        }
        combinations *= alphabet.length;
    }
}

@nogc nothrow private void contextualQuotes() {
    import npegged.meta : AliasSeq;

    alias prefix = and!(literal!"\"", zeroOrMore!(or!(literal!"\"\"",
            oneOrMore!(and!(negLookahead!(literal!"\""), any)))), literal!"\"");
    alias whole = and!(prefix, literal!",", eoi);
    static assert(DelimitedQuotes._dfa_Whole.valid);
    char[7] bytes;
    enum alphabet = "a\",";
    size_t combinations = 1;
    foreach (length; 0 .. bytes.length + 1) {
        foreach (encoded; 0 .. combinations) {
            size_t value = encoded;
            foreach (ref c; bytes[0 .. length]) {
                c = alphabet[value % alphabet.length];
                value /= alphabet.length;
            }
            const input = cast(string)bytes[0 .. length];
            ParseContext context;
            static foreach (i, original; AliasSeq!(prefix, whole)) {
                {
                    alias compiled = __traits(getMember, DelimitedQuotes, ["Prefix", "Whole"][i]);
                    auto baseline = check!original(context, input);
                    auto result = check!compiled(context, input);
                    assert(baseline.status == result.status && baseline.successful == result
                            .successful);
                    assert(baseline.end == result.end && baseline.failEnd == result.failEnd);
                }
            }
        }
        combinations *= alphabet.length;
    }
    ParseContext context;
    assert(!check!(DelimitedQuotes.Prefix)(context, `"""`).successful);
    auto records = parseRecords!(DelimitedQuotes.Whole, everyRule)(context, `"",`);
    assert(records.successful && records.nodes.length == 2);
    assert(records.nodes[1].begin == 0 && records.nodes[1].end == 2);
}

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
    size_t traceCalls;
    context.trace = &traced;
    context.userData = &traceCalls;
    auto tracedGrammar = check!(Pegged.opCall)(context, PEGGEDgrammar);
    assert(tracedGrammar.successful && tracedGrammar.end == grammar.end && traceCalls > 0);
    auto tracedAction = check!(Pegged.opCall)(context, actionFixture);
    assert(tracedAction.successful && tracedAction.end == actionFixture.length);
    context.trace = null;
    auto peg = PEG(context, "A <- 'a'\n");
    assert(peg.successful);
    assert(npegged_checkMarkdown());
    assert(npegged_checkC());
    assert(npegged_checkD());
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
        npegged_Cgrammar(), npegged_Dgrammar(), npegged_MarkdownGrammar(),
        npegged_Oberon2Grammar(), PEGGgrammar, PEGGEDgrammar,
        npegged_pythonGrammar(), parameterizedExamples, npegged_XMLgrammar(), actionFixture
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
    factoredChoices();
    regularTokens();
    escapedTokens();
    optionalTokenPrefixes();
    regularCommitment();
    contextualQuotes();
    ownershipAndLimits();
    recognition();
    workflows();
    GC.enable();
    return 0;
}
