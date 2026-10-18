# Makefile for npegged: druntime-only, @nogc PEG parser generator in D

SHELL := /bin/bash

# Required compilers: dmd and ldc2; DC=gdc remains an optional compatibility path
DC ?= dmd

# Memory bound for test and build executions (default: 4G)
MEMORY_LIMIT ?= 4G

# Benchmark flags (e.g., BENCH_FLAGS="--iterations=500" or BENCH_FLAGS="--json")
BENCH_FLAGS ?=

HAVE_SYSTEMD_RUN := $(shell if command -v systemd-run >/dev/null 2>&1 && systemd-run --user --scope -q --unit="npegged-probe-$$$$-$$RANDOM" true >/dev/null 2>&1; then echo 1; else echo 0; fi)
ifeq ($(HAVE_SYSTEMD_RUN),1)
RUN_BOUNDED = systemd-run --user --scope -q --unit="npegged-make-$$$$-$$RANDOM" -p "MemoryMax=$(MEMORY_LIMIT)" -p MemorySwapMax=0 env MEMORY_LIMIT="$(MEMORY_LIMIT)"
else
RUN_BOUNDED = env MEMORY_LIMIT="$(MEMORY_LIMIT)"
endif

.PHONY: performance-check benchmark-checks benchmark-compare all build test test-all examples examples-all benchmark bench benchmark-memory bench-memory coverage hotpaths format check-format check-phobos asan valgrind validate validate-full install-hooks clean help

# Default target: build and run tests using $(DC)
all: build

# Compile library and run unit/integration tests with $(DC)
build:
	$(RUN_BOUNDED) DC=$(DC) scripts/build.sh

# Alias for build (runs unit + integration tests)
test: build

# Run unit and integration tests across all supported compilers
test-all:
	@for compiler in dmd ldc2; do \
		echo "=== Testing with $$compiler ==="; \
		$(RUN_BOUNDED) DC=$$compiler scripts/build.sh; \
	done

# Compile and run all example grammars with $(DC)
examples:
	$(RUN_BOUNDED) DC=$(DC) scripts/examples.sh

# Compile and run examples across all compilers
examples-all:
	@for compiler in dmd ldc2; do \
		echo "=== Running examples with $$compiler ==="; \
		$(RUN_BOUNDED) DC=$$compiler scripts/examples.sh; \
	done

# Run benchmarks against vendored Pegged
benchmark:
	$(RUN_BOUNDED) DC=$(DC) scripts/benchmark.sh $(BENCH_FLAGS)

bench: benchmark

benchmark-checks:
	$(RUN_BOUNDED) python3 scripts/benchmark_checks.py

# Three independent runs of the current equal-output performance matrix.
performance-check:
	$(RUN_BOUNDED) DC=$(DC) python3 scripts/performance_gate.py $(BENCH_FLAGS)

benchmark-compare:
	$(RUN_BOUNDED) DC=$(DC) python3 scripts/compare_benchmarks.py $(BENCH_FLAGS)

# Run benchmarks with allocator traffic measurements
benchmark-memory:
	$(RUN_BOUNDED) DC=$(DC) scripts/benchmark.sh --memory $(BENCH_FLAGS)

bench-memory: benchmark-memory

# Measure and verify src/ coverage (>90%; current branch collector needs GDC 16/gcov)
coverage:
	$(RUN_BOUNDED) scripts/coverage.sh

# Verify @nogc compliance on hot paths (-vgc diagnostics)
hotpaths:
	$(RUN_BOUNDED) scripts/hotpaths.sh

# Format all D source and test files using dfmt
format:
	find src tests examples scripts benchmark -name '*.d' -exec dfmt -i {} +

# Check that all D files conform to dfmt formatting
check-format:
	@UNFORMATTED=0; \
	while IFS= read -r -d '' file; do \
		dfmt "$$file" | cmp -s "$$file" - || { \
			echo "Formatting violation in $$file"; \
			UNFORMATTED=1; \
		}; \
	done < <(find src tests examples scripts benchmark -name '*.d' -print0); \
	if [ $$UNFORMATTED -ne 0 ]; then \
		echo "ERROR: Code is not formatted according to dfmt. Run 'make format'." >&2; \
		exit 1; \
	fi; \
	echo "All files conform to dfmt style."

# Enforce prohibition of Phobos imports in maintained code
check-phobos:
	@if rg -n --glob '*.d' 'import[[:space:]]+(std\.|[^;]*,[[:space:]]*std\.)' src tests examples scripts benchmark; then \
		echo 'ERROR: Phobos imports are forbidden in maintained D code.' >&2; \
		exit 1; \
	fi; \
	echo "Zero Phobos imports verified in src/, tests/, examples/, scripts/, benchmark/."

# Run AddressSanitizer and LeakSanitizer tests
asan:
	$(RUN_BOUNDED) DC=ldc2 ASAN_OPTIONS=detect_leaks=1:detect_stack_use_after_return=0 scripts/build.sh -fsanitize=address -g

# Run Valgrind Memcheck leak verification
valgrind:
	$(RUN_BOUNDED) DC=ldc2 scripts/build.sh -g -O0
	$(RUN_BOUNDED) timeout --preserve-status --kill-after=2s 120s valgrind \
		--tool=memcheck \
		--leak-check=full \
		--show-leak-kinds=all \
		--track-origins=yes \
		--errors-for-leak-kinds=definite,indirect \
		--error-exitcode=1 \
		build/ldc2/tests --DRT-testmode=run-main

# Run fast validation pipeline (ldc2 build, examples, hotpaths, hooks, format, phobos)
validate:
	$(RUN_BOUNDED) scripts/validate.sh --fast

# Run complete repository validation pipeline (all compilers, sanitizers, coverage, valgrind)
validate-full:
	$(RUN_BOUNDED) scripts/validate.sh --full

# Install git pre-commit hook
install-hooks:
	scripts/install-hooks.sh

# Clean build artifacts and temporary files
clean:
	rm -rf build/
	find . -type f \( -name '*.lst' -o -name '*.o' -o -name '*.gcda' -o -name '*.gcno' \) -delete

# Display help message
help:
	@echo "npegged Makefile targets:"
	@echo "  all              Build library and run tests with \$$(DC) (default: dmd)"
	@echo "  build / test     Compile and run unit/integration tests with \$$(DC)"
	@echo "  test-all         Run unit/integration tests on dmd and ldc2"
	@echo "  examples         Run examples with \$$(DC)"
	@echo "  examples-all     Run examples across dmd and ldc2"
	@echo "  bench / benchmark Run benchmark suite against vendored Pegged"
	@echo "  benchmark-checks Verify benchmark units, integrations, and diagnostic coverage"
	@echo "  performance-check Run repeated paired 5x gates for the equal-output corpus"
	@echo "  benchmark-compare Compare common outputs across D parsers and chumsky"
	@echo "  bench-memory     Run benchmark suite with allocator accounting"
	@echo "  coverage         Measure coverage and verify src/ >90% threshold"
	@echo "  hotpaths         Verify @nogc compliance on hot paths (-vgc)"
	@echo "  format           Format all .d files using dfmt"
	@echo "  check-format     Verify all .d files are properly formatted"
	@echo "  check-phobos     Verify zero Phobos imports in maintained code"
	@echo "  asan             Run AddressSanitizer & LeakSanitizer builds"
	@echo "  valgrind         Run Valgrind Memcheck memory leak validation"
	@echo "  validate         Run fast validation pipeline using ldc2 (scripts/validate.sh --fast)"
	@echo "  validate-full    Run full validation suite across all compilers (scripts/validate.sh --full)"
	@echo "  install-hooks    Install git pre-commit hooks"
	@echo "  clean            Remove build directory and temporary files"
	@echo ""
	@echo "Variables:"
	@echo "  DC               D compiler executable (default: dmd; e.g. DC=ldc2 or DC=gdc)"
	@echo "  MEMORY_LIMIT     Memory cap per test run when systemd-run is available (default: 4G)"
	@echo "  BENCH_FLAGS      Additional flags for benchmark runner (e.g. BENCH_FLAGS='--iterations=100 --json')"
