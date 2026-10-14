/** Small compile-time utilities for Pegged-derived examples (Boost 1.0). */
module npegged.meta;
template AliasSeq(T...) {
    alias AliasSeq = T;
}

template TypeTuple(T...) {
    alias TypeTuple = T;
}

template isInputRange(T) {
    enum isInputRange = __traits(compiles, {
            T r;
            bool empty = r.length == 0;
            auto value = r[0];
            r = r[1 .. $];
        });
}

template ElementType(T) {
    alias ElementType = typeof(T.init[0]);
}

@nogc nothrow unittest {
    static assert(isInputRange!(int[]));
    static assert(!isInputRange!int);
    static assert(is(ElementType!(int[]) == int));
    static assert(AliasSeq!(int, double).length == 2);
}
