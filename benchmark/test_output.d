module benchmark.test_output;

version (unittest) {
    import core.stdc.stdio : FILE, stdout, tmpfile, fclose, fflush, rewind, fread, printf;

    /// Scope-owned capture for testing C stdout without changing process file descriptors.
    struct CapturedStdout {
        private FILE* file;
        private FILE* previous;
        @disable this(this);
        @disable this(ref CapturedStdout);

        static CapturedStdout open() @nogc nothrow {
            CapturedStdout result;
            result.file = tmpfile();
            assert(result.file !is null);
            result.previous = stdout;
            stdout = result.file;
            return result;
        }

        ~this() @nogc nothrow {
            if (file !is null) {
                stdout = previous;
                fclose(file);
            }
        }

        size_t read(scope char[] buffer) @nogc nothrow {
            assert(file !is null);
            assert(fflush(file) == 0);
            rewind(file);
            return fread(buffer.ptr, 1, buffer.length, file);
        }
    }

    @nogc nothrow unittest {
        static assert(!__traits(compiles, { CapturedStdout owner; auto copy = owner; }));
        CapturedStdout empty;
        auto original = stdout;
        {
            auto capture = CapturedStdout.open();
            printf("capture");
            char[16] text;
            assert(capture.read(text) == 7 && text[0 .. 7] == "capture");
            assert(stdout != original);
        }
        assert(stdout == original);
    }
}
