# AGENTS.md

Prime Directive: 1. Make it work. 2. Make it correct. 3. Make it fast.  Those are the constant priorities. Always ensure properly working, correct code.  Accept slow when you can't make it faster correctly.

## Repository Architecture & Core Directives

This project uses **druntime-only D**. It retains access to core runtime primitives (`object.d`, `core.*`, slices, delegates, associative arrays, and selective GC), but **completely excludes Phobos (`std.*`)**.

All code authored, refactored, or reviewed by AI agents must strictly uphold these non-negotiable architectural constraints:

1. **Zero Phobos (`std.*` is banned):** Never import `std.*`. Rely solely on `core.*` modules, runtime primitives, or repository-internal utilities.
2. **Deterministic RAII First:** Manual resource cleanup is prohibited. Bind ownership of OS handles, and network sockets to struct lifetimes via constructors and destructors.
3. **Exception-Free (`nothrow`):** Never use `throw new Exception(...)`. Unwindable exceptions and unwinding tables are disabled. Error handling must use explicit `Result!(T, E)` tagged unions or status codes.
4. **Zero GC in Hot Paths (`@nogc`):** All performance-critical paths, per-frame updates, packet/stream processors, and inner loops must be statically verified as `@nogc`.
5. **Strict Unit Testing (>90% Coverage):** Every module in `src/` must exceed 90% branch and line coverage. Files outside `src/`, including tests, examples, benchmarks, and scripts, are excluded from this threshold. Unit tests must live in the same source file, placed immediately beneath the function or struct under test.
6. **Integration Tests with Timeouts:** Major subsystems and cross-module workflows must have end-to-end integration tests located in the `tests/` directory (sibling to `src/`). Every integration test binary or runner must have a mandatory execution timeout and memory thresholds(usually 4GB).
7. **Canonical Formatting (`dfmt`):** All `.d` files must be formatted with `dfmt` before commit. Unformatted code fails CI and pre-commit hooks.
8. **Multi-Compiler Compliance:** Code must compile cleanly across **DMD** and **LDC** with zero compiler warnings.
9. **Leak & Memory Safety Enforcement:** Code must run clean under AddressSanitizer (ASan), LeakSanitizer (LSan), and Valgrind (Memcheck) with zero leaks or invalid accesses.

---

## 1. Code Style, Formatting & Commit Automation

### 1.1. Formatting with `dfmt`

All source and test files must conform to the project's `.dfmt` style. Agents must run `dfmt` inline on all touched files:

```bash
# Format all source and integration test files
find src tests -name "*.d" -exec dfmt -i {} +

```

Expected `.dfmt` baseline configuration (stored at repo root):

```ini
dfmt_align_switch_statements=true
dfmt_brace_style=otbs
dfmt_compact_labeled_switch_statements=true
dfmt_indent_size=4
dfmt_indent_style=space
dfmt_soft_max_line_length=100
dfmt_outdent_attributes=true
dfmt_space_after_cast=false
dfmt_split_operator_at_line_end=false

```

### 1.2. Git Commit Hook Enforcement

Every clone must maintain an active `.git/hooks/pre-commit` script. Agents adding tooling or build steps must ensure this script remains operational:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== [Hook] 1. Checking for Phobos imports ==="
if grep -rn --include="*.d" "import[[:space:]]\+std\." src/; then
    echo "ERROR: Phobos import detected in src/. Only core.* is allowed."
    exit 1
fi

echo "=== [Hook] 2. Checking dfmt compliance ==="
UNFORMATTED=0
for file in $(git diff --cached --name-only --diff-filter=ACMR | grep '\.d$'); do
    dfmt "$file" | cmp -s "$file" - || {
        echo "ERROR: File '$file' is not formatted according to dfmt."
        UNFORMATTED=1
    }
done
if [ $UNFORMATTED -eq 1 ]; then
    echo "Run: find src tests -name '*.d' -exec dfmt -i {} + and re-stage."
    exit 1
fi

echo "=== [Hook] 3. Enforcing @nogc on hot paths (-vgc) ==="
dmd -c -vgc src/hotpath.d -o-

echo "=== [Hook] 4. Running unit tests and checking coverage ==="
dmd -unittest -cov -run src/index.d > /dev/null
# Verify src/ line and branch coverage above 90%
python3 scripts/verify_coverage.py --threshold 90

echo "=== [Hook] All pre-commit checks passed ==="

```

---

## 2. Unit Testing & Coverage (>90%)

### 2.1. Colocation Rule

Unit tests must **never** be placed in separate test files or relegated to the bottom of the module. Place `unittest` blocks **immediately below** the symbol they validate.

```d
module myproject.buffer;

/// Circular ring buffer with zero allocations on push/pop
struct RingBuffer(T, size_t Capacity) {
    private T[Capacity] _data;
    private size_t _head;
    private size_t _tail;

    bool push(T item) @nogc nothrow {
        // Implementation...
        return true;
    }
}

// Colocated unit test immediately beneath the implementation
@nogc nothrow unittest {
    RingBuffer!(int, 4) buf;
    assert(buf.push(42));
    assert(buf.push(84));
}

```

### 2.2. Contract Mirroring

If a function is `@nogc nothrow`, its corresponding unit tests **must also be annotated `@nogc nothrow**`. This guarantees that invoking the function in tests does not silently permit hidden GC sweeps or exceptions.

### 2.3. Measuring and Enforcing >90% Coverage

Coverage is tracked via the compiler's `-cov` instrumentation:

```bash
# Build and execute unit tests with coverage enabled
dmd -unittest -cov -run src/buffer.d

# Generates buffer.lst containing source line hit counts:
# 95% of 120 lines covered

```

*Rule: Any commit dropping line or branch coverage to 90% or below in any module under `src/` will be rejected by the pre-commit hook and CI.*

---

## 3. Integration Testing & Timeouts

Integration tests validate cross-module functionality, system calls, long-lived loops, and state machines.

### 3.1. Directory Structure

Integration tests reside strictly in `tests/`, parallel to `src/`:

```
repo-root/
├── .dfmt
├── scripts/
│   └── verify_coverage.py
├── src/
│   ├── app.d
│   ├── buffer.d          # Contains implementation + colocated unittests
│   └── hotpath.d         # Contains implementation + colocated unittests
└── tests/
    ├── runner.d          # Integration test orchestrator
    ├── test_networking.d # Subsystem integration suite
    └── test_storage.d    # Subsystem integration suite

```

### 3.2. Mandatory Execution Timeouts

Integration tests must not run indefinitely under deadlock, live-lock, or resource exhaustion. Every test case or test runner invocation must implement an explicit timeout.

#### Pattern A: OS-Level Runner Timeout

In automated scripts, wrap the integration runner with the POSIX `timeout` utility:

```bash
# Hard limit: fail test if execution exceeds 10 seconds
timeout --preserve-status --kill-after=2s 10s ./tests/integration_runner

```

#### Pattern B: Built-in Watchdog Timer (No std.*)

When fine-grained per-test timeouts are required without Phobos, use POSIX interval timers:

```d
module tests.watchdog;

import core.sys.posix.unistd : alarm;
import core.sys.posix.signal : signal, SIGALRM, SIG_DFL;

/// Sets a hard process deadline in seconds.
void setDeadline(uint seconds) @nogc nothrow {
    alarm(seconds);
}

/// Disarms the watchdog timer.
void clearDeadline() @nogc nothrow {
    alarm(0);
}

// Usage in an integration test:
void testEndToEndPipeline() {
    setDeadline(5); // Must complete within 5 seconds or SIGALRM kills process
    scope(exit) clearDeadline();

    // Run end-to-end multi-module pipeline...
}

```

---

## 4. RAII & Ownership Rules

Every system resource must be owned by an explicit scope or an RAII wrapper struct.

### 4.1. Explicit Move Semantics & Copy Disabling

When writing a resource handle, explicitly disable implicit copy semantics to prevent double-free bugs:

```d
struct ScopedBuffer {
    private void* _ptr;
    private size_t _capacity;

    @disable this(this);             // Disable postblit
    @disable this(ref typeof(this));  // Disable copy constructor

    static ScopedBuffer allocate(size_t size) @nogc nothrow {
        import core.stdc.stdlib : malloc;
        ScopedBuffer buf;
        buf._ptr = malloc(size);
        buf._capacity = size;
        return buf;
    }

    ~this() @nogc nothrow {
        if (_ptr !is null) {
            import core.stdc.stdlib : free;
            free(_ptr);
            _ptr = null;
        }
    }
}

```

### 4.2. Local Scoped Cleanup

For resources with immediate function-level lifecycles, prefer `scope(exit)`:

```d
void processFile(const char* path) @nogc nothrow {
    import core.sys.posix.fcntl : open, close, O_RDONLY;
    int fd = open(path, O_RDONLY);
    if (fd < 0) return;
    scope(exit) close(fd);

    // Work with fd...
}

```

---

## 5. Error Handling Protocol

### 5.1. Expected Errors

Functions that can fail due to runtime conditions (I/O, invalid inputs, timeouts) must return a `Result!(T, E)` tagged union or a status enum:

```d
enum SystemError : int {
    None = 0,
    InvalidPayload,
    OutOfMemory,
    IoTimeout
}

struct Result(T, E = SystemError) {
    private union { T _value; E _error; }
    private bool _isOk;

    static Result ok(T val) @nogc nothrow {
        Result r; r._isOk = true; r._value = val; return r;
    }
    static Result err(E err) @nogc nothrow {
        Result r; r._isOk = false; r._error = err; return r;
    }

    bool isOk() const @nogc nothrow pure @safe { return _isOk; }
    inout(T) value() inout @nogc nothrow @trusted { assert(_isOk); return _value; }
    inout(E) error() inout @nogc nothrow @trusted { assert(!_isOk); return _error; }
}

```

### 5.2. Invariants vs. Runtime Errors

Use standard D `assert(...)` for code contracts and invariant enforcement. An assertion failure raises `core.exception.AssertError`, which aborts the process deterministically and remains legal inside `nothrow` code.

---

## 6. Compiler Diagnostics & Verification

### 6.1. GC Allocation Diagnostics (`-vgc`)

Verify that modules intended to be GC-free emit zero allocations during compilation:

```bash
dmd -c -vgc src/hotpath.d
ldc2 -c -vgc src/hotpath.d

```

*Rule: Any compiler message indicating hidden closures or array appends in a hot path is treated as a hard build failure.*

### 6.2. Building Without Phobos Linking

```bash
# LDC (Preferred for release / optimized builds)
ldc2 -defaultlib=druntime-ldc -fno-exceptions -O3 app.d

# DMD (Development / Fast debug)
dmd -defaultlib=druntime app.d

```

---

## 7. Sanitizers & Leak Detection Protocol

### 7.1. AddressSanitizer & LeakSanitizer (LDC)

Run test binaries built with ASan and LSan:

```bash
# Build and run with Address and Leak Sanitizers
ldc2 -fsanitize=address -g -unittest -run tests/runner.d

```

### 7.2. Valgrind Memcheck

For heap inspection, use-after-free, and uninitialized reads:

```bash
ldc2 -g -O0 tests/runner.d -of=test_runner

valgrind \
  --tool=memcheck \
  --leak-check=full \
  --show-leak-kinds=all \
  --track-origins=yes \
  --errors-for-leak-kinds=definite,indirect \
  --error-exitcode=1 \
  ./test_runner

```

*Rule: Any reported byte leaks (`definitely lost` or `indirectly lost`) or invalid memory reads must be resolved prior to merging.*

---

## 8. Pre-Submission Checklist for AI Agents

Before submitting code, generating patches, or opening a PR, complete every item:

* [ ] **No `std.*` Imports:** Ran `grep -rn "import std\." src/` and verified 0 hits.
* [ ] **Formatted with `dfmt`:** Executed `find src tests -name "*.d" -exec dfmt -i {} +`.
* [ ] **Unit Tests Colocated:** Every new or edited function has an adjacent `unittest` block directly below it.
* [ ] **Unit Test Coverage >90%:** Verified via `dmd -unittest -cov` and validated against the coverage threshold for `src/` only.
* [ ] **Integration Tests Located in `tests/`:** Multi-module behaviors tested in `tests/` with mandatory timeouts configured (`alarm()` or `timeout`).
* [ ] **Hot Paths are `@nogc`:** Hot-path modules and functions are marked `@nogc` and verified cleanly with `-vgc`.
* [ ] **Exception Free:** Marked `nothrow`, and fallible operations use `Result!(T, E)`.
* [ ] **RAII Encapsulation:** All system handles and dynamic buffers use RAII wrappers with `@disable this(this);`.
* [ ] **Sanitizer & Leak Clean:** Executed clean runs under ASan/LSan and Valgrind Memcheck with exit code 0.
* [ ] **Git Hook Compliance:** Passed all staged validations in `.git/hooks/pre-commit`.
