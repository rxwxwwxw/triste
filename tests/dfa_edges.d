/// Test-only exhaustive byte-transition checks for every instantiated scanner.
module tests.dfa_edges;

import npegged.dfa : scanDFAWith;

size_t exercise(alias Table)() nothrow {
    static if (__traits(hasMember, Table, "automaton"))
        enum automaton = Table.automaton;
    else
        enum automaton = Table;
    static if (automaton.valid) {
        size_t transitions;
        static void compare(string input, size_t pos = 0) nothrow {
            size_t codeExamined, loopExamined, codeEof, loopEof;
            const code = scanDFAWith!(Table, automaton.transitions.length <= 48)(input, pos, codeExamined,
                    codeEof);
            const loop = scanDFAWith!(Table, false)(input, pos, loopExamined, loopEof);
            assert(code == loop && codeExamined == loopExamined && codeEof == loopEof);
        }

        compare("", 1);
        auto visited = new bool[automaton.transitions.length];
        auto prefixes = new string[automaton.transitions.length];
        size_t[] queue = [0];
        visited[0] = true;
        for (size_t at; at < queue.length; ++at) {
            const state = queue[at];
            const prefix = prefixes[state];
            compare(prefix); // EOF at every reachable state, including nullable starts.
            foreach (value; 0 .. 256) {
                const input = prefix ~ cast(char)value;
                compare(input);
                ++transitions;
                const next = automaton.transitions[state][value];
                if (next != ubyte.max && !visited[next]) {
                    visited[next] = true;
                    prefixes[next] = input;
                    queue ~= cast(size_t)next;
                }
            }
        }
        return transitions;
    } else
        return 0;
}
