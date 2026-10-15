/** Parsing engine derived from Philippe Sigaud's Pegged. Boost Software License 1.0. */
module npegged.peg;
public import npegged.storage : Arena, Status;
import npegged.storage : growthCapacity;

/// Non-owning node. Runtime slices belong to the enclosing ParseResult.
struct ParseTree {
    string name;
    bool successful;
    string[] matches;
    string input;
    size_t begin, end;
    ParseTree[] children;
    size_t failEnd;
    ParseTree[] failedChild;
    @property auto toString() const @nogc nothrow {
        import npegged.formatting : formatTree;

        return formatTree(this);
    }

    @property auto failMsg() const @nogc nothrow {
        import npegged.formatting : failureMessage;

        return failureMessage(this);
    }

    ref inout(ParseTree) opIndex(size_t i) inout return @nogc nothrow {
        return children[i];
    }

    inout(ParseTree)[] opIndex() inout return @nogc nothrow {
        return children;
    }

    size_t opDollar() const @nogc nothrow {
        return children.length;
    }

    inout(ParseTree)[] opSlice(size_t a, size_t b) inout return @nogc nothrow {
        return children[a .. b];
    }
}

@nogc nothrow unittest {
    ParseTree[2] children;
    children[0].name = "a";
    ParseTree tree;
    tree.children = children[];
    assert(tree[0].name == "a");
    assert(tree[].length == 2);
    assert(tree[0 .. $].length == 2);
    auto text = tree.toString;
    assert(text.status == Status.ok && text.data.length);
    auto failure = tree.failMsg;
    assert(failure.status == Status.ok && failure.data.length);
}

/// Limits are per parse; contexts can be reused or used independently by threads.
struct ParseContext {
    size_t memoryLimit = 256 * 1024 * 1024;
    size_t stepLimit = 10_000_000;
    size_t depthLimit = 1024;
    void* userData;
    void function(string, size_t, bool, void*) @nogc nothrow trace;
}

/// Owns input and all runtime tree storage. Views expire when this owner is destroyed.
struct ParseResult {
    Arena arena;
    ParseTree tree;
    Status status = Status.invalidInput;
    alias tree this;
    @disable this(this);
    @disable this(ref ParseResult);
}

/// One invocation's storage and rule state. CTFE instantiations use compiler storage.
struct State(bool CT) {
    Arena* arena;
    string input;
    ParseContext context;
    Status status;
    size_t steps, depth;
    private Entry* entries;
    private Entry*[] buckets;
    private size_t entryCount;
    private ParseTree furthestFailure;
    private bool hasFailure;
    private alias ParserIdentity = ParseTree function(ref State!CT, size_t) nothrow;
    private struct Entry {
        ParserIdentity identity;
        size_t position, hash;
        ParseTree seed;
        bool active, recursive, valid;
        Entry* next;
        Entry* bucketNext;
    }

    private static size_t keyHash(string key) @nogc nothrow pure {
        size_t hash = 2166136261;
        foreach (c; key)
            hash = (hash ^ cast(ubyte)c) * 16777619;
        return hash;
    }
    /// Local builder owns its capacity until its final snapshot is returned.
    struct Builder(T) {
        State* owner;
        T[] storage;
        size_t length;
        bool put(T[] values) nothrow {
            if (values.length > size_t.max - length) {
                owner.status = Status.resourceLimit;
                return false;
            }
            size_t required = length + values.length;
            if (required > storage.length) {
                size_t capacity = growthCapacity(storage.length, required, 4);
                auto replacement = owner.allocate!T(capacity);
                if (!replacement.length)
                    return false;
                replacement[0 .. length] = storage[0 .. length];
                storage = replacement;
            }
            storage[length .. required] = values[];
            length = required;
            return true;
        }

        T[] data() nothrow {
            return storage[0 .. length];
        }
    }

    T[] allocate(T)(size_t n) nothrow {
        static if (CT) {
            if (__ctfe)
                return new T[n];
        }
        auto data = arena.allocate!T(n);
        if (arena.status != Status.ok)
            status = arena.status;
        return data;
    }

    T[] append(T)(T[] a, T[] b) nothrow {
        if (!b.length)
            return a;
        if (a.length > size_t.max - b.length) {
            status = Status.resourceLimit;
            return null;
        }
        auto data = allocate!T(a.length + b.length);
        if (data.length) {
            data[0 .. a.length] = a[];
            data[a.length .. $] = b[];
        }
        return data;
    }

    T[] single(T)(T value) nothrow {
        auto data = allocate!T(1);
        if (data.length)
            data[0] = value;
        return data;
    }

    bool tick() nothrow {
        if (status != Status.ok)
            return false;
        if (steps >= context.stepLimit) {
            status = Status.resourceLimit;
            return false;
        }
        ++steps;
        return true;
    }

    ParseTree node(size_t start, size_t end, bool success = true) nothrow {
        ParseTree result;
        result.input = input;
        result.begin = start;
        result.end = end;
        result.failEnd = end;
        result.successful = success && status == Status.ok;
        return result;
    }

    ParseTree failure(size_t pos, string expected) nothrow {
        auto result = node(pos, pos, false);
        result.matches = single(expected);
        recordFailure(result);
        return result;
    }

    void recordFailure(ParseTree candidate) nothrow {
        while (candidate.failedChild.length && tick())
            candidate = candidate.failedChild[0];
        if (candidate.end > candidate.failEnd)
            candidate.failEnd = candidate.end;
        if (!hasFailure || candidate.failEnd >= furthestFailure.failEnd) {
            furthestFailure = candidate;
            hasFailure = true;
        }
    }

    ParseTree finish(ParseTree tree) nothrow {
        if (tree.end > tree.failEnd)
            tree.failEnd = tree.end;
        if (hasFailure && furthestFailure.failEnd >= tree.failEnd && (!tree.successful
                || furthestFailure.failEnd > tree.end)) {
            tree.failEnd = furthestFailure.failEnd;
            tree.failedChild = single(furthestFailure);
        }
        return tree;
    }
    /// Seed growth, with dependent memo entries invalidated whenever a seed grows.
    ParseTree rule(alias body, string name, bool memoize = true)(size_t pos) nothrow {
        if (!tick())
            return node(pos, pos, false);
        static if (!memoize) {
            if (depth >= context.depthLimit) {
                status = Status.resourceLimit;
                return node(pos, pos, false);
            }
            ++depth;
            scope (exit)
                --depth;
            auto candidate = body(this, pos);
            candidate.name = name;
            return candidate;
        } else {
            enum baseHash = keyHash(body.mangleof);
            size_t hash = baseHash ^ (pos * cast(size_t)0x9E3779B1);
            if (!buckets.length || entryCount > buckets.length * 3 / 4) {
                auto replacement = allocate!(Entry*)(buckets.length ? buckets.length * 2 : 64);
                if (!replacement.length)
                    return node(pos, pos, false);
                entryCount = 0;
                for (auto existing = entries; existing !is null; existing = existing.next) {
                    if (!existing.valid)
                        continue;
                    auto slot = existing.hash & (replacement.length - 1);
                    existing.bucketNext = replacement[slot];
                    replacement[slot] = existing;
                    ++entryCount;
                }
                buckets = replacement;
            }
            auto slot = hash & (buckets.length - 1);
            for (auto entry = buckets[slot]; entry !is null; entry = entry.bucketNext) {
                if (entry.valid && entry.identity == &body && entry.position == pos && (entry.active || memoize)) {
                    static if (CT) {
                        if (__ctfe)
                            assert(!entry.active, "Left-recursive input parsing is supported only at runtime");
                    }
                    if (entry.active)
                        entry.recursive = true;
                    else if (!entry.seed.successful)
                        recordFailure(entry.seed);
                    return entry.seed;
                }
            }
            if (depth >= context.depthLimit) {
                status = Status.resourceLimit;
                return node(pos, pos, false);
            }
            auto storage = allocate!Entry(1);
            if (!storage.length)
                return node(pos, pos, false);
            auto entry = &storage[0];
            entry.identity = &body;
            entry.hash = hash;
            entry.valid = true;
            entry.bucketNext = buckets[slot];
            buckets[slot] = entry;
            ++entryCount;
            entry.position = pos;
            entry.seed = node(pos, pos, false);
            entry.active = true;
            entry.next = entries;
            entries = entry;
            ++depth;
            scope (exit)
                --depth;
            do {
                auto candidate = body(this, pos);
                candidate.name = name;
                if (!candidate.successful || (entry.seed.successful && candidate.end <= entry.seed
                        .end)) {
                    if (!entry.seed.successful)
                        entry.seed = candidate;
                    break;
                }
                entry.seed = candidate;
                if (!entry.recursive)
                    break;
                // Keep active seeds; completed dependent entries must be recomputed.
                for (auto dependent = entries; dependent !is null; dependent = dependent.next) {
                    if (!dependent.active && dependent.position >= pos)
                        dependent.valid = false;
                }
            }
            while (tick());
            entry.active = false;
            if (context.trace !is null)
                context.trace(name, pos, entry.seed.successful, context.userData);
            return entry.seed;
        }
    }
}

@nogc nothrow unittest {
    Arena arena;
    State!false state;
    state.arena = &arena;
    state.input = "abc";
    auto data = state.single(42);
    assert(data == [42]);
    assert(state.append(data, data) == [42, 42]);
    assert(state.append(data, cast(int[])null) == [42]);
    assert(state.failure(1, "x").matches == ["x"]);
    state.context.stepLimit = 0;
    assert(!state.tick());
    assert(state.status == Status.resourceLimit);
}

ParseResult parse(alias parser)(ref ParseContext context, scope string input) @nogc nothrow {
    ParseResult result;
    result.arena.limit = context.memoryLimit;
    auto owned = result.arena.copy!char(input);
    if (result.arena.status != Status.ok) {
        result.status = result.arena.status;
        return result;
    }
    State!false state;
    state.arena = &result.arena;
    state.context = context;
    state.input = cast(string)owned;
    result.tree = state.finish(parser(state, 0));
    result.status = state.status != Status.ok ? state.status : (result.tree.successful ? Status.ok : Status
            .mismatch);
    if (state.status != Status.ok)
        result.tree.successful = false;
    return result;
}

/// CTFE entry point. Allocation is confined to compiler-managed storage.
ParseTree parseCT(alias parser)(string input) nothrow {
    assert(__ctfe, "Use parse!(parser)(context, input) at runtime");
    State!true state;
    state.input = input;
    auto tree = state.finish(parser(state, 0));
    assert(state.status == Status.ok, "Compile-time parser resource limit exceeded");
    return tree;
}

ParseTree eps(bool CT)(ref State!CT s, size_t pos) nothrow {
    auto result = s.node(pos, pos);
    result.matches = s.single("");
    return result;
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!eps(context, "");
    assert(result.successful && result.matches == [""]);
}

ParseTree fail(bool CT)(ref State!CT s, size_t pos) nothrow {
    return s.failure(pos, "failure");
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!fail(context, "a");
    assert(result.status == Status.mismatch);
}

ParseTree eoi(bool CT)(ref State!CT s, size_t pos) nothrow {
    return pos == s.input.length ? s.node(pos, pos) : s.failure(pos, "end of input");
}

@nogc nothrow unittest {
    ParseContext context;
    auto empty = parse!eoi(context, "");
    assert(empty.successful);
    auto nonempty = parse!eoi(context, "x");
    assert(!nonempty.successful);
}

alias endOfInput = eoi;
ParseTree any(bool CT)(ref State!CT s, size_t pos) nothrow {
    if (!s.tick() || pos >= s.input.length)
        return s.failure(pos, "any char");
    auto result = s.node(pos, pos + 1);
    result.matches = s.single(s.input[pos .. pos + 1]);
    return result;
}

@nogc nothrow unittest {
    ParseContext context;
    auto character = parse!any(context, "é");
    assert(character.end == 1);
    auto empty = parse!any(context, "");
    assert(!empty.successful);
}

/// Literal matching uses byte offsets, as in the upstream engine.
template literal(string text) {
    ParseTree literal(bool CT)(ref State!CT s, size_t pos) nothrow {
        if (!s.tick())
            return s.node(pos, pos, false);
        static if (text.length == 0) {
            return s.node(pos, pos);
        } else static if (text.length == 1) {
            if (pos < s.input.length && s.input[pos] == text[0]) {
                auto result = s.node(pos, pos + 1);
                result.matches = s.single(s.input[pos .. pos + 1]);
                return result;
            }
            auto result = s.failure(pos, text);
            result.failEnd = pos;
            s.recordFailure(result);
            return result;
        } else {
            if (pos + text.length <= s.input.length && s.input[pos .. pos + text.length] == text) {
                auto result = s.node(pos, pos + text.length);
                result.matches = s.single(s.input[pos .. pos + text.length]);
                return result;
            }
            size_t i;
            while (i < text.length && pos + i < s.input.length && s.input[pos + i] == text[i])
                ++i;
            auto result = s.failure(pos, text);
            result.failEnd = pos + i;
            s.recordFailure(result);
            return result;
        }
    }
}

@nogc nothrow unittest {
    ParseContext ctx;
    auto result = parse!(literal!"abc")(ctx, "abcd");
    assert(result.successful && result.end == 3);
    assert(result.matches == ["abc"]);
    auto bad = parse!(literal!"abc")(ctx, "ax");
    assert(bad.status == Status.mismatch && bad.failEnd == 1);
    auto empty = parse!(literal!"")(ctx, "");
    assert(empty.successful && empty.matches.length == 0);
    auto end = parse!eoi(ctx, "x");
    assert(!end.successful);
    auto end2 = parse!eoi(ctx, "");
    assert(end2.successful);
    auto one = parse!any(ctx, "ab");
    assert(one.end == 1);
    auto none = parse!any(ctx, "");
    assert(!none.successful);
    ctx.memoryLimit = 0;
    auto exhausted = parse!any(ctx, "x");
    assert(exhausted.status == Status.resourceLimit);
}

/// Strict UTF-8 scalar decoding for ranges and case-insensitive literals.
bool decode(scope string input, ref size_t pos, out dchar value) @nogc nothrow pure {
    if (pos >= input.length)
        return false;
    auto first = cast(ubyte)input[pos++];
    if (first < 0x80) {
        value = first;
        return true;
    }
    uint count = first >= 0xC2 && first <= 0xDF ? 1 : first >= 0xE0 && first <= 0xEF
        ? 2 : first >= 0xF0 && first <= 0xF4 ? 3 : 0;
    if (!count || count > input.length - pos)
        return false;
    uint scalar = first & ((1u << (6 - count)) - 1);
    foreach (i; 0 .. count) {
        auto next = cast(ubyte)input[pos++];
        if ((next & 0xC0) != 0x80)
            return false;
        scalar = (scalar << 6) | (next & 0x3F);
    }
    if (scalar < (count == 1 ? 0x80 : count == 2 ? 0x800 : 0x10000) || scalar > 0x10FFFF
            || (scalar >= 0xD800 && scalar <= 0xDFFF))
        return false;
    value = cast(dchar)scalar;
    return true;
}

@nogc nothrow unittest {
    foreach (text; ["a", "é", "€", "😀"]) {
        size_t pos;
        dchar value;
        assert(decode(text, pos, value) && pos == text.length);
    }
    foreach (text; [
        "", "\x80", "\xc0\xaf", "\xe0\x80\x80", "\xed\xa0\x80", "\xf4\x90\x80\x80", "\xc2x", "\xe2"
    ]) {
        size_t pos;
        dchar value;
        assert(!decode(text, pos, value));
    }
}

template charRange(dchar low, dchar high) {
    ParseTree charRange(bool CT)(ref State!CT s, size_t pos) nothrow {
        static if (high < 128) {
            if (!s.tick() || pos >= s.input.length)
                return s.failure(pos, "character range");
            const char c = s.input[pos];
            if (c < low || c > high)
                return s.failure(pos, "character range");
            auto result = s.node(pos, pos + 1);
            result.matches = s.single(s.input[pos .. pos + 1]);
            return result;
        } else {
            size_t end = pos;
            dchar value;
            if (!s.tick() || !decode(s.input, end, value) || value < low || value > high)
                return s.failure(pos, "character range");
            auto result = s.node(pos, end);
            result.matches = s.single(s.input[pos .. end]);
            return result;
        }
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(charRange!('α', 'ω'))(context, "β");
    assert(result.successful && result.end == 2);
    auto bad = parse!(charRange!('a', 'z'))(context, "1");
    assert(!bad.successful);
}

struct CharSetMask {
    ulong[4] bits;

    void addChar(dchar c) @nogc nothrow pure @safe {
        if (c < 256) {
            bits[(cast(uint)c) >> 6] |= (1UL << ((cast(uint)c) & 63));
        }
    }

    void addRange(dchar low, dchar high) @nogc nothrow pure @safe {
        if (low <= high && high < 256) {
            for (uint c = cast(uint)low; c <= cast(uint)high; ++c) {
                bits[c >> 6] |= (1UL << (c & 63));
            }
        }
    }

    static CharSetMask fromRanges(const(char[2])[] ranges...) @nogc nothrow pure @safe {
        CharSetMask mask;
        foreach (range; ranges) {
            mask.addRange(range[0], range[1]);
        }
        return mask;
    }

    static CharSetMask fromChars(const(char)[] chars...) @nogc nothrow pure @safe {
        CharSetMask mask;
        foreach (c; chars) {
            mask.addChar(c);
        }
        return mask;
    }

    bool contains(char c) const @nogc nothrow pure @safe {
        return (bits[(cast(ubyte)c) >> 6] & (1UL << ((cast(ubyte)c) & 63))) != 0;
    }

    bool empty() const @nogc nothrow pure @safe {
        return (bits[0] | bits[1] | bits[2] | bits[3]) == 0;
    }

    bool intersects(CharSetMask other) const @nogc nothrow pure @safe {
        return ((bits[0] & other.bits[0]) | (bits[1] & other.bits[1]) | (bits[2] & other.bits[2]) | (
                bits[3] & other.bits[3])) != 0;
    }

    CharSetMask opBinary(string op : "|")(CharSetMask other) const @nogc nothrow pure @safe {
        CharSetMask res;
        res.bits[0] = bits[0] | other.bits[0];
        res.bits[1] = bits[1] | other.bits[1];
        res.bits[2] = bits[2] | other.bits[2];
        res.bits[3] = bits[3] | other.bits[3];
        return res;
    }

    CharSetMask opBinary(string op : "&")(CharSetMask other) const @nogc nothrow pure @safe {
        CharSetMask res;
        res.bits[0] = bits[0] & other.bits[0];
        res.bits[1] = bits[1] & other.bits[1];
        res.bits[2] = bits[2] & other.bits[2];
        res.bits[3] = bits[3] & other.bits[3];
        return res;
    }

    CharSetMask opUnary(string op : "~")() const @nogc nothrow pure @safe {
        CharSetMask res;
        res.bits[0] = ~bits[0];
        res.bits[1] = ~bits[1];
        res.bits[2] = ~bits[2];
        res.bits[3] = ~bits[3];
        return res;
    }
}

@nogc nothrow unittest {
    CharSetMask mask;
    assert(mask.empty());
    mask.addChar('a');
    mask.addRange('0', '9');
    assert(mask.contains('a'));
    assert(mask.contains('0'));
    assert(mask.contains('9'));
    assert(!mask.contains('b'));
    assert(!mask.empty());

    CharSetMask other = CharSetMask.fromRanges(['b', 'd']);
    assert(!mask.intersects(other));
    auto combined = mask | other;
    assert(combined.contains('c'));
    assert(mask.intersects(combined));
    auto intersected = mask & combined;
    assert(intersected.contains('a'));
    assert(!intersected.contains('b'));
    auto inverted = ~mask;
    assert(!inverted.contains('a'));
    assert(inverted.contains('b'));
}

template charClass(ulong b0, ulong b1, ulong b2, ulong b3) {
    ParseTree charClass(bool CT)(ref State!CT s, size_t pos) nothrow {
        if (!s.tick() || pos >= s.input.length)
            return s.failure(pos, "character class");
        const ubyte c = cast(ubyte)s.input[pos];
        enum ulong[4] bits = [b0, b1, b2, b3];
        if ((bits[c >> 6] & (1UL << (c & 63))) == 0)
            return s.failure(pos, "character class");
        auto result = s.node(pos, pos + 1);
        result.matches = s.single(s.input[pos .. pos + 1]);
        return result;
    }
}

template charClass(CharSetMask mask) {
    alias charClass = charClass!(mask.bits[0], mask.bits[1], mask.bits[2], mask.bits[3]);
}

@nogc nothrow unittest {
    ParseContext context;
    enum mask = CharSetMask.fromRanges(['0', '9'], ['a', 'f']);
    auto valid = parse!(charClass!mask)(context, "a");
    assert(valid.successful && valid.end == 1 && valid.matches == ["a"]);
    auto digit = parse!(charClass!mask)(context, "5");
    assert(digit.successful && digit.end == 1);
    auto bad = parse!(charClass!mask)(context, "z");
    assert(!bad.successful && bad.status == Status.mismatch);
    auto empty = parse!(charClass!mask)(context, "");
    assert(!empty.successful);
}

template and(rules...) {
    ParseTree and(bool CT)(ref State!CT s, size_t pos) nothrow {
        auto result = s.node(pos, pos);
        State!CT.Builder!string matches = {owner: &s};
        State!CT.Builder!ParseTree children = {owner: &s};
        static foreach (r; rules) {
            {
                if (!s.tick())
                    return s.node(pos, pos, false);
                auto next = r(s, result.end);
                if (!next.successful) {
                    result.successful = false;
                    result.failEnd = next.failEnd;
                    result.matches = next.matches;
                    result.failedChild = s.single(next);
                    return result;
                }
                result.end = next.end;
                matches.put(next.matches);
                children.put(next.children);
                result.matches = matches.data();
                result.children = children.data();
            }
        }
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(and!(literal!"a", literal!"b"))(context, "ab");
    assert(result.end == 2 && result.matches == ["a", "b"]);
    auto bad = parse!(and!(literal!"a", literal!"b"))(context, "ac");
    assert(bad.failEnd == 1 && bad.status == Status.mismatch);
}

template choice(bool longest, rules...) {
    ParseTree choice(bool CT)(ref State!CT s, size_t pos) nothrow {
        auto result = s.node(pos, pos, false);
        static foreach (r; rules) {
            {
                auto candidate = r(s, pos);
                if (candidate.successful) {
                    if (!longest)
                        return candidate;
                    if (!result.successful || candidate.end > result.end)
                        result = candidate;
                } else if (!result.successful && candidate.failEnd >= result.failEnd)
                    result = candidate;
            }
        }
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(choice!(true, named!(literal!"a", "first"), named!(literal!"a", "second")))(
            context, "a");
    assert(result.name == "first");
}

template or(rules...) {
    alias or = choice!(false, rules);
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(or!(literal!"x", literal!"a"))(context, "a");
    assert(result.successful);
}

template branch(alias Rule, ulong b0, ulong b1, ulong b2, ulong b3) {
    alias rule = Rule;
    enum CharSetMask mask = CharSetMask([b0, b1, b2, b3]);
}

template branch(alias Rule, CharSetMask mask) {
    alias branch = branch!(Rule, mask.bits[0], mask.bits[1], mask.bits[2], mask.bits[3]);
}

template predictiveChoice(branches...) {
    private ubyte[256] computeTable() {
        ubyte[256] table;
        foreach (i, b; branches) {
            foreach (c; 0 .. 256) {
                if (b.mask.contains(cast(char)c)) {
                    table[c] = cast(ubyte)(i + 1);
                }
            }
        }
        return table;
    }

    enum ubyte[256] branchTable = computeTable();

    ParseTree predictiveChoice(bool CT)(ref State!CT s, size_t pos) nothrow {
        if (!s.tick())
            return s.node(pos, pos, false);
        if (pos >= s.input.length) {
            auto result = s.failure(pos, "choice");
            result.failEnd = pos;
            s.recordFailure(result);
            return result;
        }
        const ubyte b = cast(ubyte)s.input[pos];
        const ubyte target = branchTable[b];
        switch (target) {
            static foreach (i; 0 .. branches.length) {
        case i + 1:
                return branches[i].rule(s, pos);
            }
        default: {
                auto result = s.failure(pos, "choice");
                result.failEnd = pos;
                s.recordFailure(result);
                return result;
            }
        }
    }
}

@nogc nothrow unittest {
    ParseContext context;
    enum maskA = CharSetMask.fromChars('a');
    enum maskB = CharSetMask.fromChars('b');
    alias pred = predictiveChoice!(branch!(literal!"a", maskA), branch!(literal!"b", maskB));
    auto resA = parse!pred(context, "a");
    assert(resA.successful && resA.end == 1);
    auto resB = parse!pred(context, "b");
    assert(resB.successful && resB.end == 1);
    auto resC = parse!pred(context, "c");
    assert(!resC.successful);
    auto resEmpty = parse!pred(context, "");
    assert(!resEmpty.successful);
}

template longest_match(rules...) {
    alias longest_match = choice!(true, rules);
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(longest_match!(literal!"a", literal!"ab"))(context, "ab");
    assert(result.end == 2);
}

template repeat(alias r, size_t minimum, size_t maximum = size_t.max) {
    ParseTree repeat(bool CT)(ref State!CT s, size_t pos) nothrow {
        auto result = s.node(pos, pos);
        State!CT.Builder!string matches = {owner: &s};
        State!CT.Builder!ParseTree children = {owner: &s};
        size_t count;
        while (count < maximum && s.tick()) {
            auto next = r(s, result.end);
            if (!next.successful) {
                if (count < minimum)
                    return next;
                break;
            }
            matches.put(next.matches);
            children.put(next.children);
            result.matches = matches.data();
            result.children = children.data();
            ++count;
            if (next.end == result.end)
                break;
            result.end = next.end;
        }
        if (count < minimum || s.status != Status.ok)
            result.successful = false;
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(repeat!(digit, 2, 3))(context, "1234");
    assert(result.end == 3);
    auto bad = parse!(repeat!(digit, 2, 3))(context, "1");
    assert(!bad.successful);
}

template zeroOrMore(alias r) {
    alias zeroOrMore = repeat!(r, 0);
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(zeroOrMore!digit)(context, "x");
    assert(result.successful && result.end == 0);
}

template oneOrMore(alias r) {
    alias oneOrMore = repeat!(r, 1);
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(oneOrMore!digit)(context, "12x");
    assert(result.end == 2);
}

template option(alias r) {
    alias option = repeat!(r, 0, 1);
}

@nogc nothrow unittest {
    ParseContext context;
    auto absent = parse!(option!digit)(context, "x");
    assert(absent.successful);
    auto present = parse!(option!digit)(context, "1");
    assert(present.end == 1);
}

template lookahead(alias r, bool positive) {
    ParseTree lookahead(bool CT)(ref State!CT s, size_t pos) nothrow {
        auto saved = s.furthestFailure;
        bool hadFailure = s.hasFailure;
        auto next = r(s, pos);
        auto nestedFailure = s.furthestFailure;
        bool nestedHadFailure = s.hasFailure;
        s.furthestFailure = saved;
        s.hasFailure = hadFailure;
        auto result = s.node(pos, pos, next.successful == positive);
        if (!result.successful) {
            static if (positive) {
                result.matches = next.matches;
                result.failEnd = next.failEnd;
                if (nestedHadFailure)
                    s.recordFailure(nestedFailure);
                else
                    s.recordFailure(result);
            } else
                result = s.failure(pos, "negative lookahead");
        }
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(lookahead!(digit, false))(context, "1");
    assert(!result.successful && result.end == 0);
}

template posLookahead(alias r) {
    alias posLookahead = lookahead!(r, true);
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(posLookahead!digit)(context, "x");
    assert(!result.successful);
}

template negLookahead(alias r) {
    alias negLookahead = lookahead!(r, false);
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(negLookahead!digit)(context, "1");
    assert(!result.successful);
}

/// Tree transforms keep grammar nodes only; primitive combinators are flattened.
template transform(alias r, char operation) {
    ParseTree transform(bool CT)(ref State!CT s, size_t pos) nothrow {
        auto result = r(s, pos);
        if (!result.successful)
            return result;
        static if (operation == '~') {
            string joined;
            size_t length;
            foreach (match; result.matches)
                length += match.length;
            auto bytes = s.allocate!char(length);
            size_t offset;
            if (bytes.length == length)
                foreach (match; result.matches) {
                    bytes[offset .. offset + match.length] = match[];
                    offset += match.length;
                }
            if (result.matches.length)
                result.matches = s.single(cast(string)bytes);
            result.children = null;
        } else static if (operation == ':') {
            result.matches = null;
            result.children = null;
        } else static if (operation == ';')
            result.children = null;
        else static if (operation == '%') {
            ParseTree[] children;
            foreach (child; result.children)
                children = s.append(children, child.children);
            result.children = children;
        } else static if (operation == '^') {
            if (!result.children.length)
                result.children = s.single(result);
        }
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(transform!(oneOrMore!digit, '~'))(context, "123");
    assert(result.matches == ["123"]);
}

template fuse(alias r) {
    alias fuse = transform!(r, '~');
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(fuse!(and!(literal!"a", discard!(literal!"b"), literal!"c")))(context, "abc");
    assert(result.matches == ["ac"]);
}

template discard(alias r) {
    alias discard = transform!(r, ':');
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(and!(literal!"a", discard!(literal!"b")))(context, "ab");
    assert(result.matches == ["a"]);
}

template drop(alias r) {
    alias drop = transform!(r, ';');
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(drop!(defined!(literal!"a", "Node")))(context, "a");
    assert(result.matches == ["a"] && result.children.length == 0);
}

template propagate(alias r) {
    alias propagate = transform!(r, '%');
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(propagate!(defined!(defined!(literal!"a", "Child"), "Parent")))(context, "a");
    assert(result.children[0].name == "Child");
}

template keep(alias r) {
    alias keep = transform!(r, '^');
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(keep!(literal!"a"))(context, "a");
    assert(result.children.length == 1 && result.children[0].matches == ["a"]);
}

template discardChildren(alias r) {
    alias discardChildren = drop!r;
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(discardChildren!(defined!(literal!"a", "Node")))(context, "a");
    assert(result.children.length == 0);
}

template defined(alias r, string name) {
    ParseTree defined(bool CT)(ref State!CT s, size_t pos) nothrow {
        auto result = r(s, pos);
        result.name = name;
        if (result.matches.length || !result.successful)
            result.children = s.single(result);
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(defined!(literal!"a", "Node"))(context, "a");
    assert(result.name == "Node" && result.children[0].name == "Node");
}

template named(alias r, string name) {
    ParseTree named(bool CT)(ref State!CT s, size_t pos) nothrow {
        auto result = r(s, pos);
        result.name = name;
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(named!(literal!"a", "Node"))(context, "a");
    assert(result.name == "Node" && result.children.length == 0);
}

template action(alias r, alias act) {
    ParseTree action(bool CT)(ref State!CT s, size_t pos) nothrow {
        auto result = r(s, pos);
        if (s.status != Status.ok) {
            result.successful = false;
            return result;
        }
        static if (__traits(compiles, act(s, result)))
            result = act(s, result);
        else
            result = act(result);
        if (!result.successful)
            s.recordFailure(result);
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(action!(literal!"a", (ParseTree p) @nogc nothrow{ p.name = "acted"; return p; }))(
            context, "a");
    assert(result.name == "acted");
}

template wrapAround(alias before, alias target, alias after) {
    ParseTree wrapAround(bool CT)(ref State!CT s, size_t pos) nothrow {
        auto leading = before(s, pos);
        if (!leading.successful)
            return leading;
        auto result = target(s, leading.end);
        if (!result.successful)
            return result;
        auto trailing = after(s, result.end);
        if (!trailing.successful)
            return trailing;
        result.begin = leading.begin;
        result.end = trailing.end;
        if (result.children.length == 1 && result.children[0].name == result.name) {
            auto child = result.children[0];
            child.begin = result.begin;
            child.end = result.end;
            result.children = s.single(child);
        }
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(wrapAround!(literal!"(", literal!"a", literal!")"))(context, "(a)");
    assert(result.end == 3 && result.matches == ["a"]);
    auto bad = parse!(wrapAround!(literal!"(", literal!"a", literal!")"))(context, "(a");
    assert(!bad.successful);
}

alias digit = charRange!('0', '9');
alias alpha = charRange!('a', 'z');
alias Alpha = charRange!('A', 'Z');
alias hexDigit = charClass!(CharSetMask.fromRanges(['0', '9'], ['a', 'f'], ['A', 'F']));
alias endOfLine = or!(literal!"\r\n", literal!"\n", literal!"\r");
alias eol = endOfLine;
alias space = or!(literal!" ", literal!"\t", literal!"\v");
alias blank = or!(space, endOfLine);
alias tab = literal!"\t";
alias spaces = fuse!(oneOrMore!space);
alias spacing = discard!(zeroOrMore!blank);
alias digits = fuse!(oneOrMore!digit);
private enum identStartMask = () {
    auto m = CharSetMask.fromRanges(['a', 'z'], ['A', 'Z']);
    m.addChar('_');
    return m;
}();
private enum identCharMask = () {
    auto m = CharSetMask.fromRanges(['a', 'z'], ['A', 'Z'], ['0', '9']);
    m.addChar('_');
    return m;
}();
alias ident = and!(oneOrMore!(charClass!identStartMask), zeroOrMore!(charClass!identCharMask));
alias identifier = named!(fuse!ident, "identifier");
alias qualifiedIdentifier = fuse!(and!(identifier, zeroOrMore!(and!(literal!".", identifier))));
alias slash = literal!"/";
alias backslash = literal!"\\";
alias quote = literal!"'";
alias doublequote = literal!"\"";
alias backquote = literal!"`";
template list(alias element, alias separator) {
    alias list = and!(element, zeroOrMore!(and!(discard!separator, element)));
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(list!(digit, literal!","))(context, "1,2,3");
    assert(result.matches == ["1", "2", "3"]);
}

template list0(alias element, alias separator) {
    alias list0 = option!(list!(element, separator));
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(list0!(digit, literal!","))(context, "");
    assert(result.successful && result.end == 0);
}

@nogc nothrow unittest {
    ParseContext ctx;
    auto seq = parse!(and!(literal!"a", literal!"b"))(ctx, "ab");
    assert(seq.matches == ["a", "b"] && seq.end == 2);
    auto bad = parse!(and!(literal!"a", literal!"b"))(ctx, "ac");
    assert(!bad.successful && bad.failedChild.length == 1);
    auto alternatives = parse!(or!(literal!"x", literal!"ab"))(ctx, "ab");
    assert(alternatives.successful);
    auto longest = parse!(longest_match!(literal!"a", literal!"ab"))(ctx, "ab");
    assert(longest.end == 2);
    auto repeated = parse!(oneOrMore!digit)(ctx, "123x");
    assert(repeated.matches == ["1", "2", "3"]);
    auto none = parse!(oneOrMore!digit)(ctx, "x");
    assert(!none.successful);
    auto nullable = parse!(zeroOrMore!eps)(ctx, "");
    assert(nullable.successful);
    auto optional = parse!(option!digit)(ctx, "x");
    assert(optional.successful);
    auto positive = parse!(posLookahead!digit)(ctx, "1");
    assert(positive.end == 0 && positive.successful);
    auto negative = parse!(negLookahead!digit)(ctx, "x");
    assert(negative.successful);
    auto fused = parse!(fuse!(oneOrMore!digit))(ctx, "123");
    assert(fused.matches == ["123"]);
    auto id = parse!identifier(ctx, "hello_42");
    assert(id.matches == ["hello_42"]);
    auto range = parse!(charRange!('é', 'ê'))(ctx, "é");
    assert(range.end == 2);
}

/// Full Unicode folding, preserving Pegged's fixed byte-length literal consumption.
template caseInsensitiveLiteral(string text) {
    ParseTree caseInsensitiveLiteral(bool CT)(ref State!CT s, size_t pos) nothrow {
        if (!s.tick() || pos > s.input.length || text.length > s.input.length - pos
                || !caseEqual(s.input[pos .. pos + text.length], text))
            return s.failure(pos, text);
        auto result = s.node(pos, pos + text.length);
        result.matches = s.single(text);
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(caseInsensitiveLiteral!"Σ")(context, "σ");
    assert(result.successful && result.matches == ["Σ"]);
}

bool caseEqual(scope string a, scope string b) @nogc nothrow pure {
    import npegged.unicode : folded;

    size_t ap, bp;
    string af, bf;
    size_t ai, bi;
    dchar ac, bc;
    bool advance(scope string input, ref size_t pos, ref string expansion, ref size_t i, out dchar value) @nogc nothrow pure {
        if (i < expansion.length)
            return decode(expansion, i, value);
        if (!decode(input, pos, value))
            return false;
        expansion = folded(value);
        i = 0;
        if (expansion.length)
            return decode(expansion, i, value);
        return true;
    }

    while (ap < a.length || ai < af.length) {
        if (!advance(a, ap, af, ai, ac) || !advance(b, bp, bf, bi, bc) || ac != bc)
            return false;
    }
    return bp == b.length && bi == bf.length;
}

@nogc nothrow unittest {
    assert(caseEqual("AbCΣß", "abcσss"));
    assert(!caseEqual("x", "xx"));
    assert(!caseEqual("xy", "x"));
    assert(!caseEqual("\xff", "a"));
    assert(!caseEqual("a", "\xff"));
    ParseContext ctx;
    auto result = parse!(caseInsensitiveLiteral!"Begin")(ctx, "BEGIN");
    assert(result.successful && result.matches == ["Begin"]);
    auto bad = parse!(caseInsensitiveLiteral!"Begin")(ctx, "End");
    assert(!bad.successful);
}

/// Matches a boundary between alphabetic and non-alphabetic input (zero bytes).
ParseTree wordBoundary(bool CT)(ref State!CT state, size_t pos) nothrow {
    import npegged.unicode : isAlphabetic;

    bool left, right;
    dchar value;
    if (pos > 0 && pos <= state.input.length) {
        size_t start = pos - 1;
        while (start && (cast(ubyte)state.input[start] & 0xC0) == 0x80)
            --start;
        size_t end = start;
        left = decode(state.input, end, value) && end == pos && isAlphabetic(value);
    }
    if (pos < state.input.length) {
        size_t end = pos;
        right = decode(state.input, end, value) && isAlphabetic(value);
    }
    return left != right ? state.node(pos, pos) : state.failure(pos, "word boundary");
}

@nogc nothrow unittest {
    ParseContext context;
    auto start = parse!wordBoundary(context, "α");
    assert(start.successful && start.end == 0);
    auto finish = parse!(and!(literal!"α", wordBoundary))(context, "α ");
    assert(finish.successful);
    auto inside = parse!(and!(literal!"α", wordBoundary))(context, "αβ");
    assert(!inside.successful);
    auto empty = parse!wordBoundary(context, "");
    assert(!empty.successful);
}

template keywords(words...) {
    ParseTree keywords(bool CT)(ref State!CT state, size_t pos) nothrow {
        auto best = state.node(pos, pos, false);
        static foreach (word; words) {
            {
                auto candidate = literal!word(state, pos);
                if (candidate.successful)
                    return candidate;
            }
        }
        return best;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(keywords!("interface", "int", "in"))(context, "interface");
    assert(result.successful && result.end == 9);
    auto bad = parse!(keywords!("in", "int"))(context, "x");
    assert(!bad.successful);
}

template discardMatches(alias parser) {
    ParseTree discardMatches(bool CT)(ref State!CT state, size_t pos) nothrow {
        auto result = parser(state, pos);
        if (result.successful)
            result.matches = null;
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(discardMatches!(defined!(literal!"a", "A")))(context, "a");
    assert(result.successful && result.matches.length == 0 && result.children.length == 1);
}

template spaceAnd(alias separator, parsers...) {
    ParseTree spaceAnd(bool CT)(ref State!CT state, size_t pos) nothrow {
        auto result = state.node(pos, pos);
        State!CT.Builder!string matches = {owner: &state};
        State!CT.Builder!ParseTree children = {owner: &state};
        static foreach (parser; parsers) {
            {
                auto part = wrapAround!(separator, parser, separator)(state, result.end);
                if (!part.successful)
                    return part;
                result.end = part.end;
                matches.put(part.matches);
                children.put(part.children);
            }
        }
        result.matches = matches.data();
        result.children = children.data();
        return result;
    }
}

@nogc nothrow unittest {
    ParseContext context;
    auto result = parse!(spaceAnd!(spacing, literal!"a", literal!"b"))(context, " a b ");
    assert(result.successful && result.end == 5 && result.matches == ["a", "b"]);
}

struct Position {
    size_t line, col, index;
}

Position position(scope string input) @nogc nothrow pure {
    Position result;
    char previous = 0;
    foreach (c; input) {
        if (c == '\r' || c == '\n' && previous != '\r') {
            ++result.line;
            result.col = 0;
        } else if (c != '\n')
            ++result.col;
        previous = c;
        ++result.index;
    }
    return result;
}

@nogc nothrow unittest {
    assert(position("one\r\ntwo\r\nthree") == Position(2, 5, 15));
    assert(position("") == Position(0, 0, 0));
    assert(position("a\nb") == Position(1, 1, 3));
}

Position position(scope const ref ParseTree tree) @nogc nothrow pure {
    size_t end = tree.end <= tree.input.length ? tree.end : tree.input.length;
    return position(tree.input[0 .. end]);
}

@nogc nothrow unittest {
    ParseTree tree;
    tree.input = "a\nb";
    tree.end = 3;
    assert(position(tree) == Position(1, 1, 3));
}

@nogc nothrow unittest {
    ParseContext context;
    // Fail allocations and work budgets at different points in nested parser execution.
    foreach (budget; 0 .. 80) {
        context = ParseContext.init;
        context.memoryLimit = budget * 128;
        auto result = parse!(and!(defined!(fuse!(oneOrMore!digit), "Number"), literal!"x"))(
                context, "12345678901234567890x");
        assert(result.status == Status.ok || result.status == Status.resourceLimit);
        context = ParseContext.init;
        context.stepLimit = budget;
        auto limited = parse!(action!(oneOrMore!digit, (ParseTree tree) @nogc nothrow => tree))(context,
                "1234567890");
        assert(limited.status == Status.ok || limited.status == Status.resourceLimit);
    }
    auto leading = parse!(wrapAround!(literal!"(", literal!"a", literal!")"))(context, "a)");
    assert(!leading.successful);
    auto kept = parse!(keep!(defined!(literal!"a", "Child")))(context, "a");
    assert(kept.successful);
    auto failed = parse!(discardMatches!(literal!"a"))(context, "x");
    assert(!failed.successful);
    auto separated = parse!(spaceAnd!(spacing, literal!"a", literal!"b"))(context, " a x ");
    assert(!separated.successful);
    auto equalLength = parse!(caseInsensitiveLiteral!"abc")(context, "xyz");
    assert(!equalLength.successful);
    auto middle = parse!(and!(any, wordBoundary))(context, "α");
    assert(!middle.successful);
    auto word = parse!(and!(literal!"1", wordBoundary))(context, "1x");
    assert(word.successful);
    context.stepLimit = 0;
    auto byteLimited = parse!any(context, "a");
    assert(byteLimited.status == Status.resourceLimit);
    auto caseLimited = parse!(caseInsensitiveLiteral!"a")(context, "a");
    assert(caseLimited.status == Status.resourceLimit);
    auto rangeLimited = parse!(charRange!('a', 'z'))(context, "a");
    assert(rangeLimited.status == Status.resourceLimit);
}

@nogc nothrow unittest {
    ParseContext context;
    alias listParser = and!(literal!"[", digit, zeroOrMore!(and!(literal!",", digit)), literal!"]", eoi);
    auto invalid = parse!listParser(context, "[1,]");
    assert(invalid.status == Status.mismatch && invalid.failEnd == 3);
    auto diagnostic = invalid.failMsg;
    assert(diagnostic.data.length);
    auto valid = parse!listParser(context, "[1,2]");
    assert(valid.successful);
    // Failed matches inside a successful negative predicate must not override the real error.
    auto predicate = parse!(and!(negLookahead!(literal!"abc"), literal!"x"))(context, "abz");
    assert(!predicate.successful && predicate.failEnd == 0);
    auto positive = parse!(posLookahead!(literal!"abc"))(context, "abz");
    assert(positive.failEnd == 2);
    auto negative = parse!(negLookahead!(literal!"abc"))(context, "abc");
    assert(!negative.successful);
}
