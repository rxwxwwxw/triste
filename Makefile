# Makefile for npegged: druntime-only, @nogc PEG parser generator in D

SHELL := /bin/bash

# Default compiler: dmd, ldc2, or gdc
DC ?= dmd

# Benchmark flags (e.g., BENCH_FLAGS="--iterations=500" or BENCH_FLAGS="--json")
BENCH_FLAGS ?=

.PHONY: benchmark-checks benchmark-compare all build test test-all examples examples-all benchmark bench benchmark-memory bench-memory coverage hotpaths format check-format check-phobos asan valgrind validate install-hooks clean help

# Default target: build and run tests using $(DC)
all: build

# Compile library and run unit/integration tests with $(DC)
build:
	DC=$(DC) scripts/build.sh

# Alias for build (runs unit + integration tests)
test: build

# Run unit and integration tests across all supported compilers
test-all:
	@for compiler in dmd ldc2 gdc; do \
		echo "=== Testing with $$compiler ==="; \
		DC=$$compiler scripts/build.sh; \
	done

# Compile and run all example grammars with $(DC)
examples:
	DC=$(DC) scripts/examples.sh

# Compile and run examples across all compilers
examples-all:
	@for compiler in dmd ldc2 gdc; do \
		echo "=== Running examples with $$compiler ==="; \
		DC=$$compiler scripts/examples.sh; \
	done

# Run benchmarks against vendored Pegged
benchmark:
	DC=$(DC) scripts/benchmark.sh $(BENCH_FLAGS)

bench: benchmark

benchmark-checks:
	python3 scripts/benchmark_checks.py

benchmark-compare:
	DC=$(DC) python3 scripts/compare_benchmarks.py $(BENCH_FLAGS)

# Run benchmarks with allocator traffic measurements
benchmark-memory:
	DC=$(DC) scripts/benchmark.sh --memory $(BENCH_FLAGS)

bench-memory: benchmark-memory

# Measure and verify src/ coverage (>90% threshold required)
coverage:
	scripts/coverage.sh

# Verify @nogc compliance on hot paths (-vgc diagnostics)
hotpaths:
	scripts/hotpaths.sh

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
	DC=ldc2 ASAN_OPTIONS=detect_leaks=1 scripts/build.sh -fsanitize=address -g
	DC=gdc ASAN_OPTIONS=detect_leaks=1 scripts/build.sh -fsanitize=address,leak -g

# Run Valgrind Memcheck leak verification
valgrind:
	DC=ldc2 scripts/build.sh -g -O0
	timeout --preserve-status --kill-after=2s 120s valgrind \
		--tool=memcheck \
		--leak-check=full \
		--show-leak-kinds=all \
		--track-origins=yes \
		--errors-for-leak-kinds=definite,indirect \
		--error-exitcode=1 \
		build/ldc2/tests --DRT-testmode=run-main

# Run complete repository validation pipeline (all compilers, sanitizers, coverage, valgrind)
validate:
	scripts/validate.sh

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
	@echo "  test-all         Run unit/integration tests on dmd, ldc2, and gdc"
	@echo "  examples         Run examples with \$$(DC)"
	@echo "  examples-all     Run examples across dmd, ldc2, and gdc"
	@echo "  bench / benchmark Run benchmark suite against vendored Pegged"
	@echo "  benchmark-checks Verify benchmark units, integrations, and diagnostic coverage"
	@echo "  benchmark-compare Compare common outputs across D parsers and chumsky"
	@echo "  bench-memory     Run benchmark suite with allocator accounting"
	@echo "  coverage         Measure coverage and verify src/ >90% threshold"
	@echo "  hotpaths         Verify @nogc compliance on hot paths (-vgc)"
	@echo "  format           Format all .d files using dfmt"
	@echo "  check-format     Verify all .d files are properly formatted"
	@echo "  check-phobos     Verify zero Phobos imports in maintained code"
	@echo "  asan             Run AddressSanitizer & LeakSanitizer builds"
	@echo "  valgrind         Run Valgrind Memcheck memory leak validation"
	@echo "  validate         Run full validation suite (scripts/validate.sh)"
	@echo "  install-hooks    Install git pre-commit hooks"
	@echo "  clean            Remove build directory and temporary files"
	@echo ""
	@echo "Variables:"
	@echo "  DC               D compiler executable (default: dmd; e.g. DC=ldc2 or DC=gdc)"
	@echo "  BENCH_FLAGS      Additional flags for benchmark runner (e.g. BENCH_FLAGS='--iterations=100 --json')"
