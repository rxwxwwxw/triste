#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="fast"
for arg in "$@"; do
  case "$arg" in
    --full) MODE="full";;
    --fast) MODE="fast";;
  esac
done
if [[ "${FULL:-0}" == "1" ]] || [[ -n "${CI:-}" && "${1:-}" != "--fast" ]]; then
  MODE="full"
fi

if [[ "$MODE" == "full" ]]; then
  # GDC/gcov are coverage-collector dependencies, not compiler compliance targets.
  required_tools=(dmd ldc2 gdc dfmt valgrind timeout python3 gcov rg prlimit)
else
  required_tools=(ldc2 dfmt timeout python3 rg prlimit)
fi

for tool in "${required_tools[@]}"; do
  command -v "$tool" >/dev/null || { echo "Required validation tool missing: $tool" >&2; exit 2; }
done

if rg -n --glob '*.d' 'import[[:space:]]+(std\.|[^;]*,[[:space:]]*std\.)' src tests examples scripts benchmark; then
  echo 'Phobos imports are forbidden in maintained D code' >&2; exit 1
fi

while IFS= read -r -d '' file; do
  dfmt "$file" | cmp -s "$file" - || { echo "Run dfmt -i on $file" >&2; exit 1; }
done < <(find src tests examples scripts benchmark -name '*.d' -print0)

timeout 10s python3 tests/test_recursion_summary.py
timeout 10s python3 tests/test_peg_probe_summary.py
timeout 10s python3 tests/test_memo_dependencies.py

if [[ "$MODE" == "full" ]]; then
  COMPILERS="dmd ldc2" bash scripts/shared-records-check.sh
  COMPILERS="dmd ldc2" bash scripts/shared-output-check.sh
  COMPILERS="dmd ldc2" bash scripts/eligibility-check.sh
  COMPILERS="dmd ldc2" bash scripts/rule-effects-check.sh
  bash scripts/pure-islands-check.sh
  bash scripts/empty-scanner-check.sh
  for compiler in dmd ldc2; do
    DC=$compiler scripts/build.sh
    DC=$compiler bash scripts/differential.sh
    DC=$compiler scripts/examples.sh
  done
  timeout 10s python3 scripts/test_hooks.py
  scripts/hotpaths.sh
  scripts/coverage.sh
  DC=ldc2 ASAN_OPTIONS=detect_leaks=1:detect_stack_use_after_return=0 scripts/build.sh -fsanitize=address -g
  DC=ldc2 scripts/build.sh -g -O0
  timeout --preserve-status --kill-after=2s 120s valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes --errors-for-leak-kinds=definite,indirect --error-exitcode=1 build/ldc2/tests --DRT-testmode=run-main
  python3 scripts/benchmark_checks.py
  echo "Full validation passed (multi-compiler, coverage, ASan/LSan, Valgrind, benchmarks)."
else
  COMPILERS=ldc2 bash scripts/shared-records-check.sh
  COMPILERS=ldc2 BACKENDS=combinators MEMOS=selective PROJECTIONS=all bash scripts/shared-output-check.sh
  COMPILERS=ldc2 bash scripts/eligibility-check.sh
  COMPILERS=ldc2 bash scripts/rule-effects-check.sh
  COMPILERS=ldc2 MEMOS=selective PROJECTIONS=all bash scripts/pure-islands-check.sh
  COMPILERS=ldc2 bash scripts/empty-scanner-check.sh
  DC=ldc2 scripts/build.sh
  DC=ldc2 bash scripts/differential.sh
  DC=ldc2 scripts/examples.sh
  timeout 10s python3 scripts/test_hooks.py
  COMPILERS=ldc2 scripts/hotpaths.sh
  echo "Fast validation passed (LDC2 build, examples, hotpaths, hooks, formatting, zero Phobos)."
  echo "Run 'scripts/validate.sh --full' or 'make validate-full' for full sanitizer, Valgrind, and multi-compiler verification."
fi
