module benchmark.json_output;

import npegged.storage : Arena, Status, growthCapacity;
import npegged.records : CompactNode;
import benchmark.handwritten.json : JsonLexer, Token, TokenType, JsonParser;

enum OutputMode {
    validation,
    spans,
    tree
}

enum NodeKind : uint {
    object,
    array,
    string_,
    number,
    true_,
    false_,
    null_
}

/// Preorder concrete JSON tree. Spans borrow the immutable benchmark input.
/// Object keys are string nodes; parent indices preserve ordering and nesting.
struct OutputNode {
    NodeKind kind;
    size_t begin, end;
    size_t parent = size_t.max;
}

struct JsonOutput {
    Arena arena;
    private OutputNode[] storage;
    private size_t length;
    bool accepted;
    @disable this(this);
    @disable this(ref JsonOutput);

    @property OutputNode[] nodes() return @nogc nothrow {
        return storage[0 .. length];
    }

    size_t add(OutputNode node) @nogc nothrow {
        if (length == storage.length) {
            auto next = arena.allocate!OutputNode(growthCapacity(length, length + 1, 32));
            if (!next.length)
                return size_t.max;
            next[0 .. length] = storage[0 .. length];
            storage = next;
        }
        storage[length] = node;
        return length++;
    }

    /// Invalid parses expose no partial output, irrespective of engine diagnostics.
    void reject() @nogc nothrow {
        accepted = false;
        length = 0;
    }
}

@nogc nothrow unittest {
    JsonOutput output;
    foreach (i; 0 .. 65)
        assert(output.add(OutputNode(NodeKind.number, i, i + 1)) == i);
    assert(output.nodes.length == 65 && output.nodes[64].end == 65);
    assert(output.arena.allocationCalls > 0 && output.arena.allocationCalls <= 3);
    assert(output.arena.requestedBytes == (32 + 64 + 128) * OutputNode.sizeof);
    output.reject();
    assert(!output.accepted && !output.nodes.length);
    JsonOutput failed;
    failed.arena.limit = 0;
    assert(failed.add(OutputNode.init) == size_t.max);
    assert(failed.arena.status == Status.resourceLimit);
}

/// Identical output consumer for all engines; raw input bytes need no decoding.
ulong fingerprint(scope const(OutputNode)[] nodes) @nogc nothrow pure {
    ulong hash = 14695981039346656037UL;
    foreach (node; nodes) {
        foreach (word; [
            cast(ulong)node.kind, cast(ulong)node.begin, cast(ulong)node.end, cast(ulong)node.parent
        ]) {
            hash = (hash ^ word) * 1099511628211UL;
        }
    }
    return hash;
}

@nogc nothrow unittest {
    OutputNode[1] nodes = [OutputNode(NodeKind.number, 0, 1)];
    const original = fingerprint(nodes);
    assert(original != fingerprint(cast(OutputNode[])null));
    nodes[0].parent = 0;
    assert(original != fingerprint(nodes));
}

/// Overload for compact records to produce comparable fingerprints without templates.
ulong fingerprint(scope const(CompactNode)[] nodes) @nogc nothrow pure {
    ulong hash = 14695981039346656037UL;
    foreach (node; nodes) {
        foreach (word; [
            cast(ulong)node.kind, cast(ulong)node.begin, cast(ulong)node.end, cast(ulong)node.parent
        ]) {
            hash = (hash ^ word) * 1099511628211UL;
        }
    }
    return hash;
}

@nogc nothrow unittest {
    CompactNode[1] nodes = [CompactNode(1, 0, 1)];
    const original = fingerprint(nodes);
    assert(original != fingerprint(cast(CompactNode[])null));
    nodes[0].parent = 0;
    assert(original != fingerprint(nodes));
}

/// Select semantic rule nodes, skipping grammar wrappers and string internals.
/// Both Pegged tree types satisfy this interface; the adapter allocates only via RAII.
bool projectTree(T)(scope const ref T tree, OutputMode mode, ref JsonOutput output, size_t parent = size_t
        .max) @nogc nothrow {
    NodeKind kind;
    bool selected = true;
    bool container;
    switch (tree.name) {
    case "JSON.Object":
        kind = NodeKind.object;
        container = true;
        break;
    case "JSON.Array":
        kind = NodeKind.array;
        container = true;
        break;
    case "Ambiguous.Start":
    case "JSON.String":
        kind = NodeKind.string_;
        break;
    case "JSON.Number":
        kind = NodeKind.number;
        break;
    case "JSON.True":
        kind = NodeKind.true_;
        break;
    case "JSON.False":
        kind = NodeKind.false_;
        break;
    case "JSON.Null":
        kind = NodeKind.null_;
        break;
    default:
        selected = false;
        break;
    }
    if (selected) {
        if (!container || mode == OutputMode.tree) {
            auto index = output.add(OutputNode(kind, tree.begin, tree.end, mode == OutputMode.tree ? parent : size_t
                    .max));
            if (index == size_t.max)
                return false;
            parent = index;
        }
        if (!container)
            return true;
    }
    foreach (ref child; tree.children)
        if (!projectTree(child, mode, output, parent))
            return false;
    return true;
}

@nogc nothrow unittest {
    import npegged.peg : ParseTree;

    ParseTree[2] children;
    children[0].name = "JSON.String";
    children[0].begin = 1;
    children[0].end = 4;
    children[1].name = "JSON.Null";
    children[1].begin = 5;
    children[1].end = 9;
    ParseTree tree;
    tree.name = "JSON.Object";
    tree.end = 10;
    tree.children = children[];
    JsonOutput output;
    assert(projectTree(tree, OutputMode.tree, output));
    assert(output.nodes.length == 3 && output.nodes[1].parent == 0);
    JsonOutput spans;
    assert(projectTree(tree, OutputMode.spans, spans));
    assert(spans.nodes.length == 2 && spans.nodes[1].parent == size_t.max);
    JsonOutput failed;
    failed.arena.limit = 0;
    assert(!projectTree(tree, OutputMode.tree, failed));
    JsonOutput leafFailed;
    leafFailed.arena.limit = 0;
    assert(!projectTree(tree, OutputMode.spans, leafFailed));
}

private struct OutputParser {
    JsonLexer lexer;
    Token current;
    OutputMode mode;
    JsonOutput* output;

    void advance() @nogc nothrow {
        current = lexer.nextToken();
    }

    size_t begin() @nogc nothrow {
        return cast(size_t)(current.text.ptr - lexer.src.ptr);
    }

    size_t end() @nogc nothrow {
        return begin() + current.text.length;
    }

    bool scalar(size_t parent) @nogc nothrow {
        NodeKind kind;
        switch (current.type) {
        case TokenType.stringLit:
            kind = NodeKind.string_;
            break;
        case TokenType.number:
            kind = NodeKind.number;
            break;
        case TokenType.kwTrue:
            kind = NodeKind.true_;
            break;
        case TokenType.kwFalse:
            kind = NodeKind.false_;
            break;
        case TokenType.kwNull:
            kind = NodeKind.null_;
            break;
        default:
            return false;
        }
        if (output.add(OutputNode(kind, begin(), end(), parent)) == size_t.max)
            return false;
        advance();
        return true;
    }

    bool value(size_t parent = size_t.max, size_t depth = 0) @nogc nothrow {
        if (depth > 512)
            return false;
        const object = current.type == TokenType.leftBrace;
        if (!object && current.type != TokenType.leftBracket)
            return scalar(parent);
        const close = object ? TokenType.rightBrace : TokenType.rightBracket;
        size_t index = size_t.max;
        if (mode == OutputMode.tree) {
            index = output.add(OutputNode(object ? NodeKind.object : NodeKind.array, begin(), 0, parent));
            if (index == size_t.max)
                return false;
        }
        advance();
        if (current.type != close) {
            while (true) {
                if (object) {
                    if (current.type != TokenType.stringLit || !scalar(index))
                        return false;
                    if (current.type != TokenType.colon)
                        return false;
                    advance();
                }
                if (!value(index, depth + 1))
                    return false;
                if (current.type != TokenType.comma)
                    break;
                advance();
            }
        }
        if (current.type != close)
            return false;
        if (index != size_t.max)
            output.nodes[index].end = end();
        advance();
        return true;
    }
}

@nogc nothrow unittest {
    JsonOutput output;
    OutputParser parser = OutputParser(JsonLexer("true", 0), Token.init, OutputMode.spans, &output);
    parser.advance();
    assert(parser.value() && output.nodes[0].kind == NodeKind.true_);
    JsonOutput invalid;
    OutputParser bad = OutputParser(JsonLexer("{", 0), Token.init, OutputMode.tree, &invalid);
    bad.advance();
    assert(!bad.value());
}

JsonOutput handwrittenOutput(string input, OutputMode mode) @nogc nothrow {
    JsonOutput result;
    if (mode == OutputMode.validation) {
        result.accepted = JsonParser.parse(input);
        return result;
    }
    OutputParser parser = OutputParser(JsonLexer(input, 0), Token.init, mode, &result);
    parser.advance();
    result.accepted = parser.value() && parser.current.type == TokenType.eof;
    if (!result.accepted)
        result.reject();
    return result;
}

@nogc nothrow unittest {
    enum input = ` {"a":[1,true,false,null,"x"],"b":{}} `;
    auto tree = handwrittenOutput(input, OutputMode.tree);
    assert(tree.accepted && tree.nodes.length == 10);
    assert(tree.nodes[0] == OutputNode(NodeKind.object, 1, input.length - 1));
    assert(tree.nodes[1] == OutputNode(NodeKind.string_, 2, 5, 0));
    assert(tree.nodes[2].kind == NodeKind.array && tree.nodes[2].parent == 0);
    auto spans = handwrittenOutput(input, OutputMode.spans);
    assert(spans.accepted && spans.nodes.length == 7);
    foreach (node; spans.nodes)
        assert(node.parent == size_t.max);
    auto check = handwrittenOutput(input, OutputMode.validation);
    assert(check.accepted && check.arena.allocationCalls == 0);
    foreach (bad; ["[1,]", "{1:2}", `{"a" 1}`, "[", "{}x", "tru", `{"a":}`]) {
        auto rejected = handwrittenOutput(bad, OutputMode.tree);
        assert(!rejected.accepted && !rejected.nodes.length);
    }
}

/// Handwritten equivalent of ('a'* 'b' / 'a'* 'c') eoi, retaining ordered retry.
bool handwrittenAmbiguous(string input) @nogc nothrow pure {
    foreach (ending; "bc") {
        size_t pos;
        while (pos < input.length && input[pos] == 'a')
            ++pos;
        if (pos < input.length && input[pos] == ending && pos + 1 == input.length)
            return true;
    }
    return false;
}

@nogc nothrow unittest {
    foreach (input; ["b", "c", "aaab", "aaac"])
        assert(handwrittenAmbiguous(input));
    foreach (input; ["", "a", "aad", "acc"])
        assert(!handwrittenAmbiguous(input));
}

JsonOutput ambiguousOutput(string input, OutputMode mode) @nogc nothrow {
    JsonOutput result;
    result.accepted = handwrittenAmbiguous(input);
    if (result.accepted && mode != OutputMode.validation) {
        if (result.add(OutputNode(NodeKind.string_, 0, input.length)) == size_t.max)
            result.reject();
    }
    return result;
}

@nogc nothrow unittest {
    auto result = ambiguousOutput("aac", OutputMode.tree);
    assert(result.accepted && result.nodes.length == 1);
    auto invalid = ambiguousOutput("aad", OutputMode.spans);
    assert(!invalid.accepted && !invalid.nodes.length);
    auto check = ambiguousOutput("aab", OutputMode.validation);
    assert(check.accepted && !check.nodes.length);
}
